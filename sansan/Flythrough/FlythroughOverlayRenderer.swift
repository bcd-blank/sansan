//
//  FlythroughOverlayRenderer.swift
//  sansan
//
//  지도 프레임 위에 HUD(통계·고도 프로필·현재 위치·사진 팝업)와 인트로/아웃트로를 합성합니다.
//  계약: FlythroughPipelineContract.swift (`mapRouteAndHudAreSeparateLayers`)
//

#if os(iOS)

import CoreLocation
import UIKit

/// 영상 전체에서 변하지 않는 오버레이 사전 계산값.
struct FlythroughHUDModel {
    let title: String
    let dateText: String
    let weather: HikingRouteWeatherSnapshot?
    let totalDistanceText: String
    let totalDurationText: String
    let elevationGainText: String
    /// 고도 프로필 스파크라인 (x: 0~1 거리, y: 0~1 정규화 고도).
    let profile: [CGPoint]
    /// filename → 둥근 썸네일.
    let thumbnails: [String: UIImage]

    static func make(route: FlythroughRoute, thumbnails: [String: UIImage]) -> FlythroughHUDModel {
        let sampleCount = 120
        let span = route.totalProgressDistance
        let minAlt = route.minAltitude
        let altRange = max(route.maxAltitude - route.minAltitude, 1)
        var profile: [CGPoint] = []
        profile.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let p = Double(i) / Double(sampleCount - 1)
            let sample = route.sample(at: p)
            let x = span > 0 ? sample.distance / span : p
            let y = (sample.altitude - minAlt) / altRange
            profile.append(CGPoint(x: x, y: y))
        }

        return FlythroughHUDModel(
            title: route.title,
            dateText: route.dateText,
            weather: route.weather,
            totalDistanceText: String(format: "%.2f km", route.totalDistanceMeters / 1000),
            totalDurationText: FlythroughFormat.duration(route.totalDuration),
            elevationGainText: "\(Int(route.elevationGainMeters.rounded())) m",
            profile: profile,
            thumbnails: thumbnails
        )
    }
}

@MainActor
struct FlythroughOverlayRenderer {
    let canvasSize: CGSize
    let renderScale: CGFloat
    let configuration: FlythroughVideoConfiguration
    let model: FlythroughHUDModel
    let route: FlythroughRoute

    private var isLandscape: Bool { configuration.orientation == .landscape }

    private var layout: FlythroughHUDLayout.Metrics {
        FlythroughHUDLayout.metrics(canvasSize: canvasSize, orientation: configuration.orientation)
    }

    private var topInset: CGFloat { layout.titleTopInset }

    private let imageRenderer: UIGraphicsImageRenderer

    init(
        canvasSize: CGSize,
        renderScale: CGFloat,
        configuration: FlythroughVideoConfiguration,
        model: FlythroughHUDModel,
        route: FlythroughRoute
    ) {
        self.canvasSize = canvasSize
        self.renderScale = renderScale
        self.configuration = configuration
        self.model = model
        self.route = route
        let format = UIGraphicsImageRendererFormat()
        format.scale = renderScale
        format.opaque = true
        imageRenderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
    }

    /// 앱 전반과 동일한 SF Rounded 디자인 폰트. 숫자는 monospacedDigit로 폭을 고정합니다.
    private func font(
        size: CGFloat,
        weight: UIFont.Weight,
        monospacedDigit: Bool = false
    ) -> UIFont {
        let base = monospacedDigit
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }

    /// 지도 프레임 위에 HUD를 합성한 최종 프레임을 만듭니다.
    func compose(
        base: UIImage,
        directive: FlythroughFrameDirective,
        currentPoint: CGPoint?
    ) -> UIImage {
        imageRenderer.image { context in
            let cg = context.cgContext
            base.draw(in: CGRect(origin: .zero, size: canvasSize))

            switch directive.phase {
            case .intro:
                let titleFade = introFade(directive.phaseFraction)
                drawScrim(cg, alpha: 0.14 + 0.32 * titleFade)
                drawIntro(cg, fade: titleFade)
            case .flight:
                drawBottomHUD(cg, directive: directive)
                drawTopTitle(cg, opacity: 1)
            case .outro:
                drawBottomHUD(cg, directive: directive)
                drawTopTitle(cg, opacity: outroTitleOpacity(directive.phaseFraction))
            }
        }
    }

