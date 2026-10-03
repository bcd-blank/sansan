//
//  HikingGPXImporter.swift
//  Shared
//

import Foundation

enum HikingGPXImporter {
    struct ParsedTrack: Sendable {
        let sessionData: HikingSessionData
        let endedAt: Date
        let displayName: String?
    }

    enum ImportError: LocalizedError, Sendable {
        case unreadableFile
        case invalidFormat(String)
        case insufficientPoints
        case noUser

        var errorDescription: String? {
            switch self {
            case .unreadableFile:
                return "GPX 파일을 읽을 수 없습니다."
            case .invalidFormat(let detail):
                return "GPX 형식을 해석하지 못했습니다. \(detail)"
            case .insufficientPoints:
                return "GPS 포인트가 2개 이상 있는 GPX 파일이 필요합니다."
            case .noUser:
                return "사용자를 선택한 뒤 다시 시도해 주세요."
            }
        }
    }

    nonisolated static func parse(url: URL) throws -> ParsedTrack {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadableFile
        }
        return try parse(data: data, suggestedName: url.deletingPathExtension().lastPathComponent)
    }

    nonisolated static func parse(data: Data, suggestedName: String) throws -> ParsedTrack {
        try runOnMainActor {
            try parseOnMainActor(data: data, suggestedName: suggestedName)
        }
    }

    nonisolated private static func runOnMainActor<T>(_ work: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(work)
        }
        return try DispatchQueue.main.sync {
            try work()
        }
    }

    @MainActor
    private static func parseOnMainActor(data: Data, suggestedName: String) throws -> ParsedTrack {
        let delegate = GPXParseDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            if let parseError = delegate.parseError {
                throw ImportError.invalidFormat(parseError)
            }
            throw ImportError.invalidFormat("XML 파싱에 실패했습니다.")
        }

        guard let segment = delegate.longestSegment, segment.points.count >= 2 else {
            throw ImportError.insufficientPoints
        }

        let resolvedPoints = resolveTimestamps(
            segment.points,
            metadataTime: delegate.metadataTime
        )
        let startedAt = resolvedPoints.first?.timestamp
        let endedAt = resolvedPoints.last?.timestamp ?? Date()
        let elapsedTime: TimeInterval
        if let startedAt {
            elapsedTime = max(0, endedAt.timeIntervalSince(startedAt))
        } else {
            elapsedTime = 0
        }

        var session = HikingSessionData(
            sessionID: UUID(),
            state: .idle,
            startedAt: startedAt,
            totalDistance: 0,
            elapsedTime: elapsedTime,
            currentAltitude: resolvedPoints.last?.altitude ?? 0,
            points: resolvedPoints,
            lastUpdated: endedAt
        )
        session.finalizeForPersistence()

        let displayName = SavedHikingSession.normalizedDisplayName(
            segment.trackName ?? delegate.routeName ?? suggestedName
        )

        return ParsedTrack(
            sessionData: session,
            endedAt: endedAt,
            displayName: displayName
        )
    }

    private static func resolveTimestamps(
        _ rawPoints: [GPXRawPoint],
        metadataTime: Date?
    ) -> [HikingPoint] {
        guard !rawPoints.isEmpty else { return [] }

        let anchorEnd = metadataTime ?? Date()
        if rawPoints.allSatisfy({ $0.timestamp == nil }) {
            return rawPoints.enumerated().map { index, point in
                let offset = TimeInterval(rawPoints.count - 1 - index)
                return HikingPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    timestamp: anchorEnd.addingTimeInterval(-offset)
                )
            }
        }

        var timestamps = rawPoints.map(\.timestamp)
        if timestamps.first == nil, let firstKnown = timestamps.compactMap({ $0 }).first {
            timestamps[0] = firstKnown
        }
        if timestamps.last == nil, let lastKnown = timestamps.compactMap({ $0 }).last {
            timestamps[timestamps.count - 1] = lastKnown
        }

        for index in timestamps.indices where timestamps[index] == nil {
            var previousIndex: Int?
            var nextIndex: Int?
            if index > 0 {
                previousIndex = (0..<index).reversed().first(where: { timestamps[$0] != nil })
            }
            if index < timestamps.count - 1 {
                nextIndex = ((index + 1)..<timestamps.count).first(where: { timestamps[$0] != nil })
            }

            switch (previousIndex, nextIndex) {
            case let (previous?, next?):
                let previousTime = timestamps[previous]!
                let nextTime = timestamps[next]!
                let ratio = Double(index - previous) / Double(next - previous)
                timestamps[index] = previousTime.addingTimeInterval(
                    nextTime.timeIntervalSince(previousTime) * ratio
                )
            case let (previous?, nil):
                timestamps[index] = timestamps[previous]!
            case let (nil, next?):
                timestamps[index] = timestamps[next]!
            case (nil, nil):
                timestamps[index] = anchorEnd
            }
        }

        return zip(rawPoints, timestamps).map { point, timestamp in
            HikingPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                timestamp: timestamp ?? anchorEnd
            )
        }
    }
}

