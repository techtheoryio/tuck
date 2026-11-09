import AppKit
import SwiftUI
import TuckCore

@MainActor @Observable
final class NotchModel {
    enum Phase { case idle, arming, open }

    static let openWidth: CGFloat = 400
    static let rowHeight: CGFloat = 40
    static let inputHeight: CGFloat = 49
    static let maxRows = 7

    /// On Macs with a Dynamic Island the camera is a pill inside the menu bar, not a notch hanging from the top edge.
    /// The public API reports only its bounding box from the top edge; the pill itself starts 9.5 pt below it
    /// (70 × 38 pt on a 14" MacBook Pro, read once from the private `_centerHUDMinimalObstructionFrame`).
    static let islandTopInset: CGFloat = 9.5
    /// macOS grows its own black pill about its center when hovered (MenuBarAgent's `hoverScale`), measured from photos.
    static let islandHoverScale: CGFloat = 1.15
    /// How far the shape reaches past the pill while hovered or open: less than the system's hover growth,
    /// so ours stays hidden inside the system's pill until the panel opens.
    static let islandGrow: CGFloat = 3
    /// From the system's hovered pill to the middle of the arming ring's stroke. The ring then just fits the menu bar.
    static let islandRingOutset: CGFloat = 2.5
    static let islandOpenRadius: CGFloat = 28
    /// The most the hovered pill leans toward the pointer, by eye: the system's own limit isn't readable.
    static let islandLean = CGSize(width: 5, height: 2.5)

    var phase = Phase.idle
    var notch = CGSize(width: 190, height: 32)
    var hasNotch = false
    var isIsland = false
    var lean = CGSize.zero  // while arming on the island, see NotchController.updateLean
    var draft = ""
    var list: TodoList { didSet { save() } }
    @ObservationIgnored private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        list = TodoList.load(from: fileURL)
    }

    var listHeight: CGFloat {
        list.items.isEmpty ? 56 : CGFloat(min(list.items.count, Self.maxRows)) * Self.rowHeight + 12
    }

    var pill: CGSize { CGSize(width: notch.width, height: notch.height - Self.islandTopInset) }
    var grownPill: CGSize { CGSize(width: pill.width + 2 * Self.islandGrow, height: pill.height + 2 * Self.islandGrow) }

    /// The top row of the open panel, which the notch or pill sits in.
    var headerHeight: CGFloat { isIsland ? grownPill.height : notch.height }

    /// Distance from the screen's top edge to the drawn shape: a notch hangs from the edge, the island floats below it.
    var top: CGFloat {
        guard isIsland else { return 0 }
        return phase == .idle ? Self.islandTopInset : Self.islandTopInset - Self.islandGrow
    }

    var size: CGSize {
        switch phase {
        case .idle: isIsland ? pill : notch
        // The hardware notch has no pixels, so grow a visible strip below it for the arming bar.
        // The island gets a ring around it instead (see ArmingRing).
        case .arming: isIsland ? grownPill : CGSize(width: notch.width + 18, height: notch.height + 14)
        case .open: CGSize(width: Self.openWidth, height: headerHeight + listHeight + Self.inputHeight)
        }
    }

    private func save() {
        do { try list.save(to: fileURL) } catch { NSLog("Tuck: could not save to-dos: \(error)") }
    }
}

/// Mouse-moved monitors decide when the panel opens: resting on the notch for the hover delay opens it,
/// leaving the open panel closes it. While closed the window ignores the mouse, so the menu bar around it keeps working.
@MainActor
final class NotchController {
    static let animation = Animation.spring(duration: 0.32, bounce: 0.2)
    static let closeAnimation = Animation.spring(duration: 0.28, bounce: 0)  // no overshoot when it tucks back in

    let model: NotchModel
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var armTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private let pinnedOpen = ProcessInfo.processInfo.environment["TUCK_OPEN"] != nil  // debug: stay open regardless of the mouse

