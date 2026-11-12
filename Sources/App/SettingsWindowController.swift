import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var hasBeenPresented = false
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    init(
        vpnController: VPNController,
        totpGenerator: TOTPGenerating,
        loginItemController: LoginItemController
    ) {
        let settingsView = SettingsView(
            vpnController: vpnController,
            totpGenerator: totpGenerator,
            loginItemController: loginItemController
        )
        let hostingView = NSHostingView(rootView: settingsView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "OneTapVPN Settings"
        window.contentView = hostingView
        window.minSize = NSSize(width: 480, height: 520)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .participatesInCycle]
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func present() {
        guard let window else {
            return
        }

        if !hasBeenPresented {
            window.center()
            hasBeenPresented = true
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        if previousActivationPolicy == nil {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppLogger.info("Settings window presented activeSpace=\(window.isOnActiveSpace) visible=\(window.isVisible)")
    }

    func windowWillClose(_ notification: Notification) {
        guard let previousActivationPolicy else {
            return
        }
        NSApp.setActivationPolicy(previousActivationPolicy)
        self.previousActivationPolicy = nil
    }
}
