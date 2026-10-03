//
//  HikingRecordListComponents.swift
//  sansan
//

#if os(iOS)

import SwiftUI
import UIKit

struct RecordRenameSheet: View {
    @Binding var draft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SelectAllOnFocusTextField(placeholder: "이름", text: $draft)
                        .frame(height: 28)
                } footer: {
                    Text("비우면 시작·종료 시각이 기본 이름으로 돌아갑니다.")
                }
            }
            .navigationTitle("기록 이름")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}

struct BodyMassEditSheet: View {
    @Binding var draft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        DecimalFocusTextField(
                            placeholder: "\(Int(BodyMetricsPreferences.defaultBodyMassKilograms))",
                            text: $draft
                        )
                        .frame(height: 28)

                        Text("kg")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("아이폰 단독 기록의 칼로리 추정에 사용됩니다.")
                }
            }
            .navigationTitle("체중")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("확인", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }
}

struct RecordMemoSheet: View {
    @Binding var draft: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AutoFocusMemoTextView(placeholder: "메모를 입력하세요", text: $draft)
                        .frame(minHeight: 88)
                } footer: {
                    Text("비우면 메모가 표시되지 않습니다.")
                }
            }
            .navigationTitle("메모")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장", action: onSave)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }
}

/// 메모 시트 — 시트와 함께 키보드가 바로 올라오도록 UIKit 포커스를 사용합니다.
struct AutoFocusMemoTextView: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = text.isEmpty ? .placeholderText : .label
        textView.isScrollEnabled = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default

        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = .placeholderText
        } else {
            textView.text = text
            textView.textColor = .label
        }

        DispatchQueue.main.async {
            textView.becomeFirstResponder()
        }
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        guard !uiView.isFirstResponder else { return }

        if text.isEmpty {
            if uiView.text != placeholder || uiView.textColor != .placeholderText {
                uiView.text = placeholder
                uiView.textColor = .placeholderText
            }
        } else if uiView.text != text || uiView.textColor == .placeholderText {
            uiView.text = text
            uiView.textColor = .label
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: AutoFocusMemoTextView

        init(parent: AutoFocusMemoTextView) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == .placeholderText {
                textView.text = parent.text
                textView.textColor = .label
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.textColor != .placeholderText else { return }
            let limited = String(textView.text.prefix(SavedHikingSession.maxMemoLength))
            if limited != textView.text {
                textView.text = limited
            }
            parent.text = limited
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard textView.textColor != .placeholderText else {
                parent.text = ""
                return
            }
            parent.text = textView.text
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = .placeholderText
            }
        }
    }
}

/// 이름 수정 시 기존 텍스트를 전체 선택해 바로 덮어쓸 수 있게 합니다.
struct SelectAllOnFocusTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.autocorrectionType = .default
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        private var didSelectAll = false

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard !didSelectAll else { return }
            didSelectAll = true
            textField.selectAll(nil)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// 체중 입력 — 숫자 키패드, 시트와 함께 키보드가 바로 올라오도록 UIKit 포커스를 사용합니다.
struct DecimalFocusTextField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.clearButtonMode = .whileEditing
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.delegate = context.coordinator
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }
    }
}

struct RecordTrailingSwipeActions: ViewModifier {
    let record: SavedHikingSession
    let onDelete: (UUID) -> Void
    let togglePin: (UUID) -> Void
    let toggleFavorite: (UUID) -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete(record.id)
                } label: {
                    Label("삭제", systemImage: "trash")
                }

                Button {
                    togglePin(record.id)
                } label: {
                    Label(
                        record.isListPinned ? "고정 해제" : "상단 고정",
                        systemImage: record.isListPinned ? "pin.slash" : "pin"
                    )
                }
                .tint(.indigo)

                Button {
                    toggleFavorite(record.id)
                } label: {
                    Label(
                        record.isFavorite ? "즐겨찾기 해제" : "즐겨찾기",
                        systemImage: record.isFavorite ? "star.slash" : "star"
                    )
                }
                .tint(.yellow)
            }
    }
}

struct RecordsListTabBar: View {
    @Binding var selection: RecordsListTab
    let savedCount: Int
    let importedCount: Int

    @Environment(\.chromeCapsuleHeight) private var capsuleHeight
    @Namespace private var tabIndicatorNamespace

    private let capsuleInset = iPhoneBottomChromeLayout.tabCapsuleInset
    private let selectionInset = iPhoneBottomChromeLayout.selectionInset

