import AppKit

MainActor.assumeIsolated {
    if Export.runIfRequested() { exit(0) }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // An "accessory" app has no Dock icon and can float over full-screen apps.
    app.setActivationPolicy(.accessory)
    app.run()
}
