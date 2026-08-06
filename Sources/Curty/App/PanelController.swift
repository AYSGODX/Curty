import AppKit
import SwiftUI

enum PanelInteractionPolicy {
    static let sampleInterval: TimeInterval = 1.0 / 60.0
    static let idleSampleInterval: TimeInterval = 0.1
    static let closeDelay: TimeInterval = 0.22
    static let closeAnimationDuration: TimeInterval = 0.08

    /// NSRect.contains treats maxY as outside the rectangle, and the cursor
    /// lands exactly on screenFrame.maxY when it is shoved into the top of the
    /// screen. Without slack past the edge that last row read as "outside the
    /// notch" and closed the panel.
    static let topEdgeSlack: CGFloat = 4


    static func activationRect(
        screenFrame: NSRect,
        safeAreaTop: CGFloat,
        leftAuxiliaryArea: NSRect?,
        rightAuxiliaryArea: NSRect?
    ) -> NSRect {
        let height = max(34, min(54, safeAreaTop + 14))

        if let leftAuxiliaryArea, let rightAuxiliaryArea {
            let notchWidth = rightAuxiliaryArea.minX - leftAuxiliaryArea.maxX
            if notchWidth >= 24 {
                return NSRect(
                    x: leftAuxiliaryArea.maxX - 30,
                    y: screenFrame.maxY - height,
                    width: notchWidth + 60,
                    height: height + topEdgeSlack
                )
            }
        }

        return NSRect(
            x: screenFrame.midX - 130,
            y: screenFrame.maxY - height,
            width: 260,
            height: height + topEdgeSlack
        )
    }
}

/// Mission Control does not create a window of its own kind — it stacks extra
/// full-screen windows on top of the ones the Dock already keeps whenever the
/// wallpaper is visible. Hard-coding how many there should be is what left the
/// notch dead on a bare desktop, so the resting count is learned instead and
/// only a rise above it reads as an overlay. Should a system update make the
/// higher count normal, it settles into the new baseline and suppression stops
/// by itself; the notch can never stay blocked.
struct DockOverlayWatch {
    /// How long an elevated count may persist before it is accepted as normal.
    /// Only time spent with the cursor in the notch counts towards it.
    static let settleInterval: TimeInterval = 8

    private var restingCount: Int?
    private var elevatedSince: TimeInterval?

    mutating func isOverlayPresent(fullScreenDockWindows count: Int, now: TimeInterval) -> Bool {
        guard let resting = restingCount else {
            restingCount = count
            return false
        }

        if count <= resting {
            restingCount = count
            elevatedSince = nil
            return false
        }

        let since = elevatedSince ?? now
        elevatedSince = since
        guard now - since < Self.settleInterval else {
            restingCount = count
            elevatedSince = nil
            return false
        }
        return true
    }
}

/// Counts on-screen windows the Dock draws over most of the display. Geometry
/// and owner only — no titles, no contents, no screen capture.
enum SystemOverlayPolicy {
    static let coverageThreshold: CGFloat = 0.5

    static func coversDisplay(width: CGFloat, height: CGFloat, screenSize: CGSize) -> Bool {
        let screenArea = screenSize.width * screenSize.height
        guard screenArea > 0 else { return false }
        return width * height >= screenArea * coverageThreshold
    }

    static func fullScreenDockWindowCount(screenSize: CGSize) -> Int {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return 0 }