    private var tabContentHeight: CGFloat {
        iPhoneBottomChromeLayout.tabContentHeight(forCapsuleHeight: capsuleHeight)
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(RecordsListTab.allCases) { tab in
                    tabButton(tab)
                        .glassEffectID(tab, in: tabIndicatorNamespace)
                }
            }
            .frame(height: tabContentHeight)
            .padding(capsuleInset)
            .background {
                tabSelectionIndicator
            }
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID("recordsListTabs", in: tabIndicatorNamespace)
        }
        .frame(height: capsuleHeight)
        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding)
        .padding(.vertical, iPhoneBottomChromeLayout.recordsTabBarVerticalPadding)
    }

    @ViewBuilder
    private var tabSelectionIndicator: some View {
        GeometryReader { geometry in
            let tabCount = CGFloat(RecordsListTab.allCases.count)
            let itemWidth = geometry.size.width / tabCount
            let selectedIndex = CGFloat(RecordsListTab.allCases.firstIndex(of: selection) ?? 0)
            let inset = selectionInset

            Capsule()
                .fill(Color.primary.opacity(0.1))
                .frame(
                    width: max(itemWidth - inset * 2, 0),
                    height: max(geometry.size.height - inset * 2, 0)
                )
                .offset(x: itemWidth * selectedIndex + inset, y: inset)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selection)
        }
    }

    private func tabButton(_ tab: RecordsListTab) -> some View {
        let isSelected = selection == tab
        let count = count(for: tab)

        return Button {
            guard selection != tab else { return }
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .symbolVariant(isSelected ? .fill : .none)

                Text(tab.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            (isSelected ? RecordsListChrome.accent : Color.secondary).opacity(0.16),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isSelected ? RecordsListChrome.accent : Color.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: tab, count: count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func count(for tab: RecordsListTab) -> Int {
        switch tab {
        case .saved: savedCount
        case .imported: importedCount
        }
    }

    private func accessibilityLabel(for tab: RecordsListTab, count: Int) -> String {
        if count > 0 {
            return "\(tab.title), \(count)개"
        }
        return tab.title
    }
}

struct HikingRecordRow: View {
    enum RecordListMarker {
        case none
        case favorite
        case pinned
    }

    let record: SavedHikingSession
    var listMarker: RecordListMarker = .none
    var allowsRename: Bool = true
    var onRename: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RecordThumbnailView(record: record)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(record.listTitle)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    listMarkerIcon

                    if allowsRename {
                        Button(action: onRename) {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("기록 이름 수정")
                    }
                }

                HStack(spacing: 6) {
                    RecordMetricChip(icon: "clock", text: record.formattedDurationCompact, tint: .blue)
                    RecordMetricChip(icon: "figure.hiking", text: record.formattedDistance, tint: .green)
                    RecordMetricChip(icon: "arrow.up.right", text: record.formattedElevationGain, tint: .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var listMarkerIcon: some View {
        switch listMarker {
        case .none:
            EmptyView()
        case .favorite:
            Image(systemName: "star.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.yellow)
                .accessibilityLabel("즐겨찾기")
        case .pinned:
            Image(systemName: "pin.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.indigo)
                .accessibilityLabel("상단 고정")
        }
    }
}

struct RecordMetricChip: View {
    let icon: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct RecordThumbnailView: View {
    let record: SavedHikingSession
    @ObservedObject private var store = HikingRecordStore.shared
    @State private var thumbnailImage: UIImage?

    private var isRegenerating: Bool {
        store.regeneratingRecordID == record.id
    }

    var body: some View {
        ZStack {
            Group {
                if let thumbnailImage {
                    Image(uiImage: thumbnailImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Color(.tertiarySystemFill)
                        Image(systemName: "map")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if isRegenerating {
                Color.black.opacity(0.28)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: isRegenerating)
        .task(id: store.snapshotRevision(for: record.id)) {
            guard let path = record.snapshotFileURL?.path else {
                thumbnailImage = nil
                // 기록 종료 직후 생성이 실패한 기록 — 목록에 보이면 자동으로 다시 생성합니다.
                await store.ensureSnapshotExists(for: record.id)
                return
            }
            let loaded = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: path)
            }.value
            thumbnailImage = loaded
            if loaded == nil {
                // PNG 파일이 삭제·유실된 경우도 자동 복구합니다.
                await store.ensureSnapshotExists(for: record.id)
            }
        }
    }
}

#endif
