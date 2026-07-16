import AppKit
import Carbon.HIToolbox
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // CLIPBOARD_OVERLAY_STORE lets tests use a throwaway history file instead of
    // scribbling on the real one.
    private let history = ClipboardHistory(
        storeURL: ProcessInfo.processInfo.environment["CLIPBOARD_OVERLAY_STORE"].map(URL.init(fileURLWithPath:))
    )
    private let watcher = ClipboardWatcher()
    private lazy var overlay = OverlayController(history: history)
    private var hotKey: GlobalHotKey?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setvbuf(stdout, nil, _IONBF, 0)

        watcher.onNewClip = { [weak self] item in
            self?.history.add(item)
        }
        watcher.start()

        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey))
        if hotKey == nil {
            log("ERROR: could not register Cmd+Shift+V — another app already owns it")
        }
        hotKey?.onFire = { [weak self] in
            self?.overlay.toggle()
        }

        overlay.onSelect = { item, target in
            Paster.paste(item, into: target)
        }

        installQuitHandlers()
        log("ready — Cmd+Shift+V to summon (accessibility trusted: \(Paster.isTrusted))")

        #if DEBUG
            installDebugHooks()
        #endif
    }

    /// AppKit doesn't run applicationWillTerminate for a plain SIGTERM, so a
    /// `kill` (or a logout) would drop unsaved history without this.
    private func installQuitHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.history.flush()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The throttled save would otherwise be dropped on quit.
        history.flush()
    }

    #if DEBUG
        /// SIGUSR1 toggles the overlay, so it can be driven headlessly in tests
        /// without granting Accessibility to a synthetic-keystroke driver.
        private func installDebugHooks() {
            signal(SIGUSR1, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            source.setEventHandler { [weak self] in
                guard let self else { return }
                self.overlay.toggle()
                log("SIGUSR1 -> overlay visible=\(self.overlay.isVisible), previousApp=\(self.overlay.previousApp?.localizedName ?? "none")")
            }
            source.resume()
            signalSources.append(source)

            if ProcessInfo.processInfo.environment["CLIPBOARD_OVERLAY_SELFTEST"] == "1" {
                DebugSelfTest.run(overlay: overlay, history: history, watcher: watcher)
            }
        }
    #endif
}

/// Prints to stdout, and also appends to $CLIPBOARD_OVERLAY_LOG when set — the
/// app is normally launched by LaunchServices, where stdout goes nowhere.
func log(_ message: String) {
    let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(stamp)] \(message)"
    print(line)

    guard let path = ProcessInfo.processInfo.environment["CLIPBOARD_OVERLAY_LOG"] else { return }
    guard let data = (line + "\n").data(using: .utf8) else { return }
    if let handle = FileHandle(forWritingAtPath: path) {
        handle.seekToEndOfFile()
        handle.write(data)
        try? handle.close()
    } else {
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
