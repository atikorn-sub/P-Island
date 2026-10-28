import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // Allow the window to sit over the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Owns the panel, keeps it over the notch, and opens/closes it from mouse position.
/// The panel ignores the mouse while closed so the menu bar stays clickable;
/// hover is detected with event monitors instead.
final class NotchController {
    let state: NotchState
    let panel = NotchPanel()

    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var stickyUntil: Date?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var sizeObserver: AnyCancellable?
    private var alertObserver: AnyCancellable?
    private var miniObserver: AnyCancellable?
    private var swipeDistance: CGFloat = 0
    private var swipeUsed = false
    /// Sideways swipe on the closed notch: skips songs.
    private var songSwipe: CGFloat = 0
    private var songSwipeUsed = false
    /// After a song swipe the notch stays closed until the pointer leaves it.
    private var holdClosedUntilLeave = false
    private var openedAt = Date.distantPast

    /// The open panel plus room for its shadow.
    private var windowSize: CGSize {
        CGSize(width: state.openSize.width + 60, height: state.openSize.height + 40)
    }

    init(state: NotchState) {
        self.state = state
        let host = NotchHostingView(state: state)
        host.sizingOptions = []
        host.safeAreaRegions = []
        panel.contentView = host
        layout()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.layout() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.panel.orderFrontRegardless() }
        // @Published fires before the value changes, so lay out on the next turn of the run loop.
        sizeObserver = state.settings.$sizeScale.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }
        // When a card goes away while the panel is closed, let clicks reach the menu bar again.
        alertObserver = state.$alert.sink { [weak self] alert in
            guard let self, alert == nil, !self.state.isOpen else { return }
            self.panel.ignoresMouseEvents = true
            self.state.holdAlert(false)
            self.giveKeyboardBack()
        }
        state.requestKeyboard = { [weak self] in
            self?.panel.makeKey()
        }
        state.openPanel = { [weak self] in self?.open() }
        // When the slim bar goes away under the pointer, let clicks reach the menu bar again.
        miniObserver = state.music.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, !self.state.isOpen, self.state.alert == nil,
                      self.state.closedActivity != .miniPlayer else { return }
                self.panel.ignoresMouseEvents = true
            }
        }
    }

    // MARK: Geometry

    private func layout() {
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let s = notched ?? NSScreen.main ?? NSScreen.screens.first else { return }
        screen = s
        if let left = s.auxiliaryTopLeftArea, let right = s.auxiliaryTopRightArea, s.safeAreaInsets.top > 0 {
            state.notchSize = CGSize(width: s.frame.width - left.width - right.width, height: s.safeAreaInsets.top)
            state.hasNotch = true
        } else {
            let menuBar = s.frame.maxY - s.visibleFrame.maxY
            state.notchSize = CGSize(width: 180, height: max(menuBar, 24))
            state.hasNotch = false
        }
        let size = windowSize
        panel.setFrame(NSRect(x: s.frame.midX - size.width / 2, y: s.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func topCenteredRect(_ size: CGSize) -> NSRect {
        let f = screen?.frame ?? .zero
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    private var openRect: NSRect { topCenteredRect(state.openSize) }

    /// Closed notch plus a little slack; extends above the screen edge so the very top pixel counts.
    private var hoverRect: NSRect {
        let r = topCenteredRect(state.closedSize)
        return NSRect(x: r.minX - 6, y: r.minY - 4, width: r.width + 12, height: r.height + 8)
    }

    private var dragHotRect: NSRect { hoverRect.insetBy(dx: -40, dy: -20) }

    // MARK: Open / close

    func open(tab: NotchTab? = nil, sticky: TimeInterval? = nil) {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        if let tab { state.tab = tab }
        if let sticky {
            stickyUntil = Date().addingTimeInterval(sticky)
            DispatchQueue.main.asyncAfter(deadline: .now() + sticky + 0.05) { [weak self] in
                self?.evaluateHover()
            }
        }
        guard !state.isOpen else { return }
        panel.ignoresMouseEvents = false
        state.isOpen = true
        openedAt = Date()
        if state.settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func close() {
        openWork?.cancel()
        openWork = nil
        closeWork?.cancel()
        closeWork = nil
        stickyUntil = nil
        state.shelf.dropTargeting = false
        guard state.isOpen else { return }
        state.isOpen = false
        panel.ignoresMouseEvents = true
        giveKeyboardBack()
    }

    /// After typing in the panel (clipboard search, a reply), hand the keyboard back to the app underneath.
    private func giveKeyboardBack() {
        guard panel.isKeyWindow else { return }
        panel.resignKey()
        NSWorkspace.shared.frontmostApplication?.activate()
    }

    /// Hotkey behaviour: open on `tab`, or close if it is already showing.
    func toggle(tab: NotchTab? = nil) {
        if state.isOpen && (tab == nil || state.tab == tab) {
            close()
        } else {
            open(tab: tab, sticky: 4)
        }
    }

    // MARK: Mouse tracking

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
        if let scroll = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] in self?.handleScroll($0); return $0 }) {
            monitors.append(scroll)
        }
        // While closed the panel lets the pointer through, so its scrolls arrive as other apps' events.
        if let scroll = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] in self?.handleScroll($0) }) {
            monitors.append(scroll)
        }
    }

    /// A sideways two-finger swipe on the closed notch while music plays: left for the next song,
    /// right for the previous one, like flicking through covers.
    private func handleSongSwipe(_ event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty, state.music.hasTrack,
              hoverRect.insetBy(dx: -6, dy: -4).contains(NSEvent.mouseLocation) else { return }
        switch event.phase {
        case .began:
            songSwipe = 0
            songSwipeUsed = false
        case .ended, .cancelled:
            return
        default:
            break
        }
        // Swiping here means "skip", not "open": keep the hover from opening the panel.
        openWork?.cancel()
        openWork = nil
        holdClosedUntilLeave = true
        guard !songSwipeUsed, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 else { return }
        songSwipe += event.scrollingDeltaX
        guard abs(songSwipe) > 40 else { return }
        songSwipeUsed = true
        if songSwipe < 0 { state.music.next() } else { state.music.previous() }
        if state.settings.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// A sideways two-finger swipe on the open panel moves to the next / previous tab.
    private func handleScroll(_ event: NSEvent) {
        if !state.isOpen {
            handleSongSwipe(event)
            return
        }
        // The hover opened the panel a moment before the fingers started swiping on the notch:
        // that was meant for the songs, so fold the panel back and let the swipe skip.
        if event.phase == .began, state.music.hasTrack, Date().timeIntervalSince(openedAt) < 0.8,
           hoverRect.contains(NSEvent.mouseLocation), abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY) {
            close()
            handleSongSwipe(event)
            return
        }
        guard event.hasPreciseScrollingDeltas else { return }
        switch event.phase {
        case .began:
            swipeDistance = 0
            swipeUsed = false
        case .ended, .cancelled:
            swipeDistance = 0
            swipeUsed = false
            return
        default:
            break
        }
        guard !swipeUsed, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 else { return }
        if state.tab == .shelf && state.shelf.items.count > 5 { return } // the shelf scrolls sideways itself
        swipeDistance += event.scrollingDeltaX
        guard abs(swipeDistance) > 50 else { return }
        swipeUsed = true
        let tabs = NotchTab.allCases
        guard let i = tabs.firstIndex(of: state.tab) else { return }
        let next = swipeDistance < 0 ? i + 1 : i - 1
        if tabs.indices.contains(next) { state.tab = tabs[next] }
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if state.isOpen, !state.holdOpen, !openRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) {
                close()
            }
        case .leftMouseDragged:
            handleDrag()
        case .leftMouseUp:
            // The drag ended (dropped or let go elsewhere): back to the normal shelf once the drop has landed.
            if state.shelf.dropTargeting {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.state.shelf.dropTargeting = false }
            }
        default:
            evaluateHover()
        }
    }

    /// Opens the shelf when a file is dragged up to the notch.
    private func handleDrag() {
        let pb = NSPasteboard(name: .drag)
        let fileTypes: [NSPasteboard.PasteboardType] = [.fileURL, .tiff, .png, .init("NSFilenamesPboardType")]
        let isFileDrag = pb.changeCount != dragChangeCount && (pb.types ?? []).contains { fileTypes.contains($0) }
        guard isFileDrag else {
            evaluateHover()
            return
        }
        let p = NSEvent.mouseLocation
        if state.isOpen {
            if openRect.contains(p) {
                if state.tab != .shelf { state.tab = .shelf }
                if !state.shelf.dropTargeting { state.shelf.dropTargeting = true }
            }
            evaluateHover()
        } else if dragHotRect.contains(p) {
            state.shelf.dropTargeting = true
            open(tab: .shelf)
        }
    }

    private func evaluateHover() {
        let p = NSEvent.mouseLocation
        if state.isOpen {
            if let until = stickyUntil, until > Date() { return }
            if state.holdOpen {
                closeWork?.cancel()
                closeWork = nil
                return
            }
            if openRect.insetBy(dx: -8, dy: -8).contains(p) {
                closeWork?.cancel()
                closeWork = nil
            } else if closeWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.close() }
                closeWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            }
        } else if let alert = state.alert, alert.isInteractive {
            // Volume, brightness and meeting cards take the pointer themselves instead of opening the panel.
            let inside = topCenteredRect(state.closedSize).insetBy(dx: -6, dy: -6).contains(p)
            panel.ignoresMouseEvents = !inside
            state.holdAlert(inside || alert.keepsFocus)
        } else if state.closedActivity == .miniPlayer {
            // The slim bar's buttons are clickable in place; only the camera area opens the panel.
            panel.ignoresMouseEvents = !topCenteredRect(state.closedSize).insetBy(dx: -4, dy: -4).contains(p)
            scheduleOpen(if: cameraRect.contains(p)) { [weak self] in self?.cameraRect.contains(NSEvent.mouseLocation) ?? false }
        } else {
            scheduleOpen(if: hoverRect.contains(p)) { [weak self] in self?.hoverRect.contains(NSEvent.mouseLocation) ?? false }
        }
    }

    /// Opens after a short pause while the pointer stays put, so passing over the notch doesn't pop it open.
    private func scheduleOpen(if inside: Bool, stillInside: @escaping () -> Bool) {
        guard inside else {
            openWork?.cancel()
            openWork = nil
            holdClosedUntilLeave = false
            return
        }
        guard !holdClosedUntilLeave else { return }
        guard openWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWork = nil
            if stillInside() { self.open() }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// The camera housing itself, plus a little room above.
    private var cameraRect: NSRect {
        let r = topCenteredRect(state.notchSize)
        return NSRect(x: r.minX, y: r.minY - 2, width: r.width, height: r.height + 6)
    }
}
