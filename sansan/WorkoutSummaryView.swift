//
//  WorkoutSummaryView.swift
//  sansan
//
//  기록 종료 직후 저장 전 종합 데이터 검토 화면.
//

#if os(iOS)

import MapKit
import SwiftUI

/// 종료 버튼 후 표시되는 요약 검토 화면 — 데이터 확인 후 저장/삭제.
struct WorkoutSummaryView: View {
    let session: HikingSessionData
    let onSave: () -> Void
    let onDiscard: () -> Void

    @Environment(\.chromeCapsuleHeight) private var chromeCapsuleHeight
    @State private var showDiscardConfirmation = false

    private static let routeColor = Color(red: 0.12, green: 0.72, blue: 0.45)

    private var record: SavedHikingSession {
        SavedHikingSession(session: session)
    }

    private var routeCoordinates: [CLLocationCoordinate2D] {
        session.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    routePreview
                    HikingRecordSummarySection(record: record)
                    dataQualityNote
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("기록 요약")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                actionBar
            }
        }
        .interactiveDismissDisabled(true)
    }

    // MARK: - 경로 미리보기

    @ViewBuilder
    private var routePreview: some View {
        if routeCoordinates.count >= 2 {
            Map(initialPosition: .region(
                HikingMapRegion.fitting(
                    coordinates: routeCoordinates,
                    viewSize: CGSize(width: 340, height: 220)
                )
            )) {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Self.routeColor, lineWidth: 5)

                if let start = routeCoordinates.first {
                    Annotation("시작", coordinate: start) {
                        routeEndpointDot(color: Self.routeColor)
                    }
                }
                if let end = routeCoordinates.last {
                    Annotation("종료", coordinate: end) {
                        routeEndpointDot(color: .red)
                    }
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(false)
        } else {
            ContentUnavailableView(
                "경로 없음",
                systemImage: "map",
                description: Text("기록된 GPS 포인트가 부족합니다. 저장 전에 확인하세요.")
            )
            .frame(height: 180)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func routeEndpointDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay {
                Circle().strokeBorder(.white, lineWidth: 2.5)
            }
            .shadow(radius: 2)
    }

    private var dataQualityNote: some View {
        Label(
            "데이터가 제대로 수집됐는지 확인한 뒤 저장하세요.",
            systemImage: "checkmark.seal"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    // MARK: - 하단 액션

    private var actionBar: some View {
        HStack(spacing: 8) {
            summaryActionButton(
                title: "삭제",
                systemImage: "trash",
                tint: .red,
                isBold: false
            ) {
                showDiscardConfirmation = true
            }

            summaryActionButton(
                title: "저장 완료",
                systemImage: "checkmark",
                tint: Self.routeColor,
                isBold: true,
                action: onSave
            )
        }
        .frame(height: chromeCapsuleHeight)
        .padding(.horizontal, iPhoneBottomChromeLayout.chromeHorizontalPadding)
        .padding(.vertical, 12)
        .confirmationDialog(
            "이 기록을 삭제할까요?",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                onDiscard()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("저장하지 않고 기록을 폐기합니다. 되돌릴 수 없습니다.")
        }
    }

    private func summaryActionButton(
        title: String,
        systemImage: String,
        tint: Color,
        isBold: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(isBold ? .bold : .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: iPhoneBottomChromeLayout.chromeControlHeight)
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .buttonBorderShape(.capsule)
    }
}

#endif
