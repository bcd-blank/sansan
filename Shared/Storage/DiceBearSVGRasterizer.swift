//
//  DiceBearSVGRasterizer.swift
//  Shared
//

#if os(iOS)

import PDFKit
import UIKit
import WebKit

enum DiceBearSVGRasterizer {
    @MainActor
    static func image(fromSVG data: Data, dimension: CGFloat = 256) async -> UIImage? {
        await rasterizeWithWebKit(data, dimension: dimension)
    }

    @MainActor
    private static func rasterizeWithWebKit(_ data: Data, dimension: CGFloat) async -> UIImage? {
        guard let svg = String(data: data, encoding: .utf8) else { return nil }

        let size = CGSize(width: dimension, height: dimension)
        let webView = WKWebView(frame: CGRect(origin: .zero, size: size))
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        if let window = keyWindow() {
            webView.alpha = 0.02
            webView.frame = CGRect(origin: .zero, size: size)
            window.addSubview(webView)
        }

        defer { webView.removeFromSuperview() }

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=\(Int(dimension)),height=\(Int(dimension)),initial-scale=1,maximum-scale=1">
        <style>
          html, body { margin: 0; padding: 0; width: \(Int(dimension))px; height: \(Int(dimension))px; overflow: hidden; background: transparent; }
          svg { width: \(Int(dimension))px; height: \(Int(dimension))px; display: block; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """

        do {
            try await loadHTML(html, in: webView)
            webView.setNeedsLayout()
            webView.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 120_000_000)

            if let image = try? await pdfImage(from: webView, size: size) {
                return image
            }

            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(origin: .zero, size: size)
            configuration.afterScreenUpdates = true
            return try await webView.takeSnapshot(configuration: configuration)
        } catch {
            return nil
        }
    }

    @MainActor
    private static func pdfImage(from webView: WKWebView, size: CGSize) async throws -> UIImage? {
        let pdfConfiguration = WKPDFConfiguration()
        pdfConfiguration.rect = CGRect(origin: .zero, size: size)
        let pdfData = try await webView.pdf(configuration: pdfConfiguration)
        guard let page = PDFDocument(data: pdfData)?.page(at: 0) else {
            return nil
        }
        return page.thumbnail(of: size, for: .mediaBox)
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first
    }

    @MainActor
    private static func loadHTML(_ html: String, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let waiter = NavigationWaiter(continuation: continuation)
            objc_setAssociatedObject(webView, &WaiterKey.value, waiter, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            webView.navigationDelegate = waiter
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

private enum WaiterKey {
    static var value: UInt8 = 0
}

private final class NavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resume(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

#endif