private struct GPXRawPoint {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: Date?
}

private struct GPXSegment {
    var trackName: String?
    var points: [GPXRawPoint] = []
}

private final class GPXParseDelegate: NSObject, XMLParserDelegate {
    private(set) var metadataTime: Date?
    private(set) var routeName: String?
    private(set) var parseError: String?

    private var segments: [GPXSegment] = []
    private var currentSegment = GPXSegment()
    private var currentPoint: GPXRawPoint?
    private var currentText = ""
    private var elementStack: [String] = []
    private var collectingTrackPoints = false
    private var collectingRoutePoints = false

    var longestSegment: GPXSegment? {
        segments.max(by: { $0.points.count < $1.points.count })
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        elementStack.append(name)
        currentText = ""

        switch name {
        case "trk":
            currentSegment = GPXSegment()
            collectingTrackPoints = true
            collectingRoutePoints = false
        case "trkseg":
            if collectingTrackPoints, !currentSegment.points.isEmpty {
                segments.append(currentSegment)
                currentSegment = GPXSegment(trackName: currentSegment.trackName)
            }
        case "trkpt":
            guard collectingTrackPoints,
                  let latitude = doubleAttribute("lat", in: attributeDict),
                  let longitude = doubleAttribute("lon", in: attributeDict)
            else { return }
            currentPoint = GPXRawPoint(
                latitude: latitude,
                longitude: longitude,
                altitude: 0,
                timestamp: nil
            )
        case "rte":
            collectingRoutePoints = true
            collectingTrackPoints = false
            currentSegment = GPXSegment()
        case "rtept":
            guard collectingRoutePoints,
                  let latitude = doubleAttribute("lat", in: attributeDict),
                  let longitude = doubleAttribute("lon", in: attributeDict)
            else { return }
            currentPoint = GPXRawPoint(
                latitude: latitude,
                longitude: longitude,
                altitude: 0,
                timestamp: nil
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = localName(elementName)
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            _ = elementStack.popLast()
            currentText = ""
        }

        switch name {
        case "time":
            if elementStack.dropLast().last == "metadata", let date = parseGPXTime(text) {
                metadataTime = date
            } else if var point = currentPoint, let date = parseGPXTime(text) {
                point = GPXRawPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    timestamp: date
                )
                currentPoint = point
            }
        case "ele":
            if var point = currentPoint, let elevation = Double(text) {
                point = GPXRawPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: elevation,
                    timestamp: point.timestamp
                )
                currentPoint = point
            }
        case "name":
            if elementStack.dropLast().last == "trk", !text.isEmpty {
                currentSegment.trackName = text
            } else if elementStack.dropLast().last == "rte", !text.isEmpty {
                routeName = text
            }
        case "trkpt":
            if let point = currentPoint {
                currentSegment.points.append(point)
            }
            currentPoint = nil
        case "rtept":
            if let point = currentPoint {
                currentSegment.points.append(point)
            }
            currentPoint = nil
        case "trk":
            if !currentSegment.points.isEmpty {
                segments.append(currentSegment)
            }
            collectingTrackPoints = false
            currentSegment = GPXSegment()
        case "rte":
            if !currentSegment.points.isEmpty {
                segments.append(currentSegment)
            }
            collectingRoutePoints = false
            currentSegment = GPXSegment()
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError.localizedDescription
    }

    private func localName(_ elementName: String) -> String {
        elementName.split(separator: ":").last.map(String.init) ?? elementName
    }

    private func doubleAttribute(_ key: String, in attributes: [String: String]) -> Double? {
        if let value = attributes[key], let number = Double(value) {
            return number
        }
        let lowercasedKey = key.lowercased()
        for (attributeKey, value) in attributes where attributeKey.lowercased() == lowercasedKey {
            if let number = Double(value) {
                return number
            }
        }
        return nil
    }

    private func parseGPXTime(_ value: String) -> Date? {
        if let date = iso8601WithFractional.date(from: value) {
            return date
        }
        if let date = iso8601Standard.date(from: value) {
            return date
        }
        return legacyGPXFormatter.date(from: value)
    }

    private let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private lazy var legacyGPXFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()
}
