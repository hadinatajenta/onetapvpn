import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let controller: VPNController
    private let onOpenSettings: () -> Void
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    init(controller: VPNController, onOpenSettings: @escaping () -> Void) {
        self.controller = controller
        self.onOpenSettings = onOpenSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        configureButton()
        observeStatus()
        apply(controller.status)
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(handleClick(_:))
        _ = button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
    }

    private func observeStatus() {
        controller.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.apply(status)
                }
            }
            .store(in: &cancellables)
    }

    private func apply(_ status: VPNStatus) {
        let symbolName: String
        let description: String
        let actionDescription: String

        switch status {
        case .connected:
            symbolName = "shield.fill"
            description = "OneTapVPN connected"
            actionDescription = "disconnect"
        case .connecting:
            symbolName = "arrow.triangle.2.circlepath"
            description = "OneTapVPN connecting"
            actionDescription = "wait for the connection to finish"
        case .disconnecting:
            symbolName = "arrow.triangle.2.circlepath"
            description = "OneTapVPN disconnecting"
            actionDescription = "wait for the connection to finish"
        case .failed:
            symbolName = "exclamationmark.shield.fill"
            description = "OneTapVPN connection error"
            actionDescription = "open Settings"
        case .unknown, .disconnected:
            symbolName = "shield"
            description = "OneTapVPN disconnected"
            actionDescription = "connect"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "shield", accessibilityDescription: description)
        image?.isTemplate = true

        guard let button = statusItem.button else {
            return
        }
        button.image = image
        button.toolTip = "\(description). Click to \(actionDescription)."
        button.setAccessibilityLabel(description)
        button.setAccessibilityHelp("Click to \(actionDescription).")
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            controller.toggle()
            return
        }

        let isSecondaryClick = event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control))

        if isSecondaryClick {
            presentMenu()
        } else if !controller.hasCredentials || !AccessibilityPermission.isTrusted {
            onOpenSettings()
        } else if case .failed = controller.status {
            onOpenSettings()
        } else {
            controller.toggle()
        }
    }

    private func presentMenu() {
        rebuildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let statusTextItem = NSMenuItem(title: controller.status.displayText, action: nil, keyEquivalent: "")
        statusTextItem.isEnabled = false
        menu.addItem(statusTextItem)
        menu.addItem(.separator())

        let connectionTitle = controller.status.isConnected ? "Disconnect" : "Connect"
        let connectionItem = NSMenuItem(
            title: connectionTitle,
            action: #selector(toggleConnection),
            keyEquivalent: ""
        )
        connectionItem.target = self
        connectionItem.isEnabled = !controller.isBusy
        menu.addItem(connectionItem)

        let reconnectItem = NSMenuItem(
            title: "Reconnect automatically",
            action: #selector(toggleAutoReconnect),
            keyEquivalent: ""
        )
        reconnectItem.target = self
        reconnectItem.state = controller.autoReconnect ? .on : .off
        menu.addItem(reconnectItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit OneTapVPN",
            action: #selector(quitApplication),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func toggleConnection() {
        controller.toggle()
    }

    @objc private func toggleAutoReconnect() {
        controller.autoReconnect.toggle()
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quitApplication() {
        NSApp.terminate(nil)
    }
}
