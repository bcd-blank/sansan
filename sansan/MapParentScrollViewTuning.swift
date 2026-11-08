//
//  MapParentScrollViewTuning.swift
//  sansan
//
//  ScrollView 안 Map 제스처가 스크롤·버튼 탭과 충돌하지 않도록 부모 UIScrollView를 조정합니다.
//

#if os(iOS)

import SwiftUI
import UIKit

struct MapParentScrollViewTuning: UIViewRepresentable {
    func makeUIView(context: Context) -> TuningAnchorView {
        let view = TuningAnchorView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TuningAnchorView, context: Context) {
        uiView.applyIfNeeded()
    }

    final class TuningAnchorView: UIView {
        private var didApply = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            didApply = false
            applyIfNeeded()
        }

        func applyIfNeeded() {
            guard window != nil, !didApply else { return }
            guard let scrollView = findScrollView(startingAt: superview) else { return }
            scrollView.delaysContentTouches = false
            scrollView.canCancelContentTouches = true
            didApply = true
        }

        private func findScrollView(startingAt view: UIView?) -> UIScrollView? {
            var candidate = view
            while let current = candidate {
                if let scrollView = current as? UIScrollView {
                    return scrollView
                }
                candidate = current.superview
            }
            return nil
        }
    }
}

#endif
