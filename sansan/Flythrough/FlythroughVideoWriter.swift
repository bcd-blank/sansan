//
//  FlythroughVideoWriter.swift
//  sansan
//
//  프레임(UIImage)을 H.264 MP4로 인코딩하고, 선택적으로 배경음악을 머지합니다.
//

#if os(iOS)

import AVFoundation
import UIKit

enum FlythroughVideoWriterError: Error {
    case cannotCreateWriter
    case cannotStart
    case pixelBufferFailed
    case finishFailed
    case exportFailed
}

/// 프레임을 비디오 트랙으로 인코딩하는 라이터.
/// 액터 — 픽셀 버퍼 변환·인코딩을 메인 스레드 밖에서 수행해 지도 렌더와 겹칠 수 있습니다.
actor FlythroughVideoWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let pixelSize: CGSize
    private let frameDuration: CMTime
    private var frameIndex: Int = 0

    let outputURL: URL

    init(size: CGSize, framesPerSecond: Int) throws {
        // 인코더는 짝수 픽셀을 선호합니다.
        let width = Int(size.width.rounded()) & ~1
        let height = Int(size.height.rounded()) & ~1
        pixelSize = CGSize(width: max(width, 2), height: max(height, 2))
        let fps = max(framesPerSecond, 1)
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flythrough-\(UUID().uuidString).mp4")
        outputURL = url
        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            throw FlythroughVideoWriterError.cannotCreateWriter
        }
        self.writer = writer

        // HEVC + 해상도·fps 비례 비트레이트 — 위성 영상은 텍스처가 복잡해 낮은 비트레이트에서
        // 쉽게 뭉개집니다. 0.25 bpp 기준, FHD 30fps ≈ 15.5Mbps.
        let pixelsPerSecond = Double(width * height) * Double(fps)
        let bitrate = min(max(Int(pixelsPerSecond * 0.25), 12_000_000), 35_000_000)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: pixelSize.width,
            AVVideoHeightKey: pixelSize.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoMaxKeyFrameIntervalKey: fps * 2,
                AVVideoExpectedSourceFrameRateKey: fps,
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        self.input = input

        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: pixelSize.width,
            kCVPixelBufferHeightKey as String: pixelSize.height
        ]
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attributes
        )

        guard writer.canAdd(input) else { throw FlythroughVideoWriterError.cannotCreateWriter }
        writer.add(input)
    }

    func start() throws {
        guard writer.startWriting() else {
            throw FlythroughVideoWriterError.cannotStart
        }
        writer.startSession(atSourceTime: .zero)
    }

    func append(_ image: UIImage) async throws {
        while !input.isReadyForMoreMediaData {
            try? await Task.sleep(for: .milliseconds(5))
        }
        guard let pool = adaptor.pixelBufferPool,
              let buffer = makePixelBuffer(from: image, pool: pool) else {
            throw FlythroughVideoWriterError.pixelBufferFailed
        }
        let time = CMTimeMultiply(frameDuration, multiplier: Int32(frameIndex))
        adaptor.append(buffer, withPresentationTime: time)
        frameIndex += 1
    }

    func finish() async throws -> URL {
        input.markAsFinished()
        let endTime = CMTimeMultiply(frameDuration, multiplier: Int32(max(frameIndex, 1)))
        writer.endSession(atSourceTime: endTime)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else {
            throw FlythroughVideoWriterError.finishFailed
        }
        return outputURL
    }

    private func makePixelBuffer(from image: UIImage, pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer,
              let cgImage = image.cgImage else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            return nil
        }

        context.draw(cgImage, in: CGRect(origin: .zero, size: pixelSize))
        return buffer
    }
}

/// 비디오에 배경음악을 머지합니다.
enum FlythroughAudioMixer {
    static func merge(videoURL: URL, audioURL: URL) async throws -> URL {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw FlythroughVideoWriterError.exportFailed
        }

        let duration = try await videoAsset.load(.duration)
        let videoRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(videoRange, of: videoTrack, at: .zero)

        if let audioTrack = try? await audioAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            let audioDuration = try await audioAsset.load(.duration)
            var inserted = CMTime.zero
            while inserted < duration {
                let remaining = duration - inserted
                let chunk = min(audioDuration, remaining)
                let range = CMTimeRange(start: .zero, duration: chunk)
                try? compositionAudioTrack.insertTimeRange(range, of: audioTrack, at: inserted)
                inserted = inserted + chunk
                if chunk.seconds <= 0 { break }
            }
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flythrough-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: outputURL)

        // Passthrough — 비디오 트랙을 재인코딩하지 않고 그대로 먹싱(화질 손실·추가 시간 방지).
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw FlythroughVideoWriterError.exportFailed
        }
        do {
            try await export.export(to: outputURL, as: .mp4)
        } catch {
            throw FlythroughVideoWriterError.exportFailed
        }
        return outputURL
    }
}

#endif
