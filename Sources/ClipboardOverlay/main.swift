import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory: no dock icon, no menu bar. Info.plist sets LSUIElement too; this
// covers the case of running the binary directly, outside the bundle.
app.setActivationPolicy(.accessory)
app.run()
