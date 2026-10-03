//
//  KMSCCourseBrowseView.swift
//  sansan
//
//  KMSC 공공 코스 브라우즈 — 검색·따라가기·내 모음 추가.
//

#if os(iOS)

import SwiftUI

struct KMSCCourseBrowseView: View {
    var onFollowRoute: (() -> Void)?

    @ObservedObject private var store = HikingRecordStore.shared
    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var detailCourse: KMSCCourseEntry?

    private var filteredCourses: [KMSCCourseEntry] {
        KMSCCourseCatalog.search(query: searchText, category: selectedCategory)
    }

    private var courseSections: [(title: String, courses: [KMSCCourseEntry])] {
        let grouped = Dictionary(grouping: filteredCourses, by: \.groupName)
        return grouped.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.compactMap { key in
            guard let courses = grouped[key], !courses.isEmpty else { return nil }
            return (key, courses)
        }
    }

    var body: some View {
        Group {
            if !KMSCCourseCatalog.isCatalogAvailable {
                ContentUnavailableView {
                    Label("코스 데이터 없음", systemImage: "book.closed")
                } description: {
                    Text("코스 목록 파일을 확인해 주세요.")
                }
            } else if filteredCourses.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List {
                    ForEach(courseSections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.courses) { course in
                                Button {
                                    detailCourse = course
                                } label: {
                                    KMSCCourseRow(
                                        course: course,
                                        isInCollection: store.recordID(forBundledRouteID: course.id) != nil
                                    )
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("한국등산트레킹지원센터 제공 코스")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "산·코스 검색")
        .safeAreaInset(edge: .top, spacing: 0) {
            categoryFilterBar
        }
        .navigationDestination(item: $detailCourse) { course in
            KMSCCourseDetailView(entry: course, onFollowRoute: onFollowRoute)
        }
        .onAppear {
#if DEBUG
            applyAppStoreScreenshotModeIfNeeded()
#endif
        }
    }

#if DEBUG
    private func applyAppStoreScreenshotModeIfNeeded() {
        guard AppStoreScreenshotMode.current?.opensKMSCCourseDetail == true,
              detailCourse == nil,
              let course = KMSCCourseCatalog.allCourses.first else { return }
        detailCourse = course
    }
#endif

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "전체", category: nil)
                ForEach(KMSCCourseCatalog.categories, id: \.self) { category in
                    categoryChip(title: category, category: category)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func categoryChip(title: String, category: String?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct KMSCCourseRow: View {
    let course: KMSCCourseEntry
    let isInCollection: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.body.weight(.medium))
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(course.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(course.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isInCollection {
                Text("추가됨")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

#endif
