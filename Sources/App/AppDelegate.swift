import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum DefaultsKey {
        static let hasCompletedFirstLaunch = "hasCompletedFirstLaunch"
    }

    private let totpGenerator: TOTPGenerator
    private let vpnController: VPNController
    private let loginItemController: LoginItemController
    private let notificationPresenter: NotificationPresenter
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var previousStatus: VPNStatus = .unknown
    private var isAutoReconnectExpected = false

    override init() {
        let generator = TOTPGenerator()
        let automation = GlobalProtectAutomation()
        let statusMonitor = GPStatusMonitor()

        self.totpGenerator = generator
        self.vpnController = VPNController(
            credentialsStore: KeychainStore(),
            totpGenerator: generator,
            automation: automation,
            statusMonitor: statusMonitor
        )
        self.loginItemController = LoginItemController()
        self.notificationPresenter = NotificationPresenter()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureMainMenu()
        createStatusItem()
        settingsWindowController = SettingsWindowController(
            vpnController: vpnController,
            totpGenerator: totpGenerator,
            loginItemController: loginItemController
        )

        observeWake()
        observeStatus()
        vpnController.start()

        notificationPresenter.requestAuthorizationIfNeeded()
        presentSettingsIfNeeded()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let toggleTitle = vpnController.status.isConnected ? "Disconnect" : "Connect"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleFromDock), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(showSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)

        let applicationMenu = NSMenu()
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit OneTapVPN",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        applicationMenuItem.submenu = applicationMenu
        NSApp.mainMenu = mainMenu
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func toggleFromDock() {
        vpnController.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        vpnController.stop()
        cancellables.removeAll()
    }

    private func createStatusItem() {
        let statusItemController = StatusItemController(
            controller: vpnController,
            onOpenSettings: { [weak self] in
                self?.showSettings()
            }
        )
        self.statusItemController = statusItemController
    }

    private func observeWake() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.vpnController.handleWake()
                }
            }
            .store(in: &cancellables)
    }

    private func observeStatus() {
        vpnController.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    guard let self else {
                        return
                    }
                    self.handleStatusChange(status)
                }
            }
            .store(in: &cancellables)
    }

    private func handleStatusChange(_ status: VPNStatus) {
        let previousStatus = self.previousStatus
        self.previousStatus = status

        switch status {
        case .disconnected:
            if previousStatus.isConnected, vpnController.autoReconnect {
                isAutoReconnectExpected = true
            }
        case .connected:
            if isAutoReconnectExpected, vpnController.autoReconnect {
                notificationPresenter.notifyAutoReconnectSucceeded()
            }
            isAutoReconnectExpected = false
        case .disconnecting:
            isAutoReconnectExpected = false
        case .failed:
            if case .failed = previousStatus {
                return
            }
            isAutoReconnectExpected = false
            notificationPresenter.notifyConnectionFailed()
        case .unknown, .connecting:
            break
        }
    }

    private func presentSettingsIfNeeded() {
        let defaults = UserDefaults.standard
        let hasCompletedFirstLaunch = defaults.bool(forKey: DefaultsKey.hasCompletedFirstLaunch)
        defaults.set(true, forKey: DefaultsKey.hasCompletedFirstLaunch)

        let shouldPresentSettings = !hasCompletedFirstLaunch
            || !AccessibilityPermission.isTrusted

        guard shouldPresentSettings else {
            return
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            self.showSettings()
        }
    }

    private func showSettings() {
        AppLogger.info("Showing settings window")
        settingsWindowController?.present()
    }
}
