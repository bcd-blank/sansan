//
//  HikingRecordRouteMapView.swift
//  sansan
//

#if os(iOS)

import MapKit
import Photos
import SwiftUI
import UIKit

/// 저장된 GPS 경로를 MapKit 지도 레이어로 표시 (확대·이동 시 실제 지도).
struct HikingRecordRouteMapView: View {
    let recordID: UUID
    let mapWidth: CGFloat
    let mapHeight: CGFloat

    @ObservedObject private var store = HikingRecordStore.shared
    @ObservedObject private var snapshotPreferences = HikingSnapshotPreferencesObserver.shared
    @ObservedObject private var mapDisplayPreferences = HikingMapDisplayPreferencesObserver.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var photoGallery: TrailPhotoGalleryPresentation?
    /// 기록 상세 지도 전용 — 저장·공유 이미지 설정(`HikingShareExportPreferences`)과 별개.
    @State private var showsDistanceMarkers = true
    @State private var showsPhotoMarkers = true
    @State private var mapResetTrigger = 0
    @State private var cardGlobalFrame: CGRect = .zero
    @State private var mapContentGlobalFrame: CGRect = .zero
    @State private var isLiveRegistryActive = false
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var kilometerMarkerPlacements: [RouteKilometerMarkerPlacement] = []
    @State private var nearbySummits: [MountainSummit] = []
    @State private var isRouteDisplayReady = false

    private var record: SavedHikingSession? {
        store.records.first { $0.id == recordID }
    }

    private var hasTrailPhotos: Bool { !(record?.session.photos.isEmpty ?? true) }

    private var fittingRegion: MKCoordinateRegion {
        HikingMapRegion.fitting(
            coordinates: routeCoordinates,
            viewSize: CGSize(width: mapWidth, height: mapHeight)
        )
    }

    /// ScrollView·레이아웃 직후 0×0으로 MapKit이 그려지며 CAMetalLayer 경고가 나는 것을 방지.
    private var isMapDrawable: Bool {
        mapWidth >= 1 && mapHeight >= 1
    }

