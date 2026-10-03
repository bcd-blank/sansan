//
//  KMSCCourseDetailView.swift
//  sansan
//

#if os(iOS)

import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct KMSCCourseDetailView: View {
    let entry: KMSCCourseEntry
    var onFollowRoute: (() -> Void)?

    @ObservedObject private var store = HikingRecordStore.shared
    @ObservedObject private var routeFollow = HikingRouteFollowObserver.shared
    @Environment(\.dismiss) private var dismiss

    @State private var coordinates: [CLLocationCoordinate2D] = []
    @State private var isLoadingPreview = true
    @State private var previewError: String?
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var isInCollection: Bool {
        store.recordID(forBundledRouteID: entry.id) != nil
    }

    private var isFollowing: Bool {
        guard let recordID = store.recordID(forBundledRouteID: entry.id) else { return false }
        return routeFollow.followedRecordID == recordID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                routePreview
                metaBlock
                actionButtons
                Text("한국등산·트레킹지원센터 공공데이터 GPX (출처 표기)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoadingPreview = true
            previewError = nil
            defer { isLoadingPreview = false }
            do {
                coordinates = try await KMSCCourseCatalog.loadCoordinates(for: entry.id)
            } catch let error as KMSCCourseImportError {
                previewError = error.errorDescription
                coordinates = []
            } catch {
                previewError = KMSCCourseImportError.unreadable.errorDescription
                coordinates = []
            }
        }
        .alert("코스 추가 실패", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var routePreview: some View {
        if isLoadingPreview {
            ProgressView("코스 불러오는 중")
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        } else if coordinates.count >= 2 {
            Map(initialPosition: .region(
                HikingMapRegion.fitting(
                    coordinates: coordinates,
                    viewSize: CGSize(width: 340, height: 220)
                )
            )) {
                MapPolyline(coordinates: coordinates)
                    .stroke(Color(red: 0.12, green: 0.72, blue: 0.45), lineWidth: 4)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
        } else {
            ContentUnavailableView(
                "경로 미리보기 없음",
                systemImage: "map",
                description: Text(previewError ?? "코스 파일을 받지 못했습니다.")
            )
            .frame(height: 180)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.category)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(entry.groupName)
                .font(.title3.weight(.bold))
            Text(entry.title)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                playActionHaptic()
                Task { await addToCollection() }
            } label: {
                Label(
                    isInCollection ? "내 모음에 추가됨" : "내 모음에 추가",
                    systemImage: isInCollection ? "checkmark.circle.fill" : "plus.circle.fill"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isImporting || isInCollection)

            Button {
                playActionHaptic()
                Task { await followCourse() }
            } label: {
                Label(
                    isFollowing ? "따라가는 중" : "경로 따라가기",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(isImporting)
        }
    }

    private func playActionHaptic() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func addToCollection() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        let result = await store.importKMSCCourse(entry)
        if case .failure(let error) = result {
            errorMessage = error.errorDescription
        }
    }

    private func followCourse() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        let result = await store.importKMSCCourse(entry)
        switch result {
        case .success(let recordID):
            routeFollow.setFollowedRoute(recordID: recordID)
            onFollowRoute?()
            dismiss()
        case .failure(let error):
            errorMessage = error.errorDescription
        }
    }
}

#endif
