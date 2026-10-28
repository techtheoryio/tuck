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

    var phase = Phase.idle
    var notch = CGSize(width: 190, height: 32)
    var hasNotch = false
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

    var size: CGSize {
        switch phase {
        case .idle: notch
        // The hardware notch has no pixels, so grow a visible strip below it for the arming bar.
        case .arming: CGSize(width: notch.width + 18, height: notch.height + 14)
        case .open: CGSize(width: Self.openWidth, height: notch.height + listHeight + Self.inputHeight)
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
        } else {
            model.notch = CGSize(width: 190, height: max(screen.frame.maxY - screen.visibleFrame.maxY, 24))
        }
        let size = CGSize(width: 520, height: 480)
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func mouseMoved() {
        guard let screen, !pinnedOpen else { return }
        let size = model.phase == .idle ? model.notch : model.size
        let rect = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
                          width: size.width, height: size.height)
        // A little slack: the top pixel row, and a margin around the open panel so its edge isn't a tripwire.
        let inside = rect.insetBy(dx: model.phase == .open ? -12 : 0, dy: model.phase == .open ? -12 : -2)
            .contains(NSEvent.mouseLocation)

        switch (model.phase, inside) {
        case (.idle, true):
            withAnimation(Self.animation) { model.phase = .arming }
            armTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "hoverDelay")))
                if !Task.isCancelled { self?.open() }
            }
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
