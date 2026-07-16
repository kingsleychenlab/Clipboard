#if DEBUG

import AppKit
import Carbon.HIToolbox

/// Drives the overlay with real in-process key events so keyboard behaviour can
/// be verified without granting Accessibility to a test driver.
/// Debug builds only, and only when CLIPBOARD_SELFTEST=1:
///     swift build && CLIPBOARD_SELFTEST=1 .build/debug/Clipboard
enum DebugSelfTest {
    private static var failures = 0
    private static var selected: [String] = []

    static func run(overlay: OverlayController, history: ClipboardHistory, watcher: ClipboardWatcher) {
        log("=== SELF TEST ===")
        log("   accessibility trusted: \(Paster.isTrusted)")

        // Stop polling: the test writes to the pasteboard, and the watcher would
        // capture those writes back into the history mid-run and skew the counts.
        watcher.stop()

        // The test writes to the real pasteboard; put the user's clip back after.
        let savedClipboard = NSPasteboard.general.string(forType: .string)

        history.add(ClipItem(text: "alpha one"))
        history.add(ClipItem(text: "beta two"))
        history.add(ClipItem(text: "gamma three"))  // newest

        overlay.onSelect = { item, target in
            selected.append(item.preview)
            // write() only — synthesizing Cmd+V needs Accessibility and a real
            // target app, so that half is verified interactively.
            Paster.write(item)
            log("  onSelect fired: \(item.preview) -> \(target?.localizedName ?? "none")")
        }

        var steps: [(String, () -> Void)] = []

        steps.append(("show overlay", {
            check("history starts clean (use a fresh CLIPBOARD_STORE)",
                  history.items.count == 3, "\(history.items.count) — stale store?")
            overlay.show()
        }))
        steps.append(("firstResponder is the text field", {
            let responder = overlay.debugPanel?.firstResponder
            let name = String(describing: type(of: responder))
            // The field editor (an NSTextView) becoming first responder is what
            // proves the query field is focused and will receive typing.
            check("query field focused (firstResponder=\(name))", responder is NSTextView)
            check("3 results shown", overlay.debugModel.results.count == 3, "\(overlay.debugModel.results.count)")
            check("selection starts at top", overlay.debugModel.selectedIndex == 0)
        }))

        steps.append(("type 'a'", { typeCharacter("a", overlay: overlay) }))
        steps.append(("typing reached the field", {
            check("query == 'a'", overlay.debugModel.query == "a", "query='\(overlay.debugModel.query)'")
            check("filter applied (alpha/gamma/beta all contain 'a')",
                  overlay.debugModel.results.count == 3, "\(overlay.debugModel.results.count)")
        }))

        steps.append(("type 'lp' -> 'alp'", {
            typeCharacter("l", overlay: overlay)
            typeCharacter("p", overlay: overlay)
        }))
        steps.append(("live filtering narrows", {
            check("query == 'alp'", overlay.debugModel.query == "alp", "query='\(overlay.debugModel.query)'")
            check("only 'alpha one' matches", overlay.debugModel.results.count == 1, "\(overlay.debugModel.results.count)")
            check("match is alpha one", overlay.debugModel.results.first?.preview == "alpha one")
        }))

        steps.append(("clear query", { overlay.debugModel.query = "" }))
        steps.append(("arrow down x2", {
            sendKey(kVK_DownArrow, overlay: overlay)
            sendKey(kVK_DownArrow, overlay: overlay)
        }))
        steps.append(("selection moved down", {
            check("selectedIndex == 2", overlay.debugModel.selectedIndex == 2, "\(overlay.debugModel.selectedIndex)")
        }))

        steps.append(("arrow up", { sendKey(kVK_UpArrow, overlay: overlay) }))
        steps.append(("selection moved up", {
            check("selectedIndex == 1", overlay.debugModel.selectedIndex == 1, "\(overlay.debugModel.selectedIndex)")
        }))

        steps.append(("arrow up x5 (past the top)", {
            for _ in 0..<5 { sendKey(kVK_UpArrow, overlay: overlay) }
        }))
        steps.append(("clamps at top, no wraparound", {
            check("selectedIndex == 0", overlay.debugModel.selectedIndex == 0, "\(overlay.debugModel.selectedIndex)")
        }))

        steps.append(("arrow down x9 (past the end)", {
            for _ in 0..<9 { sendKey(kVK_DownArrow, overlay: overlay) }
        }))
        steps.append(("clamps at bottom", {
            check("selectedIndex == 2", overlay.debugModel.selectedIndex == 2, "\(overlay.debugModel.selectedIndex)")
        }))

        steps.append(("arrow up, then Enter", {
            sendKey(kVK_UpArrow, overlay: overlay)
            sendKey(kVK_Return, overlay: overlay)
        }))
        steps.append(("Enter selects and dismisses", {
            check("onSelect fired once", selected.count == 1, "\(selected.count)")
            check("selected the highlighted row", selected.first == "beta two", selected.first ?? "nil")
            check("overlay hidden after Enter", !overlay.isVisible)
            let onBoard = NSPasteboard.general.string(forType: .string)
            check("selected clip landed on the pasteboard", onBoard == "beta two", onBoard ?? "nil")
        }))

        steps.append(("write an image clip", {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
            Paster.write(ClipItem(imageData: png))
        }))
        steps.append(("image clip offers both PNG and TIFF", {
            let types = Set((NSPasteboard.general.types ?? []).map(\.rawValue))
            check("PNG on pasteboard", types.contains(NSPasteboard.PasteboardType.png.rawValue), "\(types)")
            check("TIFF on pasteboard (for apps that only take TIFF)",
                  types.contains(NSPasteboard.PasteboardType.tiff.rawValue))
        }))

        // --- deletion -------------------------------------------------------

        steps.append(("re-show for delete tests", {
            overlay.show()
            check("3 clips before deleting", overlay.debugModel.results.count == 3, "\(overlay.debugModel.results.count)")
        }))

        steps.append(("plain Delete (no Cmd) while typing", {
            typeCharacter("a", overlay: overlay)
            sendKey(kVK_Delete, overlay: overlay)
        }))
        steps.append(("plain Delete edits the query, never deletes a clip", {
            check("no clip was deleted", overlay.debugModel.results.count == 3, "\(overlay.debugModel.results.count)")
            check("query was edited instead", overlay.debugModel.query == "", "query='\(overlay.debugModel.query)'")
        }))

        steps.append(("select middle row, Cmd+Delete", {
            sendKey(kVK_DownArrow, overlay: overlay)  // index 1 = "beta two"
            sendKey(kVK_Delete, flags: .command, overlay: overlay)
        }))
        steps.append(("Cmd+Delete removes the selected clip", {
            check("2 clips remain", overlay.debugModel.results.count == 2, "\(overlay.debugModel.results.count)")
            check("the right one went", !overlay.debugModel.results.contains { $0.preview == "beta two" },
                  overlay.debugModel.results.map(\.preview).joined(separator: ", "))
            // The whole point of not resetting selection on item changes: the
            // next row slides under the cursor so you can delete a run of clips.
            check("selection stays in place", overlay.debugModel.selectedIndex == 1, "\(overlay.debugModel.selectedIndex)")
            check("selection now points at the next clip", overlay.debugModel.selectedItem?.preview == "alpha one",
                  overlay.debugModel.selectedItem?.preview ?? "nil")
        }))

        steps.append(("Cmd+Delete again (repeat delete)", {
            sendKey(kVK_Delete, flags: .command, overlay: overlay)
        }))
        steps.append(("repeat delete clamps at the end", {
            check("1 clip remains", overlay.debugModel.results.count == 1, "\(overlay.debugModel.results.count)")
            check("selection clamped to last row", overlay.debugModel.selectedIndex == 0, "\(overlay.debugModel.selectedIndex)")
            check("survivor is gamma three", overlay.debugModel.selectedItem?.preview == "gamma three",
                  overlay.debugModel.selectedItem?.preview ?? "nil")
        }))

        steps.append(("delete the last one", {
            sendKey(kVK_Delete, flags: .command, overlay: overlay)
        }))
        steps.append(("empty list is handled", {
            check("history empty", overlay.debugModel.results.isEmpty, "\(overlay.debugModel.results.count)")
            check("no selected item", overlay.debugModel.selectedItem == nil)
            sendKey(kVK_Delete, flags: .command, overlay: overlay)  // must not crash
            check("Cmd+Delete on empty list is a no-op", overlay.debugModel.results.isEmpty)
            sendKey(kVK_Return, overlay: overlay)  // must not crash or select
            check("Enter on empty list selects nothing", selected.count == 1, "\(selected.count)")
        }))

        steps.append(("deletion persisted to the store", {
            history.flush()
            check("store reflects the deletions", history.items.isEmpty, "\(history.items.count) left")
        }))

        steps.append(("re-show, then Escape", {
            overlay.show()
            check("query reset on re-show", overlay.debugModel.query == "")
            check("selection reset on re-show", overlay.debugModel.selectedIndex == 0)
            sendKey(kVK_Escape, overlay: overlay)
        }))
        steps.append(("Escape dismisses without selecting", {
            check("overlay hidden after Escape", !overlay.isVisible)
            check("no extra selection fired", selected.count == 1, "\(selected.count)")
        }))

        // Each step gets its own runloop turn so posted events are actually
        // dispatched and SwiftUI has applied its state updates before we assert.
        var delay = 0.4
        for (label, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                log("-- \(label)")
                action()
            }
            delay += 0.35
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.3) {
            if let savedClipboard {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(savedClipboard, forType: .string)
                log("   (restored your clipboard)")
            }
            log(failures == 0 ? "=== SELF TEST: ALL PASSED ===" : "=== SELF TEST: \(failures) FAILURE(S) ===")
            NSApp.terminate(nil)
        }
    }

    private static func check(_ label: String, _ condition: Bool, _ detail: String = "") {
        log("   \(condition ? "PASS" : "FAIL")  \(label)\(detail.isEmpty ? "" : " → \(detail)")")
        if !condition { failures += 1 }
    }

    private static func sendKey(
        _ keyCode: Int,
        characters: String = "",
        flags: NSEvent.ModifierFlags = [],
        overlay: OverlayController
    ) {
        guard let window = overlay.debugPanel,
              let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: UInt16(keyCode)
              )
        else { return }
        // sendEvent, not postEvent: synchronous, so the assertion in the next
        // step sees the result rather than racing the event queue.
        NSApp.sendEvent(event)
    }

    private static func typeCharacter(_ character: String, overlay: OverlayController) {
        sendKey(keyCodeFor(character), characters: character, overlay: overlay)
    }

    private static func keyCodeFor(_ character: String) -> Int {
        switch character {
        case "a": return kVK_ANSI_A
        case "l": return kVK_ANSI_L
        case "p": return kVK_ANSI_P
        default: return kVK_ANSI_A
        }
    }
}

#endif
