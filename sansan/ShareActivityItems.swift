//
//  ShareActivityItems.swift
//  sansan
//
//  공유 시트에 넘길 항목 — 콘텐츠 종류별 UTI·메타데이터·제외 활동.
//

#if os(iOS)

import LinkPresentation
import UIKit
import UniformTypeIdentifiers

extension UTType {
    static var hikingGPX: UTType {
        if let type = UTType(filenameExtension: "gpx") {
            return type
        }
        return UTType(importedAs: "com.topografix.gpx")
    }
}

/// 기록 카드 이미지 vs GPX 파일 — iOS가 적합한 앱을 골라 표시합니다.
enum ShareSheetMode {
    case recordCard
    case gpxFile

    /// 특정 서드파티 앱만 고를 수는 없고, 시스템·부적합 활동만 숨깁니다.
    var excludedActivityTypes: [UIActivity.ActivityType] {
        switch self {
        case .recordCard:
            return [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .print,
                .markupAsPDF,
                .collaborationCopyLink,
                .collaborationInviteWithLink,
            ]
        case .gpxFile:
            return [
                .assignToContact,
                .addToReadingList,
                .openInIBooks,
                .print,
                .markupAsPDF,
                .saveToCameraRoll,
                .copyToPasteboard,
                .mail,
                .message,
                .postToFacebook,
                .postToTwitter,
                .postToWeibo,
                .postToTencentWeibo,
                .postToVimeo,
                .postToFlickr,
                .collaborationCopyLink,
                .collaborationInviteWithLink,
            ]
        }
    }
}

/// SNS·메시지 공유에 맞춘 기록 카드 이미지.
final class RecordCardShareActivityItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        image
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.imageProvider = NSItemProvider(object: image)
        return metadata
    }
}

/// GPX UTI 전용 ItemProvider — 범용 URL보다 경로 앱만 골라 표시하기 쉽습니다.
final class GPXFileShareActivityItem: NSObject, UIActivityItemSource {
    let fileURL: URL
    let title: String
    private let itemProvider: NSItemProvider

    init(fileURL: URL, title: String) {
        self.fileURL = fileURL
        self.title = title
        let provider = NSItemProvider()
        provider.suggestedName = fileURL.deletingPathExtension().lastPathComponent
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.hikingGPX.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            completion(fileURL, true, nil)
            return nil
        }
        self.itemProvider = provider
        super.init()
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        itemProvider
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        itemProvider
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        UTType.hikingGPX.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title
    }

    func activityViewControllerLinkMetadata(
        _ activityViewController: UIActivityViewController
    ) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = fileURL
        metadata.iconProvider = NSItemProvider(
            object: UIImage(systemName: "map.fill") ?? UIImage()
        )
        return metadata
    }
}

#endif
