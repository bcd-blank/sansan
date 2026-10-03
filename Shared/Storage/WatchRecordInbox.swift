//
//  WatchRecordInbox.swift
//  Shared
//
//  Watch에서 도착한 완료 기록은 바로 저장하지 않고, 모음 탭에서 사용자가 가져오기를 시작할 때까지 보관합니다.
//

#if os(iOS)

import Combine
import Foundation

@MainActor
final class WatchRecordInbox: ObservableObject {
    static let shared = WatchRecordInbox()

    @Published private(set) var pendingCount = 0
    @Published private(set) var isImporting = false

    var hasPending: Bool { pendingCount > 0 }

    private init() {
        refreshCountFromDisk()
    }

    nonisolated private static var directoryURL: URL {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("WatchRecordInbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// WC 콜백 — JSON 디코드 없이 파일만 보관해 메인 진입을 막지 않습니다.
    nonisolated static func enqueueEncodedSession(_ data: Data) {
        guard !data.isEmpty else { return }
        Task.detached(priority: .utility) {
            let sessionID = peekSessionID(from: data) ?? UUID()
            let destination = directoryURL.appendingPathComponent("\(sessionID.uuidString).json")
            if let existing = try? Data(contentsOf: destination), existing.count >= data.count {
                await MainActor.run { WatchRecordInbox.shared.refreshCountFromDisk() }
                return
            }
            try? data.write(to: destination, options: .atomic)
            await MainActor.run {
                WatchRecordInbox.shared.didWriteInboxFile(sessionID: sessionID, at: destination)
            }
        }
    }

    func enqueue(session: HikingSessionData, encoded: Data) {
        let hasContent = session.elapsedTime > 0
            || session.totalDistance > 0
            || !session.points.isEmpty
            || !session.photos.isEmpty
        guard hasContent else { return }

        if HikingRecordStore.shared.records.contains(where: { $0.id == session.sessionID }) {
            return
        }

        WorkoutManager.shared.acknowledgeWatchInboundSession(session.sessionID)
        Self.enqueueEncodedSession(encoded)
    }

    func importPending() async {
        guard !isImporting else { return }
        isImporting = true
        defer {
            isImporting = false
            refreshCountFromDisk()
        }

        let directory = Self.directoryURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ))?
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                let right = (try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                return left > right
            }
            ?? []

        for fileURL in files {
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: fileURL)
            }.value
            try? FileManager.default.removeItem(at: fileURL)
            refreshCountFromDisk()

            guard let data, let session = try? HikingSessionData.decoded(from: data) else { continue }

            var finished = session
            finished.finalizeForPersistence()
            HikingRecordStore.shared.save(finished)
            WorkoutManager.shared.acknowledgeWatchInboundSession(finished.sessionID)
        }
    }

    func refreshCountFromDisk() {
        let directory = Self.directoryURL
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ))?
            .filter { $0.pathExtension.lowercased() == "json" }
            ?? []
        pendingCount = files.count
    }

    private func didWriteInboxFile(sessionID: UUID, at url: URL) {
        if HikingRecordStore.shared.records.contains(where: { $0.id == sessionID }) {
            try? FileManager.default.removeItem(at: url)
        } else {
            WorkoutManager.shared.acknowledgeWatchInboundSession(sessionID)
        }
        refreshCountFromDisk()
    }

    nonisolated private static func peekSessionID(from data: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let raw = object["sessionID"] as? String {
            return UUID(uuidString: raw)
        }
        return nil
    }
}

#endif