    var body: some View {
        ZStack {
            if isMapDrawable {
                if isRouteDisplayReady, let record, routeCoordinates.count >= 2 {
                    interactiveMap(record: record)
                } else if let record, record.session.points.count >= 2 {
                    routeLoadingPlaceholder
                } else {
                    routeUnavailablePlaceholder
                }
            } else {
                mapLayoutPlaceholder
            }
        }
        .frame(width: mapWidth, height: mapHeight)
        .overlay(alignment: .top) {
            if let record, !record.mapPinnedPhotos.isEmpty {
                MapPinnedThumbnailsTopBar(
                    recordID: recordID,
                    photos: record.mapPinnedPhotos,
                    onSelect: { presentPhotoGallery(startingWith: $0) }
                )
                .padding(.top, 10)
                .padding(.horizontal, 10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if routeCoordinates.count >= 2 {
                mapControlButtons
            }
        }
        .overlay(alignment: .bottomLeading) {
            if snapshotPreferences.style.showsBrandLogo, routeCoordinates.count >= 2 {
                RouteBrandLogoOverlay(
                    bottomOffset: RouteBrandLogoMetrics.interactiveMapAttributionBottomOffset,
                    sizeScale: 0.6
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(HikingRecordCardLayout.groupedCardStroke(for: colorScheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .background {
            MapParentScrollViewTuning()
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        publishLiveMapContext(globalFrame: geometry.frame(in: .global))
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, frame in
                        publishLiveMapContext(globalFrame: frame)
                    }
            }
        }
        .onDisappear {
            isLiveRegistryActive = false
            LiveRouteMapSnapshotRegistry.shared.remove(recordID: recordID)
        }
        .onAppear {
            isLiveRegistryActive = true
        }
        .task(id: routePreparationToken) {
            await prepareRouteDisplayData()
        }
        .onChange(of: mapResetTrigger) { _, _ in
            fitRouteInView(animated: true)
        }
        .fullScreenCover(item: $photoGallery) { gallery in
            TrailPhotoGalleryView(
                recordID: recordID,
                initialPhotoID: gallery.id,
                onDismiss: { photoGallery = nil },
                onShowMapThumbnail: { result in
                    if case .pinned = result {
                        photoGallery = nil
                    }
                }
            )
        }
    }

    private func presentPhotoGallery(startingWith photo: HikingTrailPhoto) {
        guard let record else { return }
        let sorted = record.session.photos.sorted { $0.timestamp < $1.timestamp }
        guard sorted.contains(where: { $0.id == photo.id }) else { return }
        photoGallery = TrailPhotoGalleryPresentation(id: photo.id)
    }

    private var photoMarkerPlacements: [TrailPhotoMapMarkerPlacement] {
        guard let record else { return [] }
        return TrailPhotoMapAnnotationBuilder.markerPlacements(for: record.session.photos)
    }

    private var routePreparationToken: String {
        guard let record else { return recordID.uuidString }
        let cacheVersion = record.session.displayCacheVersion.map(String.init) ?? "none"
        return "\(recordID.uuidString)|\(record.session.points.count)|\(cacheVersion)|\(mapDisplayPreferences.showsSummitMarkers)"
    }

    /// 사진 목록이 바뀔 때만 Map을 재구성 (표시 on/off·핀은 카메라 유지).
    private var mapPhotoListRevision: String {
        guard let record else { return "empty" }
        return record.session.photos.map(\.id.uuidString).joined(separator: ",")
    }

    private func interactiveMap(record: SavedHikingSession) -> some View {
        MapReader { proxy in
            Map(position: $mapPosition, interactionModes: .all) {
                routeMapContent
                distanceMarkerMapContent
                segmentBreakMapContent
                RouteNearbySummitMapContent(
                    summits: nearbySummits,
                    showsSummits: mapDisplayPreferences.showsSummitMarkers
                )
                photoMapContent
            }
            .mapStyle(.standard(elevation: .flat))
            .onMapCameraChange(frequency: .onEnd) { context in
                guard isLiveRegistryActive else { return }
                LiveRouteMapSnapshotRegistry.shared.updateLiveCamera(
                    recordID: recordID,
                    region: context.region,
                    visibleMapRect: liveVisibleMapRect(proxy: proxy) ?? context.rect
                )
            }
            .background {
                RouteMapVisibleRenderRegistrar(recordID: recordID)
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            publishMapContentFrame(geometry.frame(in: .global))
                        }
                        .onChange(of: geometry.frame(in: .global)) { _, frame in
                            publishMapContentFrame(frame)
                        }
                }
            }
            .onAppear {
                // 저장 시점에 화면 지도가 실제로 보여주는 영역을 그대로 가져와 클론에 적용합니다.
                // (onMapCameraChange가 초기 프로그램적 카메라에서 안 뜨는 경우 대비)
                LiveRouteMapSnapshotRegistry.shared.registerVisibleRectProvider(recordID: recordID) {
                    liveVisibleMapRect(proxy: proxy)
                }
            }
            .id(mapPhotoListRevision)
        }
    }

    /// 라이브 SwiftUI `Map`의 네 모서리를 좌표로 변환해 현재 보이는 MapRect를 만듭니다.
    private func liveVisibleMapRect(proxy: MapProxy) -> MKMapRect? {
        let size = CGSize(width: mapWidth, height: mapHeight)
        guard size.width > 1, size.height > 1 else { return nil }
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: size.width, y: 0),
            CGPoint(x: 0, y: size.height),
            CGPoint(x: size.width, y: size.height)
        ]
        var rect = MKMapRect.null
        for corner in corners {
            guard let coordinate = proxy.convert(corner, from: .local) else { return nil }
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return rect.isNull ? nil : rect
    }

    @MapContentBuilder
    private var routeMapContent: some MapContent {
        MapPolyline(coordinates: routeCoordinates)
            .stroke(
                Color(red: 0.12, green: 0.72, blue: 0.45),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

        if let start = routeCoordinates.first {
            Annotation("", coordinate: start) {
                RouteEndpointMarker(fill: Color(red: 0.12, green: 0.72, blue: 0.45))
            }
        }

        if let end = routeCoordinates.last, routeCoordinates.count > 1 {
            Annotation("", coordinate: end) {
                RouteEndpointMarker(fill: Color(red: 0.11, green: 0.11, blue: 0.12))
            }
        }
    }

    @MapContentBuilder
    private var distanceMarkerMapContent: some MapContent {
        if showsDistanceMarkers {
            ForEach(kilometerMarkerPlacements) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .center) {
                    RouteKilometerHorizontalMarker(
                        text: marker.labelText,
                        placesLabelOnLeadingSide: marker.placesLabelOnLeadingSide
                    )
                }
            }
        }
    }

    private var segmentBreakPlacements: [SegmentBreakPlacement] {
        guard let record else { return [] }
        return SegmentBreakMarkerBuilder.placements(for: record.session.segmentBreaks ?? [])
    }

    @MapContentBuilder
    private var segmentBreakMapContent: some MapContent {
        ForEach(segmentBreakPlacements) { placement in
            Annotation("", coordinate: placement.coordinate, anchor: .center) {
                SegmentBreakMarkerView(kind: placement.kind)
            }
        }
    }

    @MapContentBuilder
    private var photoMapContent: some MapContent {
        if showsPhotoMarkers {
            ForEach(photoMarkerPlacements) { placement in
                Annotation(
                    "",
                    coordinate: placement.coordinate,
                    anchor: placement.isCluster ? .center : .bottom
                ) {
                    TrailPhotoMapMarkerPlacementView(placement: placement) { photo in
                        presentPhotoGallery(startingWith: photo)
                    }
                }
            }
        }
    }

    private var mapLayoutPlaceholder: some View {
        Color(.tertiarySystemFill)
    }

    private var routeLoadingPlaceholder: some View {
        Color(.tertiarySystemFill)
            .overlay {
                ProgressView()
            }
    }

    private var routeUnavailablePlaceholder: some View {
        Color(.tertiarySystemFill)
            .overlay {
                ContentUnavailableView(
                    "경로 데이터 부족",
                    systemImage: "map",
                    description: Text("GPS 포인트가 2개 이상일 때 지도에 경로가 표시됩니다.")
                )
            }
    }

    @ViewBuilder
    private var mapControlButtons: some View {
        HStack(spacing: 12) {
            MapFloatingControlButton(
                systemImage: "ruler",
                isActive: showsDistanceMarkers,
                accessibilityLabel: showsDistanceMarkers
                    ? "거리 라벨 가리기"
                    : "거리 라벨 표시"
            ) {
                showsDistanceMarkers.toggle()
            }

            if hasTrailPhotos {
                MapFloatingControlButton(
                    systemImage: "camera.fill",
                    isActive: showsPhotoMarkers,
                    accessibilityLabel: showsPhotoMarkers ? "사진 아이콘 가리기" : "사진 아이콘 표시"
                ) {
                    showsPhotoMarkers.toggle()
                }
            }

            MapFloatingControlButton(
                systemImage: "arrow.up.left.and.arrow.down.right",
                accessibilityLabel: "전체 경로 보기"
            ) {
                mapResetTrigger += 1
            }
        }
        .padding(10)
    }

    private func publishMapContentFrame(_ frame: CGRect) {
        guard shouldPublishFrame(frame, comparedTo: mapContentGlobalFrame) else { return }
        mapContentGlobalFrame = frame
        publishLiveMapContextIfPossible()
    }

    private func publishLiveMapContext(globalFrame: CGRect) {
        guard shouldPublishFrame(globalFrame, comparedTo: cardGlobalFrame) else { return }
        cardGlobalFrame = globalFrame
        publishLiveMapContextIfPossible()
    }

    private func shouldPublishFrame(_ frame: CGRect, comparedTo lastFrame: CGRect) -> Bool {
        guard frame.width > 1, frame.height > 1 else { return false }
        guard lastFrame.width > 1, lastFrame.height > 1 else { return true }
        let delta = max(
            abs(frame.minX - lastFrame.minX),
            abs(frame.minY - lastFrame.minY),
            abs(frame.width - lastFrame.width),
            abs(frame.height - lastFrame.height)
        )
        return delta > 2
    }

    private func publishLiveMapContextIfPossible() {
        guard isLiveRegistryActive else { return }
        guard routeCoordinates.count >= 2 else { return }
        let contentFrame = mapContentGlobalFrame.width > 1 && mapContentGlobalFrame.height > 1
            ? mapContentGlobalFrame
            : cardGlobalFrame
        guard contentFrame.width > 1, contentFrame.height > 1 else { return }
        let cardFrame = cardGlobalFrame.width > 1 && cardGlobalFrame.height > 1
            ? cardGlobalFrame
            : contentFrame
        LiveRouteMapSnapshotRegistry.shared.update(
            recordID: recordID,
            globalFrame: cardFrame,
            mapContentGlobalFrame: contentFrame,
            mapSize: CGSize(width: mapWidth, height: mapHeight),
            coordinates: routeCoordinates
        )
    }

    private func prepareRouteDisplayData() async {
        guard let record, record.session.points.count >= 2 else {
            isRouteDisplayReady = false
            routeCoordinates = []
            kilometerMarkerPlacements = []
            nearbySummits = []
            return
        }

        if loadPersistedRouteDisplayIfAvailable(from: record) {
            fitRouteInView(animated: false)
            return
        }

        isRouteDisplayReady = false
        let includeSummits = mapDisplayPreferences.showsSummitMarkers
        let displayData = await HikingRecordRouteDisplayPreparer.prepare(
            points: record.session.points,
            includeSummits: includeSummits
        )

        routeCoordinates = displayData.coordinates
        kilometerMarkerPlacements = displayData.kilometerMarkers
        nearbySummits = displayData.nearbySummits
        isRouteDisplayReady = true
        fitRouteInView(animated: false)
    }

    /// 저장 시 계산해 둔 경로·마커·정상 데이터를 그대로 사용합니다.
    private func loadPersistedRouteDisplayIfAvailable(from record: SavedHikingSession) -> Bool {
        guard record.session.hasPersistedDisplayCache,
              let storedCoordinates = record.session.displayRouteCoordinates else {
            return false
        }

        routeCoordinates = storedCoordinates.map(\.coordinate)
        kilometerMarkerPlacements = record.session.kilometerMarkers ?? []
        nearbySummits = mapDisplayPreferences.showsSummitMarkers
            ? (record.session.nearbySummits ?? [])
            : []
        isRouteDisplayReady = true
        return true
    }

    private func fitRouteInView(animated: Bool) {
        guard routeCoordinates.count >= 2 else { return }
        if animated {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                mapPosition = .region(fittingRegion)
            }
        } else {
            mapPosition = .region(fittingRegion)
        }
        guard isLiveRegistryActive else { return }
        LiveRouteMapSnapshotRegistry.shared.updateLiveCamera(
            recordID: recordID,
            region: fittingRegion
        )
    }
}

