import Combine
import Foundation

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: VPNStatus
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy: Bool
    @Published var autoReconnect: Bool {
        didSet {
            settings.autoReconnect = autoReconnect
        }
    }
    @Published var connectAtLogin: Bool {
        didSet {
            settings.connectAtLogin = connectAtLogin
        }
    }

    private let credentialsStore: CredentialsStoring
    private let totpGenerator: TOTPGenerating
    private let automation: GlobalProtectControlling
    private let statusMonitor: StatusMonitoring
    private var settings = AppSettings()
    private var reconnectWorkItem: DispatchWorkItem?
    private var reconnectAttempts = 0
    private var isUserInitiatedDisconnect = false

    init(
        credentialsStore: CredentialsStoring,
        totpGenerator: TOTPGenerating,
        automation: GlobalProtectControlling,
        statusMonitor: StatusMonitoring
    ) {
        self.credentialsStore = credentialsStore
        self.totpGenerator = totpGenerator
        self.automation = automation
        self.statusMonitor = statusMonitor
        self.status = statusMonitor.currentStatus
        self.lastError = nil
        self.isBusy = false
        self.autoReconnect = settings.autoReconnect
        self.connectAtLogin = settings.connectAtLogin
    }

    var hasCredentials: Bool {
        do {
            return try credentialsStore.loadCredentials()?.isConfigured ?? false
        } catch {
            return false
        }
    }

    func start() {
        statusMonitor.onStatusChange = { [weak self] newStatus in
            self?.apply(newStatus)
        }
        statusMonitor.start()
        refreshStatus()
        if connectAtLogin, status != .connected {
            connect()
        }
    }

    func stop() {
        statusMonitor.stop()
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
    }

    func connect() {
        connect(isAutomatic: false)
    }

    private func connect(isAutomatic: Bool) {
        guard !isBusy else {
            return
        }
        guard let credentials = loadCredentials(), credentials.isConfigured else {
            lastError = "Open Settings and save your credentials first."
            status = .failed(lastError ?? "Credentials are missing.")
            return
        }

        if !isAutomatic {
            reconnectAttempts = 0
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isBusy = true
        lastError = nil
        isUserInitiatedDisconnect = false
        status = .connecting

        Task { @MainActor in
            do {
                let otpCode = try totpGenerator.generateCode(
                    secret: credentials.totpSecret,
                    digits: credentials.otpDigits,
                    period: credentials.otpPeriod,
                    algorithm: credentials.otpAlgorithm,
                    date: Date()
                )
                try await automation.connect(credentials: credentials, otpCode: otpCode)
                isBusy = false
                reconnectAttempts = 0
                status = .connected
            } catch {
                isBusy = false
                status = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func disconnect() {
        guard !isBusy else {
            return
        }

        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        isUserInitiatedDisconnect = true
        isBusy = true
        lastError = nil
        status = .disconnecting

        Task { @MainActor in
            do {
                try await automation.disconnect()
                isBusy = false
                status = .disconnected
            } catch {
                isBusy = false
                status = .failed(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func toggle() {
        if status.isConnected {
            disconnect()
        } else {
            connect()
        }
    }

    func testConnection() {
        connect()
    }

    func refreshStatus() {
        statusMonitor.refresh()
        let monitoredStatus = statusMonitor.currentStatus
        if monitoredStatus != .unknown {
            status = monitoredStatus
        }
    }

    func handleWake() {
        refreshStatus()
        if autoReconnect, !isUserInitiatedDisconnect, status == .disconnected, loadCredentials() != nil {
            connect(isAutomatic: true)
        }
    }

    func loadCredentials() -> Credentials? {
        do {
            return try credentialsStore.loadCredentials()
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func saveCredentials(_ credentials: Credentials) throws {
        try credentialsStore.saveCredentials(credentials)
        lastError = nil
    }

    func deleteCredentials() throws {
        try credentialsStore.deleteCredentials()
        lastError = nil
    }

    private func apply(_ newStatus: VPNStatus) {
        if isBusy {
            if case .failed(let message) = newStatus {
                lastError = message
            }
            return
        }

        let previousStatus = status
        status = newStatus

        switch newStatus {
        case .connected:
            reconnectWorkItem?.cancel()
            reconnectWorkItem = nil
            reconnectAttempts = 0
            lastError = nil
        case .failed(let message):
            lastError = message
        case .disconnected:
            if previousStatus.isConnected, autoReconnect, !isUserInitiatedDisconnect {
                scheduleAutoReconnect()
            }
        default:
            break
        }
    }

    private func scheduleAutoReconnect() {
        guard reconnectAttempts < 3, !isBusy, loadCredentials() != nil else {
            return
        }

        let delaySeconds = [5, 15, 30][min(reconnectAttempts, 2)]
        reconnectAttempts += 1
        reconnectWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.connect(isAutomatic: true)
            }
        }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delaySeconds), execute: workItem)
    }
}