    // MARK: - Intro / Outro

    private func introFade(_ t: Double) -> CGFloat {
        if t < FlythroughIntroTiming.titleFadeInEnd {
            return CGFloat(t / FlythroughIntroTiming.titleFadeInEnd)
        }
        if t < FlythroughIntroTiming.zoomStart {
            return 1
        }
        if t >= FlythroughIntroTiming.titleFadeOutEnd {
            return 0
        }
        let fadeSpan = FlythroughIntroTiming.titleFadeOutEnd - FlythroughIntroTiming.zoomStart
        let raw = (t - FlythroughIntroTiming.zoomStart) / fadeSpan
        return CGFloat(1 - raw)
    }

    private func outroTitleOpacity(_ t: Double) -> CGFloat {
        // Invariant: FlythroughPipelineInvariant.outroKeepsFlightTitleVisible
        1
    }

    private func drawIntro(_ cg: CGContext, fade: CGFloat) {
        let blockCenterY = canvasSize.height * (isLandscape ? 0.44 : 0.40)
        let maxWidth = canvasSize.width - 72

        drawCenteredText(
            model.dateText,
            font: font(size: isLandscape ? 12 : 13, weight: .medium),
            color: UIColor.white.withAlphaComponent(0.62 * fade),
            center: CGPoint(x: canvasSize.width / 2, y: blockCenterY - (isLandscape ? 34 : 38)),
            maxWidth: maxWidth
        )

        drawCenteredText(
            model.title,
            font: font(size: isLandscape ? 30 : 36, weight: .semibold),
            color: UIColor.white.withAlphaComponent(fade),
            center: CGPoint(x: canvasSize.width / 2, y: blockCenterY),
            maxWidth: maxWidth,
            shadow: true
        )

        let accentLineY = blockCenterY + (isLandscape ? 28 : 32)

        // 얇은 악센트 라인 — 과한 pill/부제목 대신 미니멀 포인트.
        let lineWidth: CGFloat = 28
        let lineRect = CGRect(
            x: canvasSize.width / 2 - lineWidth / 2,
            y: accentLineY,
            width: lineWidth,
            height: 2
        )
        FlythroughPalette.routeColor.withAlphaComponent(0.85 * fade).setFill()
        cg.fill(lineRect)

        drawWeatherCaption(
            cg,
            anchor: CGPoint(
                x: canvasSize.width / 2,
                y: accentLineY + 2 + (isLandscape ? 10 : 12)
            ),
            opacity: fade,
            alignment: .center,
            maxWidth: maxWidth,
            shadow: true
        )
    }

    // MARK: - Flight HUD

    private func drawTopTitle(_ cg: CGContext, opacity: CGFloat) {
        let inset: CGFloat = isLandscape ? 24 : 22
        let originX = inset
        var originY = topInset + (isLandscape ? 6 : 10)

        let logoSide: CGFloat = isLandscape ? 26 : 30
        if let logo = BrandLogoImage.rasterizedWhiteLogo(side: logoSide) {
            cg.saveGState()
            cg.setShadow(
                offset: CGSize(width: 0, height: 1),
                blur: 3,
                color: UIColor.black.withAlphaComponent(0.4 * opacity).cgColor
            )
            cg.setAlpha(opacity)
            logo.draw(in: CGRect(x: originX, y: originY, width: logoSide, height: logoSide))
            cg.restoreGState()
            originY += logoSide + (isLandscape ? 6 : 8)
        }

        drawLeftText(
            model.title,
            font: font(size: isLandscape ? 16 : 17, weight: .semibold),
            color: UIColor.white.withAlphaComponent(opacity),
            origin: CGPoint(x: originX, y: originY),
            maxWidth: isLandscape
                ? canvasSize.width - layout.statsPanelWidth - inset * 2 - 16
                : canvasSize.width - inset * 2,
            shadow: true
        )

        originY += isLandscape ? 22 : 24
        drawLeftText(
            model.dateText,
            font: font(size: isLandscape ? 11 : 12, weight: .medium),
            color: UIColor.white.withAlphaComponent(0.58 * opacity),
            origin: CGPoint(x: originX, y: originY),
            maxWidth: canvasSize.width - inset * 2,
            shadow: true
        )

        originY += isLandscape ? 20 : 22
        if let weatherBottom = drawWeatherCaption(
            cg,
            anchor: CGPoint(x: originX, y: originY),
            opacity: opacity,
            alignment: .left,
            maxWidth: isLandscape
                ? canvasSize.width - layout.statsPanelWidth - inset * 2 - 16
                : canvasSize.width - inset * 2,
            shadow: true
        ) {
            originY = weatherBottom
        }
    }