        return windows.reduce(into: 0) { total, window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let width = bounds["Width"] as? CGFloat,
                  let height = bounds["Height"] as? CGFloat,
                  coversDisplay(width: width, height: height, screenSize: screenSize) else { return }
            total += 1
        }
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {
    private let model: AppModel
    private let panel: FloatingPanel
    private var cursorTimer: Timer?
    private var closeWorkItem: DispatchWorkItem?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var overlayWatch = DockOverlayWatch()
    private var overlayCheckedAt: TimeInterval = 0
    private var overlayWasVisible = false
    private var awaitsCursorArrival = false

    private let panelSize = NSSize(width: 488, height: 420)

    init(model: AppModel) {
        self.model = model
        panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(rootView: PanelRootView(model: model))
    }

    func install() {
        position(on: NSScreen.main)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        startCursorMonitoring()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position(on: self?.screenUnderMouse() ?? NSScreen.main) }
        }
    }

    func teardown() {
        cancelClose()
        cursorTimer?.invalidate()
        cursorTimer = nil
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        panel.orderOut(nil)
    }

    func toggle(holdingUntilCursorArrives: Bool = false) {
        model.isPanelOpen ? close() : open(holdingUntilCursorArrives: holdingUntilCursorArrives)
    }

    /// Opened from the menu bar the cursor is nowhere near the panel, so the
    /// ordinary "cursor left" rule would close it again within a frame. In that
    /// case hold it open until the cursor has actually visited it once.
    func open(holdingUntilCursorArrives: Bool = false) {
        cancelClose()
        guard !model.isPanelOpen else { return }
        awaitsCursorArrival = holdingUntilCursorArrives
        position(on: screenUnderMouse() ?? NSScreen.main)
        model.isPanelOpen = true
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        scheduleCursorTimer(interval: PanelInteractionPolicy.sampleInterval)
    }

    func close() {
        closeWorkItem = nil
        guard !model.isPinned else { return }
        awaitsCursorArrival = false
        model.isPanelOpen = false
        panel.ignoresMouseEvents = true
        scheduleCursorTimer(interval: PanelInteractionPolicy.idleSampleInterval)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PanelInteractionPolicy.closeAnimationDuration
            panel.animator().alphaValue = 0
        }
    }

    private func startCursorMonitoring() {
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] _ in
            Task { @MainActor in self?.sampleCursor() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in self?.sampleCursor() }
            return event
        }

        scheduleCursorTimer(interval: PanelInteractionPolicy.idleSampleInterval)
    }

    // The mouse monitors above drive every ordinary hover, so the timer only
    // has to catch a cursor that reaches the activation zone without sending
    // an event: after a wake, a Space switch, or another app's tracking loop.
    // While the panel is open it samples at full rate to notice the cursor
    // leaving; while closed a slow poll is enough and lets the CPU idle.
    private func scheduleCursorTimer(interval: TimeInterval) {
        cursorTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleCursor() }
        }
        timer.tolerance = interval / 4
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func sampleCursor() {
        let point = NSEvent.mouseLocation
        guard let screen = screen(containing: point) else { return }
        let activation = PanelInteractionPolicy.activationRect(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            leftAuxiliaryArea: screen.auxiliaryTopLeftArea,
            rightAuxiliaryArea: screen.auxiliaryTopRightArea
        )

        if activation.contains(point) {
            if !model.isPanelOpen, isSystemOverlayVisible(on: screen) { return }
            open()
            return
        }

        guard model.isPanelOpen, !model.isPinned else { return }
        if panel.attachedSheet != nil || panel.frame.insetBy(dx: -8, dy: -8).contains(point) {
            awaitsCursorArrival = false
            cancelClose()
        } else if awaitsCursorArrival {
            cancelClose()
        } else {
            scheduleClose()
        }
    }

    /// Only consulted while the cursor sits in the activation zone and the panel
    /// is closed, so the window scan stays rare; the cache bounds it during a
    /// suppressed hover.
    private func isSystemOverlayVisible(on screen: NSScreen) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - overlayCheckedAt < 0.2 { return overlayWasVisible }
        overlayCheckedAt = now
        overlayWasVisible = overlayWatch.isOverlayPresent(
            fullScreenDockWindows: SystemOverlayPolicy.fullScreenDockWindowCount(screenSize: screen.frame.size),
            now: now
        )
        return overlayWasVisible
    }

    private func scheduleClose() {
        guard closeWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.close() }
        }
        closeWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + PanelInteractionPolicy.closeDelay,
            execute: work
        )
    }

    private func cancelClose() {
        closeWorkItem?.cancel()
        closeWorkItem = nil
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let origin = NSPoint(
            x: screen.frame.midX - panelSize.width / 2,
            y: screen.frame.maxY - panelSize.height - 10
        )
        panel.setFrameOrigin(origin)
    }

    private func screenUnderMouse() -> NSScreen? {
        screen(containing: NSEvent.mouseLocation)
    }

    private func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }
}