    init(model: NotchModel) {
        self.model = model
        let host = NSHostingView(rootView: NotchView(controller: self))
        host.sizingOptions = []  // the window keeps its fixed frame; the notch shape animates inside it
        panel.contentView = host
        place()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        // Global: the mouse is over other apps (or our window ignores it). Local: it is over the open panel.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved() }
            return event
        }
        // While closed the window ignores the mouse, so a click on the notch lands in the menu bar: global is enough.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        if pinnedOpen { open() }
        if let path = ProcessInfo.processInfo.environment["TUCK_SNAPSHOT"] { snapshot(to: path) }
    }

    /// Debug: writes a PNG of the panel's window once the open animation has settled, then quits.
    private func snapshot(to path: String) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
            exit(0)
        }
    }

    /// Grows the notch and fills the arming bar; opens once the hover delay has passed.
    func arm() {
        withAnimation(Self.animation) { model.phase = .arming }
        armTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "hoverDelay")))
            if !Task.isCancelled { self?.open() }
        }
    }

    func open() {
        armTask?.cancel()
        panel.ignoresMouseEvents = false
        panel.makeKey()
        withAnimation(Self.animation) { model.phase = .open }
    }

    func close() {
        armTask?.cancel()
        closeTask?.cancel()
        closeTask = nil
        model.draft = ""
        panel.ignoresMouseEvents = true
        withAnimation(Self.closeAnimation) { model.phase = .idle } completion: { [weak self] in
            MainActor.assumeIsolated {
                // A non-activating panel stays key until it leaves the screen. Once it has shrunk back into the notch,
                // reorder it (no window fade, see NotchPanel) so typing goes back to the app underneath.
                guard let self, self.model.phase == .idle else { return }
                self.panel.orderOut(nil)
                self.panel.orderFrontRegardless()
            }
        }
    }

    /// The window is sized for the open panel; this positions it over the notch of the built-in display
    /// (or at the top center of the main display on Macs without one).
    private func place() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        self.screen = screen
        model.hasNotch = screen.safeAreaInsets.top > 0
        if model.hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notch = CGSize(width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
            // A notch is about six times as wide as it is tall; the island's bounding box is barely wider than tall.
            model.isIsland = model.notch.width < model.notch.height * 3
        } else {
            model.isIsland = false
            model.notch = CGSize(width: 190, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
        }
        let size = CGSize(width: 520, height: 480)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    /// Whether the pointer is over the notch (or island), or over the open panel.
    private func pointerInside(_ screen: NSScreen) -> Bool {
        let open = model.phase == .open
        // From the top edge down to the bottom of the shape, so the menu bar strip above the island counts too.
        let size = CGSize(width: model.size.width, height: model.top + model.size.height)
        let rect = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                          width: size.width, height: size.height)
        // A little slack: the top pixel row, a margin around the open panel so its edge isn't a tripwire,
        // and room beside the island, which is a narrow target.
        let dx: CGFloat = open ? -12 : model.isIsland ? -14 : 0
        return rect.insetBy(dx: dx, dy: open ? -12 : -2).contains(NSEvent.mouseLocation)
    }

    /// A click or tap on the notch opens the list right away: touch screens have no hover.
    private func mouseDown() {
        guard let screen, model.phase != .open, pointerInside(screen) else { return }
        open()
    }

    private func mouseMoved() {
        guard let screen, !pinnedOpen else { return }
        let inside = pointerInside(screen)

        switch (model.phase, inside) {
        case (.idle, true):
            arm()
        case (.arming, false):
            armTask?.cancel()
            withAnimation(Self.closeAnimation) { model.phase = .idle }
        case (.open, true):
            closeTask?.cancel()
            closeTask = nil
        case (.open, false) where closeTask == nil && model.draft.trimmingCharacters(in: .whitespaces).isEmpty:
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { self?.close() }
            }
        default:
            break
        }
        updateLean(screen)
    }

    /// macOS leans its hovered pill toward the pointer, rubber-banded (MenuBarAgent's `inertHoverLean`).
    /// The ring and our shape lean the same way so they stay around it.
    private func updateLean(_ screen: NSScreen) {
        guard model.isIsland, model.phase == .arming else { return }
        let mouse = NSEvent.mouseLocation
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - NotchModel.islandTopInset - model.pill.height / 2)
        let lean = CGSize(width: Self.rubberband(mouse.x - center.x, limit: NotchModel.islandLean.width, range: model.pill.width / 2),
                          height: Self.rubberband(center.y - mouse.y, limit: NotchModel.islandLean.height, range: model.pill.height / 2))
        withAnimation(.spring(duration: 0.3, bounce: 0.15)) { model.lean = lean }
    }

    /// Follows `x` at first, then flattens toward `limit`: half of it when `x` reaches `range`.
    private static func rubberband(_ x: CGFloat, limit: CGFloat, range: CGFloat) -> CGFloat {
        let d = abs(x) / range
        return (x < 0 ? -1 : 1) * limit * d / (d + 1)
    }
}

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)  // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        animationBehavior = .none  // panels fade out on orderOut by default
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }  // allow covering the menu bar
}