    private enum WeatherCaptionAlignment {
        case left
        case center
    }

    /// 날씨·온도 — 아이콘 + 온도, 아래에 상태 라벨. 반환 Y는 다음 요소 배치용 하단.
    @discardableResult
    private func drawWeatherCaption(
        _ cg: CGContext,
        anchor: CGPoint,
        opacity: CGFloat,
        alignment: WeatherCaptionAlignment,
        maxWidth: CGFloat,
        shadow: Bool
    ) -> CGFloat? {
        guard let weather = model.weather, opacity > 0.01 else { return nil }

        let iconSize: CGFloat = isLandscape ? 11 : 12
        let tempSize: CGFloat = isLandscape ? 12 : 13
        let labelSize: CGFloat = isLandscape ? 11 : 12
        let rowSpacing: CGFloat = isLandscape ? 3 : 4
        let iconGap: CGFloat = 5

        let symbolConfig = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .semibold)
        let symbolImage = UIImage(
            systemName: weather.symbolName,
            withConfiguration: symbolConfig
        )?.withTintColor(
            UIColor.orange.withAlphaComponent(0.95 * opacity),
            renderingMode: .alwaysOriginal
        )

        let tempAttr = NSAttributedString(
            string: weather.formattedTemperature,
            attributes: [
                .font: font(size: tempSize, weight: .semibold, monospacedDigit: true),
                .foregroundColor: UIColor.white.withAlphaComponent(opacity)
            ]
        )
        let labelAttr = NSAttributedString(
            string: weather.conditionLabel,
            attributes: [
                .font: font(size: labelSize, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.62 * opacity)
            ]
        )

        let tempWidth = ceil(tempAttr.size().width)
        let labelWidth = ceil(labelAttr.size().width)
        let iconWidth = symbolImage.map { ceil($0.size.width) } ?? 0
        let rowWidth = iconWidth + (iconWidth > 0 ? iconGap : 0) + tempWidth
        let blockWidth = max(rowWidth, labelWidth)

        let originX: CGFloat
        switch alignment {
        case .left:
            originX = anchor.x
        case .center:
            originX = anchor.x - blockWidth / 2
        }

        var drawY = anchor.y
        if let symbolImage {
            if shadow {
                cg.saveGState()
                cg.setShadow(
                    offset: CGSize(width: 0, height: 1),
                    blur: 3,
                    color: UIColor.black.withAlphaComponent(0.4 * opacity).cgColor
                )
            }
            let iconRect = CGRect(
                x: originX,
                y: drawY + (tempAttr.size().height - symbolImage.size.height) / 2,
                width: symbolImage.size.width,
                height: symbolImage.size.height
            )
            symbolImage.draw(in: iconRect)
            if shadow { cg.restoreGState() }
        }

        let textX = originX + iconWidth + (iconWidth > 0 ? iconGap : 0)
        if shadow {
            let shadowStyle = textShadow(opacity: opacity)
            let tempWithShadow = NSMutableAttributedString(attributedString: tempAttr)
            tempWithShadow.addAttribute(.shadow, value: shadowStyle, range: NSRange(location: 0, length: tempWithShadow.length))
            tempWithShadow.draw(at: CGPoint(x: textX, y: drawY))
        } else {
            tempAttr.draw(at: CGPoint(x: textX, y: drawY))
        }

        drawY += tempAttr.size().height + rowSpacing
        let labelX: CGFloat
        switch alignment {
        case .left:
            labelX = originX
        case .center:
            labelX = anchor.x - labelWidth / 2
        }
        if shadow {
            let labelWithShadow = NSMutableAttributedString(attributedString: labelAttr)
            labelWithShadow.addAttribute(.shadow, value: textShadow(opacity: opacity), range: NSRange(location: 0, length: labelWithShadow.length))
            labelWithShadow.draw(at: CGPoint(x: labelX, y: drawY))
        } else {
            labelAttr.draw(at: CGPoint(x: labelX, y: drawY))
        }

