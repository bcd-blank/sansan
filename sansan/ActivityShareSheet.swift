//
//  ActivityShareSheet.swift
//  sansan
//

#if os(iOS)

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// SwiftUI `.sheet` 중첩 없이 최상위 화면에서 공유 시트를 띄웁니다.
@MainActor
enum ActivitySharePresenter {
    @discardableResult
    static func present(
        items: [Any],
        mode: ShareSheetMode,
        onComplete: (() -> Void)? = nil
    ) -> Bool {
        guard !items.isEmpty else { return false }
        guard let presenter = KeyWindow.activityPresenter() else { return false }

        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        controller.excludedActivityTypes = mode.excludedActivityTypes
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in
                onComplete?()
            }
        }

        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }

        presenter.present(controller, animated: true)
        return true
    }
}

/// GPX — GPX 가져오기를 등록한 앱 위주로 표시합니다 (메모·제미나이 등 범용 앱 제외).
@MainActor
enum GPXSharePresenter {
    @discardableResult
    static func present(fileURL: URL, title: String) -> Bool {
        guard let presenter = KeyWindow.activityPresenter() else { return false }

        if GPXDocumentShareCoordinator.shared.present(fileURL: fileURL, from: presenter) {
            return true
        }

        let item = GPXFileShareActivityItem(fileURL: fileURL, title: title)
        return ActivitySharePresenter.present(items: [item], mode: .gpxFile)
    }
}

@MainActor
private final class GPXDocumentShareCoordinator: NSObject, UIDocumentInteractionControllerDelegate {
    static let shared = GPXDocumentShareCoordinator()

    private var activeController: UIDocumentInteractionController?

    @discardableResult
    func present(fileURL: URL, from presenter: UIViewController) -> Bool {
        let documentController = UIDocumentInteractionController(url: fileURL)
        documentController.uti = UTType.hikingGPX.identifier
        documentController.name = fileURL.deletingPathExtension().lastPathComponent
        documentController.delegate = self
        activeController = documentController

        let anchor = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 1,
            height: 1
        )

        if documentController.presentOpenInMenu(from: anchor, in: presenter.view, animated: true) {
            return true
        }

        activeController = nil
        return false
    }

    func documentInteractionControllerDidDismissOpenInMenu(
        _ controller: UIDocumentInteractionController
    ) {
        activeController = nil
    }

    func documentInteractionControllerDidDismissOptionsMenu(
        _ controller: UIDocumentInteractionController
    ) {
        activeController = nil
    }
}

@MainActor
private enum KeyWindow {
    /// 현재 보이는 최상위 화면 — 기록 목록 `fullScreenCover` 위에서 공유 시트를 띄웁니다.
    static func activityPresenter() -> UIViewController? {
        guard let root = foregroundRootViewController() else { return nil }

        var top = root
        while let presented = top.presentedViewController {
            if presented.isBeingDismissed { break }
            top = presented
        }

        return deepestVisibleViewController(from: top)
    }

    private static func foregroundRootViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }
            .flatMap { scene in
                scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first
            }
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        return window?.rootViewController
    }

    private static func deepestVisibleViewController(from viewController: UIViewController) -> UIViewController {
        if let navigation = viewController as? UINavigationController,
           let visible = navigation.visibleViewController {
            return deepestVisibleViewController(from: visible)
        }
        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return deepestVisibleViewController(from: selected)
        }
        return viewController
    }
}

#endif