// MARK: - 글래스 UI · 지도 컨트롤

private enum GlassIconButtonLayout {
    case standard
    case compactMapControl

    var diameter: CGFloat {
        switch self {
        case .standard: 44
        case .compactMapControl: 40
        }
    }

    var outerPadding: CGFloat {
        switch self {
        case .standard: 8
        case .compactMapControl: 0
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .standard: 0.2
        case .compactMapControl: 0.12
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .standard: 10
        case .compactMapControl: 2
        }
    }

    var shadowYOffset: CGFloat {
        switch self {
        case .standard: 4
        case .compactMapControl: 1
        }
    }
}

private struct GlassIconButton: View {
    let systemImage: String
    var tint: Color = .primary
    var isLoading: Bool = false
    var layout: GlassIconButtonLayout = .standard
    let accessibilityLabel: String
    let action: () -> Void

    private let iconBox: CGFloat = 22

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle()
                            .fill(tint.opacity(0.12))
                    }
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5)
                    }

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(tint)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint)
                        .frame(width: iconBox, height: iconBox)
                }
            }
            .frame(width: layout.diameter, height: layout.diameter)
            .shadow(
                color: .black.opacity(layout.shadowOpacity),
                radius: layout.shadowRadius,
                y: layout.shadowYOffset
            )
            .contentShape(Circle())
        }
        .buttonStyle(GlassIconPressStyle())
        .padding(layout.outerPadding)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct GlassIconPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct GlassLabeledIconButton: View {
    let label: String
    let systemImage: String
    var tint: Color = .primary
    var isLoading: Bool = false
    let accessibilityLabel: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(spacing: 5) {
            GlassIconButton(
                systemImage: systemImage,
                tint: tint,
                isLoading: isLoading,
                accessibilityLabel: accessibilityLabel,
                action: action
            )
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.4))
        }
    }
}