        return drawY + labelAttr.size().height
    }

    private func drawBottomHUD(_ cg: CGContext, directive: FlythroughFrameDirective) {
        if isLandscape {
            drawLandscapeHUD(cg, directive: directive)
        } else {
            drawPortraitBottomHUD(cg, directive: directive)
        }
    }

    private func drawPortraitBottomHUD(_ cg: CGContext, directive: FlythroughFrameDirective) {
        let sample = route.sample(at: directive.progress)
        let health = route.healthMetricTexts(at: directive.progress)
        let inset = layout.horizontalInset
        let valueSize: CGFloat = 20
        let profileHeight = layout.profileHeight
        let rowSpacing: CGFloat = 52

        let bottomInset = layout.bottomMargin
        let contentBottom = canvasSize.height - bottomInset
        let columnWidth = (canvasSize.width - inset * 2) / 3

        let secondaryLabelY = contentBottom - 34
        let primaryLabelY = secondaryLabelY - rowSpacing

        let primaryStats: [(String, String)] = [
            ("거리", String(format: "%.2f km", sample.distance / 1000)),
            ("상승", "\(Int(route.elevationGain(upTo: directive.progress).rounded())) m"),
            ("시간", FlythroughFormat.duration(sample.elapsed))
        ]
        let secondaryStats: [(String, String)] = [
            ("걸음수", health.steps),
            ("심박수", health.heartRate),
            ("칼로리", health.calories)
        ]

        let profileGap: CGFloat = 28
        let profileBottom = primaryLabelY - profileGap
        let profileRect = CGRect(
            x: inset,
            y: profileBottom - profileHeight,
            width: canvasSize.width - inset * 2,
            height: profileHeight
        )

        drawElevationProfile(
            cg,
            rect: profileRect,
            progress: directive.progress,
            altitude: sample.altitude
        )

        drawStatsRow(
            cg,
            stats: primaryStats,
            labelY: primaryLabelY,
            inset: inset,
            columnWidth: columnWidth,
            valueSize: valueSize,
            labelSize: 12
        )
        drawStatsRow(
            cg,
            stats: secondaryStats,
            labelY: secondaryLabelY,
            inset: inset,
            columnWidth: columnWidth,
            valueSize: valueSize,
            labelSize: 12
        )
    }

    private func drawLandscapeHUD(_ cg: CGContext, directive: FlythroughFrameDirective) {
        let sample = route.sample(at: directive.progress)
        let health = route.healthMetricTexts(at: directive.progress)
        let inset = layout.horizontalInset
        let statsPanelWidth = layout.statsPanelWidth
        let statsPanelLeft = canvasSize.width - inset - statsPanelWidth
        let profileGap: CGFloat = 8

        let profileRect = CGRect(
            x: inset,
            y: canvasSize.height - layout.bottomMargin - layout.profileHeight,
            width: max(statsPanelLeft - inset - profileGap, 1),
            height: layout.profileHeight
        )

        drawElevationProfile(
            cg,
            rect: profileRect,
            progress: directive.progress,
            altitude: sample.altitude
        )

        let statsPanelRect = CGRect(
            x: statsPanelLeft - 8,
            y: 0,
            width: canvasSize.width - statsPanelLeft + 8,
            height: canvasSize.height
        )
        drawSideGradient(cg, rect: statsPanelRect)

        let leftColumn: [(String, String)] = [
            ("거리", String(format: "%.2f km", sample.distance / 1000)),
            ("상승", "\(Int(route.elevationGain(upTo: directive.progress).rounded())) m"),
            ("시간", FlythroughFormat.duration(sample.elapsed)),
            ("걸음수", health.steps),
            ("심박수", health.heartRate),
            ("칼로리", health.calories)
        ]

        drawLandscapeStatsColumn(
            cg,
            stats: leftColumn,
            panelLeft: statsPanelLeft,
            panelWidth: statsPanelWidth,
            contentTop: layout.statsPanelTopInset,
            contentBottom: layout.statsPanelBottomInset
        )
    }

    /// 가로 영상 우측 — 1열 × 6행, 상·하 여백 안에 균등 배치.
    private func drawLandscapeStatsColumn(
        _ cg: CGContext,
        stats: [(String, String)],
        panelLeft: CGFloat,
        panelWidth: CGFloat,
        contentTop: CGFloat,
        contentBottom: CGFloat
    ) {
        let rowCount = max(stats.count, 1)
        let contentHeight = max(canvasSize.height - contentTop - contentBottom, 1)
        let rowHeight = contentHeight / CGFloat(rowCount)
        let valueSize = max(contentHeight * 0.058, 9)
        let labelSize = max(valueSize * 0.58, 7)
        let statBlockHeight = labelSize + 1 + valueSize

        for (index, stat) in stats.enumerated() {
            let cellTop = contentTop + rowHeight * CGFloat(index)
            let cellCenterY = cellTop + rowHeight / 2
            let statOriginY = cellCenterY - statBlockHeight / 2
            drawCompactStat(
                cg,
                label: stat.0,
                value: stat.1,
                origin: CGPoint(x: panelLeft, y: statOriginY),
                labelSize: labelSize,
                valueSize: valueSize,
                containerWidth: panelWidth,
                alignRight: true
            )
        }
    }

    private func drawCompactStat(
        _ cg: CGContext,
        label: String,
        value: String,
        origin: CGPoint,
        labelSize: CGFloat,
        valueSize: CGFloat,
        containerWidth: CGFloat? = nil,
        alignRight: Bool = false
    ) {
        let labelFont = font(size: labelSize, weight: .medium)
        let valueFont = font(size: valueSize, weight: .bold, monospacedDigit: true)
        let labelAttr = NSAttributedString(string: label, attributes: [
            .font: labelFont,
            .foregroundColor: UIColor.white.withAlphaComponent(0.68)
        ])
        let valueAttr = NSAttributedString(string: value, attributes: [
            .font: valueFont,
            .foregroundColor: UIColor.white
        ])

        if alignRight, let containerWidth {
            let labelWidth = ceil((label as NSString).size(withAttributes: [.font: labelFont]).width)
            let valueWidth = ceil((value as NSString).size(withAttributes: [.font: valueFont]).width)
            let labelX = origin.x + containerWidth - labelWidth
            let valueX = origin.x + containerWidth - valueWidth
            labelAttr.draw(at: CGPoint(x: labelX, y: origin.y))
            valueAttr.draw(at: CGPoint(x: valueX, y: origin.y + labelSize + 1))
        } else {
            labelAttr.draw(at: origin)
            valueAttr.draw(at: CGPoint(x: origin.x, y: origin.y + labelSize + 1))
        }
    }

    private func drawStatsRow(
        _ cg: CGContext,
        stats: [(String, String)],
        labelY: CGFloat,
        inset: CGFloat,
        columnWidth: CGFloat,
        valueSize: CGFloat,
        labelSize: CGFloat = 12
    ) {
        for (index, stat) in stats.enumerated() {
            let columnX = inset + columnWidth * CGFloat(index)
            let labelAttr = NSAttributedString(string: stat.0, attributes: [
                .font: font(size: labelSize, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.7)
            ])
            let valueAttr = NSAttributedString(string: stat.1, attributes: [
                .font: font(size: valueSize, weight: .bold, monospacedDigit: true),
                .foregroundColor: UIColor.white
            ])
            labelAttr.draw(at: CGPoint(x: columnX, y: labelY))
            valueAttr.draw(at: CGPoint(x: columnX, y: labelY + 16))
        }
    }

    private func drawElevationProfile(
        _ cg: CGContext,
        rect: CGRect,
        progress: Double,
        altitude: Double
    ) {
        guard model.profile.count >= 2 else { return }
        func point(_ p: CGPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + p.x * rect.width,
                y: rect.maxY - p.y * rect.height
            )
        }

        drawProfileAltitudeLabel(cg, rect: rect, altitude: altitude)

        if progress <= 0.0001 { return }

        // 비행 중에는 진행 구간만 — 전체 경로 미리보기(연한 흰색) 없음.
        let travelPath = UIBezierPath()
        let fillPath = UIBezierPath()
        var started = false
        var lastPoint = point(model.profile[0])
        for p in model.profile where p.x <= progress {
            let cgPoint = point(p)
            if !started {
                travelPath.move(to: cgPoint)
                fillPath.move(to: CGPoint(x: cgPoint.x, y: rect.maxY))
                fillPath.addLine(to: cgPoint)
                started = true
            } else {
                travelPath.addLine(to: cgPoint)
                fillPath.addLine(to: cgPoint)
            }
            lastPoint = cgPoint
        }
        if started {
            fillPath.addLine(to: CGPoint(x: lastPoint.x, y: rect.maxY))
            fillPath.close()
            FlythroughPalette.routeColor.withAlphaComponent(0.18).setFill()
            fillPath.fill()

            FlythroughPalette.routeColor.setStroke()
            travelPath.lineWidth = 2.5
            travelPath.lineJoinStyle = .round
            travelPath.stroke()

            // 진행 끝점 표시.
            let dot = UIBezierPath(ovalIn: CGRect(x: lastPoint.x - 4, y: lastPoint.y - 4, width: 8, height: 8))
            UIColor.white.setFill()
            dot.fill()
            FlythroughPalette.routeColor.setStroke()
            dot.lineWidth = 2
            dot.stroke()
        }
    }

    private func drawProfileAltitudeLabel(_ cg: CGContext, rect: CGRect, altitude: Double) {
        let labelTopInset: CGFloat = isLandscape ? -7 : 2
        let origin = CGPoint(x: rect.minX + 4, y: rect.minY + labelTopInset)
        let labelAttr = NSAttributedString(string: "고도", attributes: [
            .font: font(size: isLandscape ? 10 : 11, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.72)
        ])
        let valueAttr = NSAttributedString(
            string: "\(Int(altitude.rounded())) m",
            attributes: [
                .font: font(size: isLandscape ? 12 : 13, weight: .bold, monospacedDigit: true),
                .foregroundColor: UIColor.white
            ]
        )
        labelAttr.draw(at: origin)
        valueAttr.draw(at: CGPoint(x: origin.x, y: origin.y + (isLandscape ? 12 : 13)))
    }

    // MARK: - Primitives

    private func drawScrim(_ cg: CGContext, alpha: CGFloat) {
        UIColor.black.withAlphaComponent(min(max(alpha, 0), 1)).setFill()
        cg.fill(CGRect(origin: .zero, size: canvasSize))
    }

    private func drawSideGradient(_ cg: CGContext, rect: CGRect) {
        let colors = [
            UIColor.black.withAlphaComponent(0).cgColor,
            UIColor.black.withAlphaComponent(0.58).cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 1]
        ) else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.midY),
            end: CGPoint(x: rect.maxX, y: rect.midY),
            options: []
        )
        cg.restoreGState()
    }

    private func drawRoundedFill(_ cg: CGContext, rect: CGRect, radius: CGFloat, color: UIColor) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: radius)
        color.setFill()
        path.fill()
    }

    private func drawLeftText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        origin: CGPoint,
        maxWidth: CGFloat,
        shadow: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if shadow {
            attributes[.shadow] = textShadow(opacity: color.cgColor.alpha)
        }
        let attr = NSAttributedString(string: text, attributes: attributes)
        let bounding = attr.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let rect = CGRect(x: origin.x, y: origin.y, width: maxWidth, height: bounding.height)
        attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }

    private func textShadow(opacity: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.45 * opacity)
        shadow.shadowOffset = CGSize(width: 0, height: 1)
        shadow.shadowBlurRadius = 3
        return shadow
    }

    private func drawCenteredText(
        _ text: String,
        font: UIFont,
        color: UIColor,
        center: CGPoint,
        maxWidth: CGFloat,
        shadow: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if shadow {
            attributes[.shadow] = textShadow(opacity: color.cgColor.alpha)
        }
        let attr = NSAttributedString(string: text, attributes: attributes)
        let bounding = attr.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let rect = CGRect(
            x: center.x - maxWidth / 2,
            y: center.y - bounding.height / 2,
            width: maxWidth,
            height: bounding.height
        )
        attr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    }
}

enum FlythroughFormat {
    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func decimal(_ value: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

#endif
