//
//  iPhoneDashboardView.swift
//  sansan
//

#if os(iOS)

import MapKit
import SwiftUI

struct iPhoneDashboardView: View {
    @ObservedObject private var chrome = WorkoutChromeStateObserver.shared
    @ObservedObject private var routeFollow = HikingRouteFollowObserver.shared
    @ObservedObject private var profilePhoto = UserProfilePhotoObserver.shared

    private static let followedRouteColor = Color.orange

    @State private var showGeneralSettings = false
    @State private var didPrepareMainScreen = false
    /// 하단 탭이 먼저 살아나도록 지도·통계는 한 박자 뒤에 붙입니다.
    @State private var isLiveSessionPanePrepared = false

    var body: some View {
        VStack(spacing: 0) {
            dashboardTopBar
            followedRouteBar

            if isLiveSessionPanePrepared {
                DashboardLiveSessionPane()
            } else {
                dashboardSessionPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
        }
        .overlay {
            if let count = chrome.startCountdownRemaining {
                startCountdownOverlay(count)
            }
        }
        .onChange(of: chrome.startCountdownRemaining) { _, newValue in
            guard newValue != nil else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        .sheet(isPresented: $showGeneralSettings) {
            NavigationStack {
                GeneralSettingsView()
            }
        }
        .onAppear {
            profilePhoto.syncFromStorage()
            if !didPrepareMainScreen {
                didPrepareMainScreen = true
                Task { @MainActor in
                    await Task.yield()
                    isLiveSessionPanePrepared = true
                    try? await Task.sleep(for: .milliseconds(900))
                    await WorkoutManager.shared.prepareAfterMainScreenReady()
                    WorkoutManager.shared.prepareDashboardMapLocation()
                    routeFollow.syncFromStorage()
                }
            }
        }
    }

    private var dashboardSessionPlaceholder: some View {
        ScrollView {
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .frame(minWidth: 1, minHeight: 320)
                    .frame(height: 320)
                    .overlay {
                        ProgressView()
                    }

                Color.clear
                    .frame(height: iPhoneBottomChromeLayout.floatingChromeHeight)
            }
            .padding(.horizontal, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .scrollDisabled(true)
    }

    @ViewBuilder
    private var followedRouteBar: some View {
        if routeFollow.hasFollowedRoute {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Self.followedRouteColor)

                Text("\(routeFollow.followedRouteTitle) 따라가기")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    routeFollow.clearFollowedRoute()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("따라가기 해제")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Self.followedRouteColor.opacity(0.12))
        }
    }

    // MARK: - 상단 바

    private var dashboardTopBar: some View {
        HStack(alignment: .center, spacing: 10) {
            if let image = profilePhoto.displayImage {
                ProfileAvatarView(image: image, diameter: 36)
            } else if profilePhoto.isLoadingDefaultAvatar {
                ProgressView()
                    .frame(width: 36, height: 36)
            } else {
                ProfileAvatarPlaceholderView(diameter: 36)
            }

            Text("sansan")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .layoutPriority(1)

            Spacer(minLength: 8)

            DashboardWatchStatusCapsule()

            Button {
                showGeneralSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("일반설정")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 시작 카운트다운

    private func startCountdownOverlay(_ count: Int) -> some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()

            VStack(spacing: 16) {
                Text("\(count)")
                    .font(.system(size: 130, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: count)

                Text("등산을 시작합니다")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))

                Button("취소") {
                    WorkoutManager.shared.cancelStartCountdown()
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.red)
                .padding(.top, 8)
            }
        }
        .transition(.opacity)
    }

}

private struct DashboardWatchStatusCapsule: View {
    @ObservedObject private var workout = WorkoutManager.shared

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: watchStatusIcon)
                .font(.caption2.weight(.bold))

