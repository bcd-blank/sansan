//
//  HikingGPXExporter.swift
//  Shared
//
//  Strava, Garmin 등 GPX 가져오기 앱용 경로 파일.
//

import Foundation

enum HikingGPXExporter {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func canExport(record: SavedHikingSession) -> Bool {
        record.session.points.count >= 2
    }

    static func temporaryFileURL(for record: SavedHikingSession) throws -> URL {
        guard canExport(record: record) else {
            throw ExportError.insufficientPoints
        }

        let gpx = generateGPX(for: record)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(for: record))

        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func generateGPX(for record: SavedHikingSession) -> String {
        let points = record.session.points.sorted { $0.timestamp < $1.timestamp }
        let trackName = xmlEscaped(record.shareTrackName)
        let metadataTime = iso8601.string(from: record.endedAt)

        var lines: [String] = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<gpx version="1.1" creator="sansan" xmlns="http://www.topografix.com/GPX/1/1">"#,
            "  <metadata>",
            "    <time>\(metadataTime)</time>",
            "  </metadata>",
            "  <trk>",
            "    <name>\(trackName)</name>",
            "    <trkseg>",
        ]

        for point in points {
            lines.append(
                """
                  <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                    <ele>\(point.altitude)</ele>
                    <time>\(iso8601.string(from: point.timestamp))</time>
                  </trkpt>
                """
            )
        }

        lines += [
            "    </trkseg>",
            "  </trk>",
            "</gpx>",
        ]

        return lines.joined(separator: "\n")
    }

    private static func fileName(for record: SavedHikingSession) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "sansan-\(formatter.string(from: record.endedAt)).gpx"
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    enum ExportError: Error {
        case insufficientPoints
    }
}

private extension SavedHikingSession {
    var shareTrackName: String {
        if let startedAt {
            let start = startedAt.formatted(date: .abbreviated, time: .shortened)
            let end = endedAt.formatted(date: .omitted, time: .shortened)
            return "sansan \(start) – \(end)"
        }
        return "sansan \(endedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
