//
//  GPXDocumentPicker.swift
//  sansan
//

#if os(iOS)

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct GPXDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let gpxType = UTType(filenameExtension: "gpx", conformingTo: .xml) ?? .xml
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [gpxType], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: GPXDocumentPicker

        init(parent: GPXDocumentPicker) {
            self.parent = parent
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.dismiss()
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            defer { parent.dismiss() }
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

/// GPX 파일 선택 시트 — 상단에 항상 보이는 닫기 버튼을 제공합니다.
struct GPXDocumentPickerSheet: View {
    let onPick: (URL) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GPXDocumentPicker { url in
                onPick(url)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("GPX 가져오기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#endif