            Text(watchStatusText)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if workout.sessionData.state != .idle {
                Text(sessionStateLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(watchStatusColor)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(watchStatusColor.opacity(0.14), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(watchStatusColor.opacity(0.22), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private var watchStatusIcon: String {
        guard workout.isWatchConnectivitySupported else { return "applewatch.slash" }
        if workout.isPhoneRecordingFailoverActive { return "iphone" }
        if !workout.isWatchCounterpartInstalled { return "applewatch.slash" }
        if workout.isWatchReachable { return "applewatch.radiowaves.left.and.right" }
        if workout.isWatchLinkEstablished { return "applewatch" }
        return "applewatch.slash"
    }

    private var watchStatusText: String {
        guard workout.isWatchConnectivitySupported else { return "Watch 미지원" }
        if workout.isPhoneRecordingFailoverActive {
            return "iPhone으로 기록 중"
        }
        if !workout.isWatchCounterpartInstalled { return "Apple Watch 미연결" }
        if workout.isWatchReachable { return "Apple Watch 연결됨" }
        if workout.isWatchLinkEstablished {
            switch workout.sessionData.state {
            case .recording, .paused:
                return workout.isWatchActivelyLinked
                    ? "Apple Watch 동기화 중"
                    : "Apple Watch 연결됨 · 실시간 대기"
            case .idle:
                return "Apple Watch 연결됨"
            }
        }
        return "Apple Watch 연결 확인 중"
    }

    private var watchStatusColor: Color {
        guard workout.isWatchConnectivitySupported else { return .secondary }
        if workout.isPhoneRecordingFailoverActive { return .orange }
        if !workout.isWatchCounterpartInstalled { return .secondary }
        if workout.isWatchLinkEstablished { return .green }
        return .orange
    }

    private var sessionStateLabel: String {
        switch workout.sessionData.state {
        case .idle: "대기 중"
        case .recording: "기록 중"
        case .paused: "일시정지"
        }
    }
}

/// GPS·세션 갱신은 여기만 다시 그리고, 상단 설정·하단 탭은 건드리지 않습니다.
private struct DashboardLiveSessionPane: View {
    @ObservedObject private var displayPulse = WorkoutDashboardPulseObserver.shared
    @ObservedObject private var mapDisplayPreferences = HikingMapDisplayPreferencesObserver.shared
    @ObservedObject private var routeFollow = HikingRouteFollowObserver.shared
    @ObservedObject private var heartRatePreferences = HeartRatePreferencesObserver.shared
    @Environment(\.chromeCapsuleHeight) private var chromeCapsuleHeight

    private var workout: WorkoutManager {
        _ = displayPulse.pulse
        return WorkoutManager.shared
    }

    private static let liveRouteColor = Color(red: 0.12, green: 0.72, blue: 0.45)
    private static let followedRouteColor = Color.orange
    private static let liveRouteLineWidth: CGFloat = 5
    private static let followedRouteLineWidth: CGFloat = 3

    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isMapReady = false
    @State private var cachedRouteSegments: [[CLLocationCoordinate2D]] = []
    @State private var cachedCurrentPoint: HikingPoint? = nil
    @State private var dashboardElevationGain = "0"
    @State private var nearbySummits: [MountainSummit] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                hikingMap
                statsGrid
                DashboardElevationProfileCard(elevationGainText: $dashboardElevationGain)
                if heartRatePreferences.isFeatureEnabled {
                    DashboardHeartRateCard()
                }

                Color.clear
                    .frame(
                        height: chromeCapsuleHeight
                            + iPhoneBottomChromeLayout.chromeBottomInset
                            + iPhoneBottomChromeLayout.scrollEndBuffer
                    )
            }
            .padding(.horizontal, 16)
        }
        .ignoresSafeArea(edges: .bottom)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .confirmationDialog(
            "산행이 감지됐어요",
            isPresented: Binding(
                get: { workout.resumeHikingPrompt != nil },
                set: { isPresented in
                    if !isPresented {
                        workout.dismissResumeHikingPrompt()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("기록 재개") {
                workout.confirmResumeHikingPrompt()
            }
            Button("계속 일시정지", role: .cancel) {
                workout.dismissResumeHikingPrompt()
            }
        } message: {
            Text("일시정지 중 이동이 감지됐어요. 기록을 이어갈까요?")
        }
        .onAppear {
            heartRatePreferences.syncFromStorage()
            rebuildRouteCache()
            updateMapCamera()
            if !isMapReady {
                Task { @MainActor in
                    isMapReady = true
                }
            }
        }
        .task(id: summitRefreshKey) {
            await refreshNearbySummits()
        }
        .onChange(of: workout.authorizationStatus) { _, _ in
            updateMapCamera()
        }
        .onChange(of: workout.sessionData.points.count) { _, _ in
            rebuildRouteCache()
            updateMapCamera()
        }
        .onChange(of: workout.sessionData.segmentBreaks?.count ?? 0) { _, _ in
            rebuildRouteCache()
            updateMapCamera()
        }
        .onChange(of: workout.sessionData.state) { _, _ in
            rebuildRouteCache()
        }
        .onChange(of: routeFollow.followedRecordID) { _, _ in
            updateMapCamera()
        }
    }

    private var hikingMap: some View {
        Group {
            if isMapReady {
                Map(position: $mapPosition, interactionModes: .all) {
                    UserAnnotation()

                    if followedRouteCoordinates.count >= 2 {
                        MapPolyline(coordinates: followedRouteCoordinates)
                            .stroke(
                                Self.followedRouteColor,
                                style: StrokeStyle(
                                    lineWidth: Self.followedRouteLineWidth,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }

                    ForEach(Array(routeSegments.enumerated()), id: \.offset) { _, segment in
                        if segment.count >= 2 {
                            MapPolyline(coordinates: segment)
                                .stroke(
                                    Self.liveRouteColor,
                                    style: StrokeStyle(
                                        lineWidth: Self.liveRouteLineWidth,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                        }
                    }

                    RouteNearbySummitMapContent(
                        summits: nearbySummits,
                        showsSummits: mapDisplayPreferences.showsSummitMarkers
                    )

                    ForEach(livePhotoMarkerPlacements) { placement in
                        Annotation(
                            "",
                            coordinate: placement.coordinate,
                            anchor: placement.isCluster ? .center : .bottom
                        ) {
                            TrailPhotoMapMarkerPlacementView(placement: placement)
                        }
                    }

                    if let current = cachedCurrentPoint {
                        Annotation("현재 위치", coordinate: current.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(.green.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                Circle()
                                    .fill(.green)
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                }
                .id("\(livePhotoMapRevision)-\(routeFollow.followedRecordID?.uuidString ?? "none")")
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .frame(minWidth: 1, minHeight: 320)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var routeSegments: [[CLLocationCoordinate2D]] { cachedRouteSegments }

    private var routeSummitReferenceCoordinates: [CLLocationCoordinate2D] {
        routeSegments.last ?? []
    }

    private var summitRefreshKey: String {
        let coords = routeSummitReferenceCoordinates
        let first = coords.first
        let last = coords.last
        let firstKey = first.map { "\(Int($0.latitude * 10_000))-\(Int($0.longitude * 10_000))" } ?? "-"
        let lastKey = last.map { "\(Int($0.latitude * 10_000))-\(Int($0.longitude * 10_000))" } ?? "-"
        return "\(mapDisplayPreferences.showsSummitMarkers)|\(coords.count)|\(firstKey)|\(lastKey)"
    }

    private func refreshNearbySummits() async {
        guard mapDisplayPreferences.showsSummitMarkers else {
            nearbySummits = []
            return
        }
        let coordinates = routeSummitReferenceCoordinates
        guard coordinates.count >= 2 else {
            nearbySummits = []
            return
        }
        await MountainSummitCatalog.waitUntilReady()
        let result = await Task.detached(priority: .userInitiated) {
            MountainSummitRouteFilter.summits(near: coordinates)
        }.value
        nearbySummits = result
    }

    private var followedRouteCoordinates: [CLLocationCoordinate2D] {
        routeFollow.followedRouteCoordinates
    }

    private var livePhotoMarkerPlacements: [TrailPhotoMapMarkerPlacement] {
        TrailPhotoMapAnnotationBuilder.markerPlacements(for: workout.sessionData.photos)
    }

    private var livePhotoMapRevision: String {
        workout.sessionData.photos.map(\.id.uuidString).joined(separator: ",")
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatCard(
                title: "소요 시간",
                value: formattedElapsedTime,
                unit: "",
                icon: "clock.fill",
                tint: .blue
            )
            StatCard(
                title: "이동 거리",
                value: formattedDistance,
                unit: "km",
                icon: "figure.hiking",
                tint: .green
            )
            StatCard(
                title: "고도 변화",
                value: dashboardElevationGain,
                unit: "m↑",
                icon: "mountain.2.fill",
                tint: .orange
            )
        }
    }

    private var formattedElapsedTime: String {
        let total = Int(workout.sessionData.elapsedTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var formattedDistance: String {
        String(format: "%.2f", workout.sessionData.totalDistance / 1_000)
    }

    private func rebuildRouteCache() {
        let points = workout.sessionData.points
        cachedRouteSegments = HikingSessionMetrics.liveRouteSegments(
            from: points,
            segmentBreaks: workout.sessionData.segmentBreaks
        )
        cachedCurrentPoint = HikingSessionMetrics.pointsExcludingPausedIntervals(
            points,
            segmentBreaks: workout.sessionData.segmentBreaks
        ).last
    }

    private func updateMapCamera() {
        var fitCoordinates = followedRouteCoordinates
        for segment in cachedRouteSegments {
            fitCoordinates.append(contentsOf: segment)
        }

        if fitCoordinates.count >= 2 {
            mapPosition = .region(MKCoordinateRegion(coordinates: fitCoordinates))
            return
        }

        if let last = cachedCurrentPoint {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: last.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
            return
        }

        if let reference = followedRouteCoordinates.first {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: reference,
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            )
            return
        }

        if let mapLocation = workout.lastKnownMapLocation {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: mapLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )
            )
            return
        }

        mapPosition = .userLocation(fallback: .automatic)
    }
}

// MARK: - Components

private struct TrailPhotoLiveMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 28, height: 28)
            Circle()
                .fill(.blue)
                .frame(width: 22, height: 22)
            Image(systemName: "camera.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Helpers

private extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            )
            return
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.004),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.004)
        )
        self.init(center: center, span: span)
    }
}

#Preview {
    iPhoneDashboardView()
}

#endif