private struct MapFloatingControlButton: View {
    let systemImage: String
    var isActive: Bool = true
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        GlassIconButton(
            systemImage: systemImage,
            tint: isActive ? .blue : .secondary,
            layout: .compactMapControl,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct RouteEndpointMarker: View {
    let fill: Color

    private let outerDiameter: CGFloat = 17
    private let innerDiameter: CGFloat = 11

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: outerDiameter, height: outerDiameter)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            Circle()
                .fill(fill)
                .frame(width: innerDiameter, height: innerDiameter)
        }
    }
}

// MARK: - 일시정지/재개 마커

/// 일시정지/재개 마킹의 지도 표시 종류.
private enum SegmentBreakKind {
    /// 일시정지 지점.
    case pause
    /// 재개 지점.
    case resume
    /// 같은 자리에서 일시정지·재개가 이뤄진 경우 — 한 마커에 두 색.
    case combined
}

private struct SegmentBreakPlacement: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let kind: SegmentBreakKind
}

private enum SegmentBreakMarkerBuilder {
    /// 일시정지·재개 좌표가 이 거리 이내면 한 마커에 두 색으로 합쳐 표시합니다.
    static let combineThresholdMeters: CLLocationDistance = 25

    static func placements(for breaks: [HikingSegmentBreak]) -> [SegmentBreakPlacement] {
        var result: [SegmentBreakPlacement] = []
        for segmentBreak in breaks {
            let pause = segmentBreak.pauseCoordinate
            guard let resume = segmentBreak.resumeCoordinate else {
                result.append(
                    SegmentBreakPlacement(
                        id: "\(segmentBreak.id.uuidString)-pause",
                        coordinate: pause,
                        kind: .pause
                    )
                )
                continue
            }

            let distance = CLLocation(latitude: pause.latitude, longitude: pause.longitude)
                .distance(from: CLLocation(latitude: resume.latitude, longitude: resume.longitude))
            if distance <= combineThresholdMeters {
                let midpoint = CLLocationCoordinate2D(
                    latitude: (pause.latitude + resume.latitude) / 2,
                    longitude: (pause.longitude + resume.longitude) / 2
                )
                result.append(
                    SegmentBreakPlacement(
                        id: "\(segmentBreak.id.uuidString)-combined",
                        coordinate: midpoint,
                        kind: .combined
                    )
                )
            } else {
                result.append(
                    SegmentBreakPlacement(
                        id: "\(segmentBreak.id.uuidString)-pause",
                        coordinate: pause,
                        kind: .pause
                    )
                )
                result.append(
                    SegmentBreakPlacement(
                        id: "\(segmentBreak.id.uuidString)-resume",
                        coordinate: resume,
                        kind: .resume
                    )
                )
            }
        }
        return result
    }
}

