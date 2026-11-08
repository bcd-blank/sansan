//
//  TrailPhotoMapMarkers.swift
//  sansan
//

#if os(iOS)

import MapKit
import SwiftUI

struct TrailPhotoMapAnnotationItem: Identifiable {
    let id: UUID
    let photo: HikingTrailPhoto
    let displayCoordinate: CLLocationCoordinate2D
}

enum TrailPhotoMapAnnotationBuilder {
    static func mapMarkerItems(photos: [HikingTrailPhoto]) -> [TrailPhotoMapAnnotationItem] {
        let displayCoords = HikingTrailPhotoCoordinateLayout.displayCoordinates(for: photos)
        return photos.map { photo in
            TrailPhotoMapAnnotationItem(
                id: photo.id,
                photo: photo,
                displayCoordinate: displayCoords[photo.id] ?? photo.coordinate
            )
        }
    }

    static func markerPlacements(for photos: [HikingTrailPhoto]) -> [TrailPhotoMapMarkerPlacement] {
        TrailPhotoMapMarkerPlacementBuilder.placements(for: photos)
    }
}

// MARK: - 지도 상단 고정 썸네일

struct MapPinnedThumbnailsTopBar: View {
    let recordID: UUID
    let photos: [HikingTrailPhoto]
    let onSelect: (HikingTrailPhoto) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            HStack(spacing: 7) {
                ForEach(photos) { photo in
                    MapPinnedThumbnailChip(
                        recordID: recordID,
                        photo: photo,
                        onTap: { onSelect(photo) }
                    )
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct MapPinnedThumbnailChip: View {
    let recordID: UUID
    let photo: HikingTrailPhoto
    let onTap: () -> Void

    private let size: CGFloat = 64
    private let outerRingWidth: CGFloat = 5

    private var image: UIImage? {
        HikingTrailPhotoStore.loadImage(sessionID: recordID, filename: photo.filename)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.38))
                    .frame(width: size + outerRingWidth * 2, height: size + outerRingWidth * 2)
                Circle()
                    .strokeBorder(Color.black.opacity(0.12), lineWidth: 1)
                    .frame(width: size + outerRingWidth * 2, height: size + outerRingWidth * 2)

                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Color(.tertiarySystemFill)
                            .overlay {
                                Image(systemName: "photo")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 2)
                }
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("고정된 사진 보기")
    }
}

// MARK: - GPS 핀 마커

struct TrailPhotoMapMarkerView: View {
    var body: some View {
        TrailPhotoPinMarker()
    }
}

struct TrailPhotoMapMarkerPlacementView: View {
    let placement: TrailPhotoMapMarkerPlacement
    var onSelectPhoto: ((HikingTrailPhoto) -> Void)?

    var body: some View {
        if placement.isCluster {
            TrailPhotoMapMarkerClusterView(photos: placement.photos, onSelectPhoto: onSelectPhoto)
        } else if let photo = placement.photos.first {
            Button {
                onSelectPhoto?(photo)
            } label: {
                TrailPhotoPinMarker()
            }
            .buttonStyle(.plain)
            .disabled(onSelectPhoto == nil)
        }
    }
}

struct TrailPhotoPinMarker: View {
    private let outer = TrailPhotoMarkerMetrics.outerDiameter
    private let inner = TrailPhotoMarkerMetrics.innerDiameter
    private let tipHeight = TrailPhotoMarkerMetrics.tipHeight
    private let tipWidth = TrailPhotoMarkerMetrics.tipWidth

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: outer, height: outer)
                    .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

                Circle()
                    .fill(.blue)
                    .frame(width: inner, height: inner)

                Image(systemName: "camera.fill")
                    .font(.system(size: TrailPhotoMarkerMetrics.iconPointSize, weight: .bold))
                    .foregroundStyle(.white)
            }

            Triangle()
                .fill(.blue)
                .frame(width: tipWidth, height: tipHeight)
        }
        .frame(width: outer, height: TrailPhotoMarkerMetrics.totalHeight)
    }
}

struct TrailPhotoMapMarkerClusterView: View {
    let photos: [HikingTrailPhoto]
    var onSelectPhoto: ((HikingTrailPhoto) -> Void)?

    private let radius = TrailPhotoMarkerMetrics.clusterRadius
    private let pinHeight = TrailPhotoMarkerMetrics.totalHeight

    private var canvasSize: CGFloat {
        radius * 2 + max(TrailPhotoMarkerMetrics.totalWidth, pinHeight)
    }

    var body: some View {
        ZStack {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                let angle = Double(index) / Double(photos.count) * 360
                let radians = angle * .pi / 180
                let hub = canvasSize / 2
                let rotation = TrailPhotoMarkerLayout.rotationDegrees(pointingInwardAt: angle)

                Button {
                    onSelectPhoto?(photo)
                } label: {
                    TrailPhotoPinMarker()
                }
                .buttonStyle(.plain)
                .disabled(onSelectPhoto == nil)
                .rotationEffect(.degrees(rotation), anchor: .bottom)
                .position(
                    x: hub + CGFloat(sin(radians)) * radius,
                    y: hub - CGFloat(cos(radians)) * radius - pinHeight / 2
                )
            }
        }
        .frame(width: canvasSize, height: canvasSize)
    }
}

enum TrailPhotoMarkerLayout {
    /// 원 둘레에 놓인 핀의 뾰족한 끝이 중심(GPS)을 가리키도록 하는 회전 각도.
    static func rotationDegrees(pointingInwardAt angleFromTop: Double) -> CGFloat {
        let radians = angleFromTop * .pi / 180
        return CGFloat(atan2(-sin(radians), cos(radians)) * 180 / .pi)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

#endif
