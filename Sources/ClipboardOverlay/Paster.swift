import AppKit
import Carbon.HIToolbox

/// Writes a clip to the pasteboard and synthesizes Cmd+V into the app the user
/// was in, so choosing a clip pastes it rather than merely copying it.
enum Paster {
    /// Synthesizing keystrokes requires Accessibility. Without it `CGEvent.post`
    /// silently does nothing — so check up front and say so clearly rather than
    /// leaving the user with a mysterious no-op.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestTrustIfNeeded() -> Bool {
        if isTrusted { return true }
        // The one system prompt we can't avoid: it deep-links to the
        // Accessibility pane. Not an in-app settings screen.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    static func write(_ item: ClipItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            guard let data = item.imageData else { return }
            pasteboard.setData(data, forType: .png)
            // Some apps only accept TIFF from the pasteboard; offer both.
            if let tiff = NSImage(data: data)?.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }

    /// Writes the clip, waits for `target` to actually be frontmost, then pastes.
    static func paste(_ item: ClipItem, into target: NSRunningApplication?) {
        write(item)

        guard requestTrustIfNeeded() else {
            log("paste skipped: Accessibility not granted — clip is on the clipboard, press Cmd+V yourself")
            return
        }

        // Poll rather than guess a fixed sleep: activation is asynchronous, and
        // pasting before the target is frontmost sends Cmd+V into the void.
        waitUntilActive(target) {
            sendCommandV()
            log("pasted into \(target?.localizedName ?? "frontmost app")")
        }
    }

    private static func waitUntilActive(
        _ app: NSRunningApplication?,
        attempts: Int = 20,
        then action: @escaping () -> Void
    ) {
        guard let app, !app.isActive, attempts > 0 else {
            // Even once active, give the app a beat to install its key handling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: action)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            waitUntilActive(app, attempts: attempts - 1, then: action)
        }
    }

    private static func sendCommandV() {
        // .privateState so the user's physically-held modifiers can't leak in and
        // turn our Cmd+V into Cmd+Shift+V.
        guard let source = CGEventSource(stateID: .privateState) else { return }
        let vKey = CGKeyCode(kVK_ANSI_V)

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return }

        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}
