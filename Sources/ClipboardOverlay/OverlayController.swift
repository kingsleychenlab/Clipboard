import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The floating overlay window.
///
/// Borderless windows refuse key status by default, which would make the filter
/// field untypable — `canBecomeKey` is overridden to opt back in.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Show on whichever Space is active, including over a fullscreen app,
        // instead of yanking the user back to the Space we were summoned from.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = false
        // We drive our own fade; AppKit's default window animation adds lag.
        animationBehavior = .none
        isReleasedWhenClosed = false
    }
}

/// Shows and hides the overlay, and owns the focus dance.
///
/// Focus, the fiddly part: a `.nonactivatingPanel` won't activate our app when
/// *clicked*, but macOS still routes keystrokes only to the frontmost app — so
/// type-to-filter requires activating. The overlay therefore records whoever was
/// frontmost before it appears and hands focus straight back on dismiss, so the
/// paste lands in the app the user was actually in. Verified: on show the app is
/// active and the panel is key; on hide the previous app is active again.
final class OverlayController {
    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = 360

    private let model: OverlayViewModel
    private var panel: OverlayPanel?
    private var keyMonitor: Any?
    private(set) var previousApp: NSRunningApplication?
    private(set) var isVisible = false

    /// Called with the chosen clip once the overlay has hidden and focus has
    /// been handed back — the paste target must be frontmost first.
    var onSelect: ((ClipItem, NSRunningApplication?) -> Void)?

    #if DEBUG
        // Test hooks — compiled out of release builds entirely.
        var debugModel: OverlayViewModel { model }
        var debugPanel: NSPanel? { panel }
    #endif

    init(history: ClipboardHistory) {
        model = OverlayViewModel(history: history)

        // Clicking another app (or the desktop) dismisses the overlay. Focus is
        // already gone to wherever the user clicked, so don't drag it back.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide(restoringFocus: false)
        }
    }

    /// Builds the panel lazily and reuses it — recreating per summon costs
    /// milliseconds we don't have if the overlay is to feel instant.
    private func makePanelIfNeeded() -> OverlayPanel {
        if let panel { return panel }
        let rect = NSRect(x: 0, y: 0, width: Self.panelWidth, height: Self.panelHeight)
        let panel = OverlayPanel(contentRect: rect)
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        self.panel = panel
        return panel
    }

    func toggle() {
        isVisible ? hide(restoringFocus: true) : show()
    }

    func show() {
        guard !isVisible else { return }

        // Capture this BEFORE activating: once we activate, we are frontmost and
        // the answer is us.
        previousApp = NSWorkspace.shared.frontmostApplication

        model.reset()
        let panel = makePanelIfNeeded()
        position(panel)

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isVisible = true
        installKeyMonitor()

        // Fading the window (not the SwiftUI content) so the drop shadow fades
        // with it instead of popping in at full strength.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.async { self.model.isPresented = true }
    }

    func hide(restoringFocus: Bool) {
        guard isVisible, let panel else { return }
        isVisible = false
        removeKeyMonitor()
        model.isPresented = false

        // Focus goes back immediately rather than waiting out the fade — the
        // paste has to land the moment the user hits Enter.
        if restoringFocus, let previousApp, !previousApp.isTerminated {
            previousApp.activate()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.09
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            // Re-summoned mid-fade? Leave the now-visible panel alone.
            guard self?.isVisible == false else { return }
            panel.orderOut(nil)
        }
    }

    /// Arrow keys would otherwise move the text cursor, and Enter/Escape would
    /// be swallowed by the field. A local monitor sees keys before the field
    /// does; returning nil consumes the event, returning it passes it through so
    /// ordinary typing still reaches the query box.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch Int(event.keyCode) {
            // Cmd+Delete, the Finder idiom. Plain Delete must fall through to the
            // query field, or you couldn't correct a typo without destroying a
            // clip. (Note `case a, b where c` would bind the `where` to `b` only.)
            case kVK_Delete, kVK_ForwardDelete:
                guard flags.contains(.command) else { return event }
                self.model.deleteSelected()
                return nil
            case kVK_Escape:
                self.hide(restoringFocus: true)
                return nil
            case kVK_DownArrow:
                self.model.moveSelection(by: 1)
                return nil
            case kVK_UpArrow:
                self.model.moveSelection(by: -1)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.commitSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func commitSelection() {
        guard let item = model.selectedItem else { return }
        let target = previousApp
        hide(restoringFocus: true)
        onSelect?(item, target)
    }

    /// Centers horizontally on the screen holding the cursor, sitting in the
    /// upper third — where Spotlight puts itself, and where the eye already is.
    private func position(_ panel: OverlayPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let x = frame.midX - Self.panelWidth / 2
        let y = frame.midY + frame.height / 6 - Self.panelHeight / 2
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }
}
