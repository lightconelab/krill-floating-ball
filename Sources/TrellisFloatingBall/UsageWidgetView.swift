import AppKit

@MainActor
final class UsageWidgetView: NSView {
    enum DisplayMode {
        case ball
        case panel
    }

    var refreshAction: (() -> Void)?
    var expansionChanged: ((Bool) -> Void)?

    var snapshot: UsageSnapshot = .placeholder {
        didSet {
            needsDisplay = true
        }
    }

    var isExpanded = false {
        didSet {
            panelProgress = isExpanded ? max(panelProgress, 0.2) : panelProgress
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    private let ballSize: CGFloat = 80
    private let ballInset: CGFloat = 12
    private let panelMinWidth: CGFloat = 460
    private let panelMaxWidth: CGFloat = 580
    private let panelCardHeight: CGFloat = 66
    private let panelCardGap: CGFloat = 7
    private let panelBottomPadding: CGFloat = 16
    private let panelListTopOffset: CGFloat = 128
    private let expandedRightPadding: CGFloat = 16

    private var animationPhase: CGFloat = 0
    private var panelProgress: CGFloat = 0
    private var displayTimer: Timer?
    private var tracking: NSTrackingArea?
    private var pendingCollapse: DispatchWorkItem?
    private let displayMode: DisplayMode

    init(frame frameRect: NSRect, displayMode: DisplayMode = .ball) {
        self.displayMode = displayMode
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        updateLayerScale()
        if displayMode == .ball {
            startDisplayTimer()
        }
    }

    required init?(coder: NSCoder) {
        self.displayMode = .ball
        super.init(coder: coder)
        updateLayerScale()
        startDisplayTimer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLayerScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLayerScale()
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        pendingCollapse?.cancel()
        pendingCollapse = nil
        expansionChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        pendingCollapse?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                if self.pointerIsInsideWidget() {
                    return
                }
                self.expansionChanged?(false)
            }
        }
        pendingCollapse = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    override func mouseDown(with event: NSEvent) {
        if displayMode == .ball {
            window?.performDrag(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        switch displayMode {
        case .ball:
            drawLiquidBall()
        case .panel:
            drawExpandedPanel(progress: 1)
        }
    }

    func preferredPanelSize(maxHeight: CGFloat? = nil) -> NSSize {
        var panelHeight = preferredPanelHeight()
        if let maxHeight {
            panelHeight = min(panelHeight, max(180, maxHeight - 12))
        }
        let width = preferredPanelWidth()
        let height = panelHeight
        return NSSize(width: width, height: height)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                guard self.window?.isVisible == true else {
                    return
                }
                self.animationPhase += 0.13
                self.needsDisplay = true
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func updateLayerScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
    }

    private func updatePanelProgress() {
        let target: CGFloat = isExpanded ? 1 : 0
        panelProgress += (target - panelProgress) * 0.24
        if abs(panelProgress - target) < 0.01 {
            panelProgress = target
        }
    }

    private func ballRect() -> NSRect {
        NSRect(x: ballInset, y: (bounds.height - ballSize) / 2, width: ballSize, height: ballSize)
    }

    private func pointerIsInsideWidget() -> Bool {
        guard let window else {
            return false
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return bounds.insetBy(dx: -2, dy: -2).contains(point)
    }

    private func drawLiquidBall() {
        let rect = ballRect()
        let percentValue = snapshot.weeklyPercent
        let percent = CGFloat(max(0, min(100, percentValue ?? 0)) / 100)
        let liquidColor = liquidColor(for: percentValue)
        let critical = (percentValue ?? 0) <= 10
        let warning = (percentValue ?? 0) <= 30
        let pulse = 0.55 + 0.45 * max(0, sin(animationPhase * (critical ? 5.4 : 2.8)))

        drawBallShadow(in: rect, color: warning ? liquidColor : NSColor(hex: 0x5FC8FF), pulse: pulse)

        let sphere = NSBezierPath(ovalIn: rect)
        NSGraphicsContext.saveGraphicsState()
        sphere.addClip()
        drawLiquid(in: rect, percent: percent, color: liquidColor, pulse: pulse, critical: critical)
        drawBubbles(in: rect, color: liquidColor, percent: percent)
        drawGlassHighlights(in: rect)
        NSGraphicsContext.restoreGraphicsState()

        drawBallBorder(in: rect, color: warning ? liquidColor : NSColor(hex: 0x9EDFFF), pulse: pulse, critical: critical)
        drawWeeklyAmount(in: rect, color: warning ? .white : NSColor(hex: 0xF3FAFF))
    }

    private func drawBallShadow(in rect: NSRect, color: NSColor, pulse: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 16 + 8 * pulse
        shadow.shadowColor = color.withAlphaComponent(0.38 + 0.25 * pulse)
        shadow.shadowOffset = .zero
        shadow.set()
        color.withAlphaComponent(0.08).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -2, dy: -2)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawLiquid(in rect: NSRect, percent: CGFloat, color: NSColor, pulse: CGFloat, critical: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let waterTop = rect.maxY - rect.height * max(0.02, min(0.98, percent))
        let amplitude: CGFloat = critical ? 5.4 : 3.2
        let waveA = wavePath(in: rect, waterTop: waterTop, amplitude: amplitude, phase: animationPhase * 1.7)
        let waveB = wavePath(in: rect, waterTop: waterTop + 4, amplitude: amplitude * 0.68, phase: -animationPhase * 1.35 + 1.2)

        let fillPath = waveA.copy() as! NSBezierPath
        fillPath.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        fillPath.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        fillPath.close()

        NSGraphicsContext.saveGraphicsState()
        fillPath.addClip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlphaComponent(0.92).cgColor,
                color.blended(withFraction: 0.35, of: .white)?.withAlphaComponent(0.76).cgColor ?? color.cgColor,
                color.withAlphaComponent(0.46).cgColor
            ] as CFArray,
            locations: [0, 0.58, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: waterTop),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        NSGraphicsContext.restoreGraphicsState()

        color.withAlphaComponent(critical ? 0.9 * pulse : 0.75).setStroke()
        waveA.lineWidth = critical ? 2.1 : 1.6
        waveA.stroke()
        color.blended(withFraction: 0.35, of: .white)?.withAlphaComponent(0.42).setStroke()
        waveB.lineWidth = 1
        waveB.stroke()
    }

    private func wavePath(in rect: NSRect, waterTop: CGFloat, amplitude: CGFloat, phase: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let steps = 42
        for index in 0...steps {
            let t = CGFloat(index) / CGFloat(steps)
            let x = rect.minX + t * rect.width
            let y = waterTop + sin(t * .pi * 2.2 + phase) * amplitude + sin(t * .pi * 4.8 + phase * 0.6) * amplitude * 0.32
            if index == 0 {
                path.move(to: NSPoint(x: x, y: y))
            } else {
                path.line(to: NSPoint(x: x, y: y))
            }
        }
        return path
    }

    private func drawBubbles(in rect: NSRect, color: NSColor, percent: CGFloat) {
        let waterTop = rect.maxY - rect.height * max(0.02, min(0.98, percent))
        let bubbles: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0.28, 0.82, 2.2, 0.1),
            (0.42, 0.70, 1.5, 1.0),
            (0.66, 0.78, 2.8, 1.7),
            (0.72, 0.60, 1.8, 2.6),
            (0.36, 0.55, 1.3, 3.1)
        ]

        for bubble in bubbles {
            let drift = sin(animationPhase * 1.8 + bubble.3) * 3.2
            let rise = (animationPhase * 10 + bubble.3 * 17).truncatingRemainder(dividingBy: max(18, rect.maxY - waterTop))
            let x = rect.minX + rect.width * bubble.0 + drift
            let baseY = rect.minY + rect.height * bubble.1
            let y = max(waterTop + 6, baseY - rise)
            guard y >= waterTop, y <= rect.maxY - 8 else {
                continue
            }
            color.blended(withFraction: 0.7, of: .white)?.withAlphaComponent(0.34).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: bubble.2 * 2, height: bubble.2 * 2))
            path.lineWidth = 0.8
            path.stroke()
        }
    }

    private func drawGlassHighlights(in rect: NSRect) {
        NSColor.white.withAlphaComponent(0.18).setStroke()
        let highlight = NSBezierPath()
        highlight.appendArc(
            withCenter: NSPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.40),
            radius: rect.width * 0.33,
            startAngle: 205,
            endAngle: 288,
            clockwise: false
        )
        highlight.lineWidth = 1.2
        highlight.stroke()
    }

    private func drawBallBorder(in rect: NSRect, color: NSColor, pulse: CGFloat, critical: Bool) {
        let path = NSBezierPath(ovalIn: rect)
        color.withAlphaComponent(critical ? 0.62 + 0.34 * pulse : 0.58).setStroke()
        path.lineWidth = critical ? 2.2 : 1.5
        path.stroke()

        NSColor.white.withAlphaComponent(0.22).setStroke()
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4))
        inner.lineWidth = 0.8
        inner.stroke()
    }

    private func drawWeeklyAmount(in rect: NSRect, color: NSColor) {
        let amount = Formatters.usd(snapshot.weeklyRemaining)
        drawCentered(
            amount,
            rect: NSRect(x: rect.minX + 7, y: rect.midY - 16, width: rect.width - 14, height: 22),
            font: fittedMonospacedFont(text: amount, maxSize: 16, minSize: 10.5, width: rect.width - 14),
            color: color,
            shadow: NSColor.black.withAlphaComponent(0.72)
        )

        let time = weekRemainingText()
        drawCentered(
            time,
            rect: NSRect(x: rect.minX + 10, y: rect.midY + 7, width: rect.width - 20, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold),
            color: color.withAlphaComponent(0.86),
            shadow: NSColor.black.withAlphaComponent(0.66)
        )
    }

    private func liquidColor(for percent: Double?) -> NSColor {
        guard let percent else {
            return NSColor(hex: 0x667A8C)
        }
        if percent > 60 {
            return NSColor(hex: 0x18D7FF)
        }
        if percent > 30 {
            return NSColor(hex: 0x00FF88)
        }
        if percent > 10 {
            return NSColor(hex: 0xFFAA00)
        }
        return NSColor(hex: 0xFF144F)
    }

    private func drawExpandedPanel(progress: CGFloat) {
        let state = QuotaState(percent: snapshot.weeklyPercent)
        let height = currentPanelHeight()
        let width = currentPanelWidth()
        let panelRect = NSRect(
            x: displayMode == .panel ? 0 : ballInset + ballSize + 12 - (1 - progress) * 18,
            y: (bounds.height - height) / 2,
            width: width,
            height: height
        )
        let alpha = min(1, max(0, progress))

        NSGraphicsContext.saveGraphicsState()
        drawPanelShell(panelRect, state: state, alpha: alpha)
        drawStatsSummary(in: panelRect, state: state, alpha: alpha)
        drawSubscriptionCards(in: panelRect, alpha: alpha)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawPanelShell(_ rect: NSRect, state: QuotaState, alpha: CGFloat) {
        let path = angledPanelPath(rect)
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()

        NSColor(hex: 0xD9E6F2, alpha: alpha).setStroke()
        path.lineWidth = 1.2
        path.stroke()

        let inner = angledPanelPath(rect.insetBy(dx: 7, dy: 7))
        NSColor.white.withAlphaComponent(alpha).setFill()
        inner.fill()
        NSColor(hex: 0xE6EEF6, alpha: alpha).setStroke()
        inner.lineWidth = 0.8
        inner.stroke()
    }

    private func drawStatsSummary(in rect: NSRect, state: QuotaState, alpha: CGFloat) {
        let header = NSRect(x: rect.minX + 28, y: rect.minY + 18, width: rect.width - 56, height: 78)
        drawText(
            "今日统计",
            rect: NSRect(x: header.minX, y: header.minY, width: 86, height: 18),
            font: .systemFont(ofSize: 14.6, weight: .bold),
            color: NSColor(hex: 0x1B2633).withAlphaComponent(alpha),
            kern: 1.2
        )
        drawText(
            "(刷新时间：\(Formatters.time(snapshot.lastRefresh)))",
            rect: NSRect(x: header.minX + 70, y: header.minY + 3, width: 180, height: 14),
            font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            color: NSColor(hex: 0x64748B).withAlphaComponent(alpha)
        )

        let meta = [
            ("花费", Formatters.usd(snapshot.todayCost), NSColor(hex: 0x087EA4)),
            ("请求数", snapshot.requestCount.map(String.init) ?? "--", NSColor(hex: 0xC05BFF)),
            ("缓存率", cacheSummaryText(), NSColor(hex: 0x089981)),
            ("钱包余额", Formatters.usd(snapshot.walletBalance), NSColor(hex: 0x334155))
        ]

        let itemWidth: CGFloat = header.width / CGFloat(meta.count)
        for (index, item) in meta.enumerated() {
            let x = header.minX + CGFloat(index) * itemWidth
            drawText(
                item.0,
                rect: NSRect(x: x, y: header.minY + 27, width: itemWidth - 8, height: 13),
                font: .systemFont(ofSize: 10.5, weight: .medium),
                color: NSColor(hex: 0x64748B).withAlphaComponent(alpha),
                kern: 0.4
            )
            drawText(
                item.1,
                rect: NSRect(x: x, y: header.minY + 43, width: itemWidth - 8, height: 22),
                font: .monospacedDigitSystemFont(ofSize: index == 1 ? 15.5 : 14.1, weight: .semibold),
                color: item.2.withAlphaComponent(alpha)
            )
        }

        let line = NSBezierPath()
        line.move(to: NSPoint(x: header.minX, y: header.maxY))
        line.line(to: NSPoint(x: header.maxX, y: header.maxY))
        line.lineWidth = 0.8
        NSColor(hex: 0xE2E8F0, alpha: alpha).setStroke()
        line.stroke()
    }

    private func drawSubscriptionCards(in rect: NSRect, alpha: CGFloat) {
        let titleY = rect.minY + 106
        drawText(
            "生效套餐",
            rect: NSRect(x: rect.minX + 28, y: titleY, width: 120, height: 16),
            font: .systemFont(ofSize: 13.7, weight: .bold),
            color: NSColor(hex: 0x1B2633).withAlphaComponent(alpha),
            kern: 0.9
        )

        let listRect = NSRect(x: rect.minX + 24, y: titleY + 22, width: rect.width - 48, height: rect.maxY - titleY - 38)
        let items = snapshot.subscriptions
        guard items.isEmpty == false else {
            drawCentered(
                snapshot.needsToken ? "请先在菜单栏设置 Krill Token" : "暂无生效套餐",
                rect: listRect,
                font: .systemFont(ofSize: 12.6, weight: .medium),
                color: NSColor(hex: 0x64748B).withAlphaComponent(alpha)
            )
            return
        }

        let gap = panelCardGap
        let cardHeight = max(58, min(panelCardHeight, (listRect.height - CGFloat(max(0, items.count - 1)) * gap) / CGFloat(items.count)))
        for (index, item) in items.enumerated() {
            let y = listRect.minY + CGFloat(index) * (cardHeight + gap)
            drawSubscriptionCard(item, in: NSRect(x: listRect.minX, y: y, width: listRect.width, height: cardHeight), alpha: alpha)
        }
    }

    private func drawSubscriptionCard(_ item: SubscriptionDisplayItem, in rect: NSRect, alpha: CGFloat) {
        let percent = item.weeklyPercent ?? 0
        let color = liquidColor(for: percent)
        let compact = rect.height < 64

        let card = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor.white.withAlphaComponent(alpha).setFill()
        card.fill()
        NSColor(hex: 0xE2E8F0, alpha: alpha).setStroke()
        card.lineWidth = 0.8
        card.stroke()

        let titleFont = NSFont.systemFont(ofSize: compact ? 10.5 : 12.2, weight: .semibold)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: compact ? 8.7 : 9.6, weight: .medium)
        let periodFont = NSFont.monospacedDigitSystemFont(ofSize: compact ? 8.9 : 9.8, weight: .medium)
        let smallValueFont = NSFont.monospacedDigitSystemFont(ofSize: compact ? 7.9 : 8.5, weight: .medium)
        let labelColor = NSColor(hex: 0x64748B).withAlphaComponent(alpha)

        let topY = rect.minY + 7
        let inset: CGFloat = 10
        let remaining = remainingText(until: item.expiry, wrapped: false)
        let remainingFont = NSFont.systemFont(ofSize: compact ? 9.3 : 10.4, weight: .semibold)
        let remainingWidth = min(max(measuredWidth(remaining, font: remainingFont) + 5, compact ? 90 : 100), compact ? 122 : 136)
        let nameWidth = min(max(measuredWidth(item.name, font: titleFont) + 5, compact ? 76 : 88), compact ? 120 : 144)
        let remainingX = rect.maxX - inset - remainingWidth
        let periodX = rect.minX + inset + nameWidth + 8
        let periodWidth = max(40, remainingX - periodX - 8)
        let periodText = "\(Formatters.dateTime(item.start)) ~ \(Formatters.dateTime(item.expiry))"

        drawText(
            item.name,
            rect: NSRect(x: rect.minX + inset, y: topY, width: nameWidth, height: 16),
            font: titleFont,
            color: NSColor(hex: 0x111827).withAlphaComponent(alpha)
        )
        drawText(
            periodText,
            rect: NSRect(x: periodX, y: topY + 2, width: periodWidth, height: 14),
            font: periodFont,
            color: NSColor(hex: 0x475569).withAlphaComponent(alpha)
        )
        drawText(
            remaining,
            rect: NSRect(x: remainingX, y: topY, width: remainingWidth, height: 16),
            font: remainingFont,
            color: color.withAlphaComponent(alpha)
        )

        let quotaRowY = rect.minY + (compact ? 32 : 35)
        let innerWidth = rect.width - inset * 2
        let gap: CGFloat = 14
        let monthlyWidth = min(224, max(190, innerWidth * 0.40))
        let weeklyWidth = innerWidth - monthlyWidth - gap
        drawQuotaLine(
            label: "本周额度",
            value: "剩余 \(Formatters.usd(item.weeklyRemaining)) / \(Formatters.usd(item.weeklyTotal))",
            detail: remainingText(until: item.weekEnd),
            rect: NSRect(x: rect.minX + inset, y: quotaRowY, width: weeklyWidth, height: 13),
            labelFont: valueFont,
            valueFont: valueFont,
            detailFont: smallValueFont,
            labelColor: labelColor,
            valueColor: color.withAlphaComponent(alpha),
            detailColor: NSColor(hex: 0x64748B).withAlphaComponent(alpha)
        )

        drawInfoLine(
            label: "月额度",
            value: "剩余 \(Formatters.usd(item.monthlyRemaining)) / \(Formatters.usd(item.monthlyTotal))",
            x: rect.minX + inset + weeklyWidth + gap,
            y: quotaRowY,
            width: monthlyWidth,
            font: valueFont,
            labelColor: labelColor,
            valueColor: NSColor(hex: 0xC05BFF).withAlphaComponent(alpha)
        )

        let barRect = NSRect(x: rect.minX + 10, y: rect.maxY - 5, width: rect.width - 20, height: 2)
        NSColor(hex: 0xE2E8F0, alpha: alpha).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 1, yRadius: 1).fill()
        let fill = NSRect(x: barRect.minX, y: barRect.minY, width: barRect.width * CGFloat(percent / 100), height: barRect.height)
        color.withAlphaComponent(0.78 * alpha).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1, yRadius: 1).fill()
    }

    private func drawInfoLine(
        label: String,
        value: String,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        font: NSFont,
        labelColor: NSColor,
        valueColor: NSColor
    ) {
        let labelWidth = min(width, measuredWidth(label, font: font) + 8)
        drawText(label, rect: NSRect(x: x, y: y, width: labelWidth, height: 13), font: font, color: labelColor)
        drawText(value, rect: NSRect(x: x + labelWidth, y: y, width: width - labelWidth, height: 13), font: font, color: valueColor)
    }

    private func drawQuotaLine(
        label: String,
        value: String,
        detail: String,
        rect: NSRect,
        labelFont: NSFont,
        valueFont: NSFont,
        detailFont: NSFont,
        labelColor: NSColor,
        valueColor: NSColor,
        detailColor: NSColor
    ) {
        let labelWidth = min(rect.width, measuredWidth(label, font: labelFont) + 7)
        let valueX = rect.minX + labelWidth
        let valueWidth = min(measuredWidth(value, font: valueFont) + 4, max(0, rect.maxX - valueX))
        let detailX = valueX + valueWidth + 3
        drawText(label, rect: NSRect(x: rect.minX, y: rect.minY, width: labelWidth, height: rect.height), font: labelFont, color: labelColor)
        drawText(value, rect: NSRect(x: valueX, y: rect.minY, width: valueWidth, height: rect.height), font: valueFont, color: valueColor)
        drawText(
            detail,
            rect: NSRect(x: detailX, y: rect.minY + 1, width: max(0, rect.maxX - detailX), height: rect.height),
            font: detailFont,
            color: detailColor
        )
    }

    private func cacheSummaryText() -> String {
        guard snapshot.cacheRates.isEmpty == false else {
            return "--"
        }
        if snapshot.cacheRates.count == 1 {
            return String(format: "%.0f%%", snapshot.cacheRates[0].percent)
        }
        let average = snapshot.cacheRates.reduce(0) { $0 + $1.percent } / Double(snapshot.cacheRates.count)
        return String(format: "%.0f%%", average)
    }

    private func remainingText(until date: Date?, wrapped: Bool = true) -> String {
        guard let date else {
            return wrapped ? "(剩余--)" : "剩余--"
        }
        let text = durationText(seconds: max(0, date.timeIntervalSince(Date())))
        return wrapped ? "(剩余\(text))" : "剩余\(text)"
    }

    private func weekRemainingText() -> String {
        guard let weekEnd = snapshot.weekEnd else {
            return "--"
        }
        return durationText(seconds: max(0, weekEnd.timeIntervalSince(Date())))
    }

    private func durationText(seconds: TimeInterval) -> String {
        if seconds <= 0 {
            return "0分钟"
        }
        if seconds >= 86_400 {
            let days = Int(seconds / 86_400)
            var hours = Int(ceil((seconds - Double(days) * 86_400) / 3_600))
            var normalizedDays = days
            if hours >= 24 {
                normalizedDays += 1
                hours = 0
            }
            return "\(normalizedDays)天\(hours)小时"
        }
        if seconds >= 3_600 {
            let hours = Int(seconds / 3_600)
            var minutes = Int(ceil((seconds - Double(hours) * 3_600) / 60))
            var normalizedHours = hours
            if minutes >= 60 {
                normalizedHours += 1
                minutes = 0
            }
            return "\(normalizedHours)小时\(minutes)分钟"
        }
        return "\(max(1, Int(ceil(seconds / 60))))分钟"
    }

    private func preferredPanelHeight() -> CGFloat {
        let cardStackHeight: CGFloat
        if snapshot.subscriptions.isEmpty {
            cardStackHeight = 68
        } else {
            let count = CGFloat(snapshot.subscriptions.count)
            cardStackHeight = count * panelCardHeight + max(0, count - 1) * panelCardGap
        }
        return max(212, panelListTopOffset + cardStackHeight + panelBottomPadding)
    }

    private func currentPanelHeight() -> CGFloat {
        min(preferredPanelHeight(), max(180, bounds.height - 12))
    }

    private func preferredPanelWidth() -> CGFloat {
        var required = panelMinWidth
        let titleFont = NSFont.systemFont(ofSize: 12.2, weight: .semibold)
        let periodFont = NSFont.monospacedDigitSystemFont(ofSize: 9.8, weight: .medium)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.6, weight: .medium)
        let remainingFont = NSFont.systemFont(ofSize: 10.4, weight: .semibold)
        let cardHorizontalPadding: CGFloat = 20
        let listHorizontalPadding: CGFloat = 48

        for item in snapshot.subscriptions {
            let nameWidth = min(max(measuredWidth(item.name, font: titleFont) + 5, 88), 144)
            let period = "\(Formatters.dateTime(item.start)) ~ \(Formatters.dateTime(item.expiry))"
            let topWidth = cardHorizontalPadding
                + nameWidth
                + 8
                + measuredWidth(period, font: periodFont)
                + 8
                + measuredWidth(remainingText(until: item.expiry, wrapped: false), font: remainingFont)

            let weeklyValue = "剩余 \(Formatters.usd(item.weeklyRemaining)) / \(Formatters.usd(item.weeklyTotal))"
            let weeklyWidth = measuredWidth("本周额度", font: valueFont)
                + 7
                + measuredWidth(weeklyValue, font: valueFont)
                + 7
                + measuredWidth(remainingText(until: item.weekEnd), font: valueFont)
            let monthlyValue = "剩余 \(Formatters.usd(item.monthlyRemaining)) / \(Formatters.usd(item.monthlyTotal))"
            let monthlyWidth = measuredWidth("月额度", font: valueFont)
                + 8
                + measuredWidth(monthlyValue, font: valueFont)
            let quotaWidth = cardHorizontalPadding + weeklyWidth + 14 + monthlyWidth

            required = max(required, topWidth + listHorizontalPadding, quotaWidth + listHorizontalPadding)
        }

        return min(panelMaxWidth, ceil(required))
    }

    private func currentPanelWidth() -> CGFloat {
        if displayMode == .panel {
            return min(preferredPanelWidth(), max(panelMinWidth, bounds.width))
        }
        return min(preferredPanelWidth(), max(panelMinWidth, bounds.width - ballInset - ballSize - 12 - expandedRightPadding))
    }

    private func angledPanelPath(_ rect: NSRect) -> NSBezierPath {
        let radius: CGFloat = 16
        return NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }

    private func fittedMonospacedFont(text: String, maxSize: CGFloat, minSize: CGFloat, width: CGFloat) -> NSFont {
        var size = maxSize
        while size > minSize {
            let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
            let measured = (text as NSString).size(withAttributes: [.font: font]).width
            if measured <= width {
                return font
            }
            size -= 0.5
        }
        return .monospacedDigitSystemFont(ofSize: minSize, weight: .bold)
    }

    private func measuredWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawCentered(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0,
        shadow: NSColor? = nil
    ) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style,
            .kern: kern
        ]

        if let shadow {
            let textShadow = NSShadow()
            textShadow.shadowColor = shadow
            textShadow.shadowBlurRadius = 12
            textShadow.shadowOffset = .zero
            attributes[.shadow] = textShadow
        }

        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawText(
        _ text: String,
        rect: NSRect,
        font: NSFont,
        color: NSColor,
        kern: CGFloat = 0
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: kern
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}