private struct SegmentBreakMarkerView: View {
    let kind: SegmentBreakKind

    private static let pauseColor = Color.orange
    private static let resumeColor = Color(red: 0.12, green: 0.72, blue: 0.45)

    private let outerDiameter: CGFloat = 19
    private let innerDiameter: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: outerDiameter, height: outerDiameter)
                .shadow(color: .black.opacity(0.18), radius: 2, y: 1)

            innerContent
                .frame(width: innerDiameter, height: innerDiameter)
                .clipShape(Circle())

            iconOverlay
        }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var innerContent: some View {
        switch kind {
        case .pause:
            Self.pauseColor
        case .resume:
            Self.resumeColor
        case .combined:
            HStack(spacing: 0) {
                Self.pauseColor
                Self.resumeColor
            }
        }
    }

    @ViewBuilder
    private var iconOverlay: some View {
        switch kind {
        case .pause:
            icon("pause.fill")
        case .resume:
            icon("play.fill")
        case .combined:
            EmptyView()
        }
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 7, weight: .black))
            .foregroundStyle(.white)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .pause: "일시정지 지점"
        case .resume: "재개 지점"
        case .combined: "일시정지·재개 지점"
        }
    }
}

private struct TrailPhotoGalleryPresentation: Identifiable {
    let id: UUID
}

