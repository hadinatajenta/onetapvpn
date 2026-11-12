import AppKit
import ApplicationServices

if CommandLine.arguments.contains("--check-accessibility") {
    print(AXIsProcessTrusted() ? "trusted" : "not-trusted")
    exit(0)
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
}