private struct TrailPhotoGalleryView: View {
    let recordID: UUID
    let initialPhotoID: UUID
    let onDismiss: () -> Void
    let onShowMapThumbnail: (HikingRecordStore.MapPhotoPinResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = HikingRecordStore.shared
    @State private var selectedPhotoID: UUID

    init(
        recordID: UUID,
        initialPhotoID: UUID,
        onDismiss: @escaping () -> Void,
        onShowMapThumbnail: @escaping (HikingRecordStore.MapPhotoPinResult) -> Void
    ) {
        self.recordID = recordID
        self.initialPhotoID = initialPhotoID
        self.onDismiss = onDismiss
        self.onShowMapThumbnail = onShowMapThumbnail
        _selectedPhotoID = State(initialValue: initialPhotoID)
    }

    private var photos: [HikingTrailPhoto] {
        store.records
            .first(where: { $0.id == recordID })?
            .session.photos
            .sorted { $0.timestamp < $1.timestamp }
            ?? []
    }

    private var selectedPhoto: HikingTrailPhoto? {
        photos.first { $0.id == selectedPhotoID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TabView(selection: $selectedPhotoID) {
                    ForEach(photos) { photo in
                        TrailPhotoDetailPage(
                            recordID: recordID,
                            photo: photo,
                            reservesPageIndicatorSpace: photos.count > 1,
                            onDeleted: handlePhotoDeleted,
                            onShowMapThumbnail: onShowMapThumbnail
                        )
                        .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
                .background(Color.black)
            }
            .overlay(alignment: .topTrailing) {
                GlassIconButton(
                    systemImage: "xmark",
                    tint: .white,
                    accessibilityLabel: "닫기"
                ) {
                    closeGallery()
                }
                .padding(.trailing, 10)
                .padding(.top, 10)
            }
            .navigationTitle(selectedPhoto?.timestamp.formatted(date: .abbreviated, time: .shortened) ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .onAppear {
                if photos.contains(where: { $0.id == initialPhotoID }) {
                    selectedPhotoID = initialPhotoID
                } else if let first = photos.first {
                    selectedPhotoID = first.id
                } else {
                    closeGallery()
                }
            }
            .onChange(of: photos.map(\.id)) { _, photoIDs in
                guard !photoIDs.isEmpty else {
                    closeGallery()
                    return
                }
                if !photoIDs.contains(selectedPhotoID) {
                    selectedPhotoID = photoIDs[0]
                }
            }
        }
    }

    private func closeGallery() {
        onDismiss()
        dismiss()
    }

    private func handlePhotoDeleted(deletedID: UUID, selectNext: UUID?) {
        let remaining = photos
        guard !remaining.isEmpty else {
            closeGallery()
            return
        }
        guard selectedPhotoID == deletedID else { return }
        if let selectNext, remaining.contains(where: { $0.id == selectNext }) {
            selectedPhotoID = selectNext
        } else {
            selectedPhotoID = remaining[0].id
        }
    }
}

private struct TrailPhotoDetailPage: View {
    let recordID: UUID
    let photo: HikingTrailPhoto
    var reservesPageIndicatorSpace = false
    let onDeleted: (_ deletedID: UUID, _ selectNext: UUID?) -> Void
    let onShowMapThumbnail: (HikingRecordStore.MapPhotoPinResult) -> Void

    @ObservedObject private var store = HikingRecordStore.shared

    private var isPinnedOnMap: Bool {
        store.records
            .first(where: { $0.id == recordID })?
            .mapPinnedPhotoIDs
            .contains(photo.id) ?? false
    }

    @State private var showDeleteConfirmation = false
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var alertMessage: String?

    private var image: UIImage? {
        HikingTrailPhotoStore.loadImage(sessionID: recordID, filename: photo.filename)
    }

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView(
                        "사진을 불러올 수 없음",
                        systemImage: "photo",
                        description: Text("파일이 삭제되었을 수 있습니다.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .overlay(alignment: .bottom) {
            photoActionBar
        }
        .confirmationDialog(
            "이 사진을 기록에서 삭제할까요?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                Task { await deletePhoto() }
            }
            Button("취소", role: .cancel) {}
        }
        .alert("사진", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var photoActionBar: some View {
        HStack(spacing: 28) {
            GlassLabeledIconButton(
                label: "삭제",
                systemImage: "trash",
                tint: .red,
                isLoading: isDeleting,
                accessibilityLabel: "삭제"
            ) {
                showDeleteConfirmation = true
            }
            .disabled(isDeleting || isSaving || image == nil)

            GlassLabeledIconButton(
                label: "썸네일",
                systemImage: "photo.circle.fill",
                tint: isPinnedOnMap ? .blue : .white,
                accessibilityLabel: pinButtonAccessibilityLabel
            ) {
                pinToMap()
            }
            .disabled(isDeleting || isSaving || image == nil)
            .accessibilityAddTraits(isPinnedOnMap ? .isSelected : [])

            GlassLabeledIconButton(
                label: "저장",
                systemImage: "square.and.arrow.down",
                tint: .blue,
                isLoading: isSaving,
                accessibilityLabel: "사진 앱에 저장"
            ) {
                Task { await saveToPhotoLibrary() }
            }
            .disabled(isDeleting || isSaving || image == nil)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5)
        }
        .padding(.bottom, reservesPageIndicatorSpace ? 46 : 28)
    }

    private func saveToPhotoLibrary() async {
        guard let image else {
            alertMessage = "저장할 사진이 없습니다."
            return
        }
        isSaving = true
        defer { isSaving = false }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            alertMessage = "사진 앱 접근 권한이 필요합니다."
            return
        }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(
                    from: image.preparedForPhotoLibraryExport()
                )
            }
            alertMessage = "사진 앱에 저장되었습니다."
        } catch {
            alertMessage = "저장에 실패했습니다."
        }
    }

    private var pinButtonAccessibilityLabel: String {
        isPinnedOnMap ? "썸네일 지정 해제" : "썸네일 지정"
    }

    private func pinToMap() {
        if isPinnedOnMap {
            store.unpinMapPhoto(recordID: recordID, photoID: photo.id)
            return
        }

        let result = store.pinMapPhoto(recordID: recordID, photoID: photo.id)
        switch result {
        case .pinned:
            onShowMapThumbnail(result)
        case .limitReached:
            alertMessage = "썸네일은 최대 \(SavedHikingSession.maxMapPinnedPhotos)개까지 지정할 수 있습니다."
        case .alreadyPinned:
            break
        case .notFound:
            alertMessage = "사진을 찾을 수 없습니다."
        }
    }

    private func deletePhoto() async {
        isDeleting = true
        defer { isDeleting = false }

        let sortedPhotos = store.records
            .first(where: { $0.id == recordID })?
            .session.photos
            .sorted { $0.timestamp < $1.timestamp }
            ?? []
        let deletedIndex = sortedPhotos.firstIndex(where: { $0.id == photo.id })
        let selectNext: UUID? = {
            guard sortedPhotos.count > 1, let deletedIndex else { return nil }
            if deletedIndex + 1 < sortedPhotos.count {
                return sortedPhotos[deletedIndex + 1].id
            }
            if deletedIndex > 0 {
                return sortedPhotos[deletedIndex - 1].id
            }
            return nil
        }()

        let deleted = await store.deleteTrailPhoto(recordID: recordID, photoID: photo.id)
        if deleted {
            onDeleted(photo.id, selectNext)
        } else {
            alertMessage = "삭제에 실패했습니다."
        }
    }
}

#endif
