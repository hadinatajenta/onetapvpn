import Foundation

protocol CredentialsStoring: AnyObject {
    func loadCredentials() throws -> Credentials?
    func saveCredentials(_ credentials: Credentials) throws
    func deleteCredentials() throws
}

protocol TOTPGenerating {
    func generateCode(secret: String, digits: Int, period: Int, algorithm: String, date: Date) throws -> String
    func secondsRemaining(secret: String, digits: Int, period: Int, algorithm: String, date: Date) -> Int
    func parseProvisioningURI(
        _ uri: String,
        defaultDigits: Int,
        defaultPeriod: Int,
        defaultAlgorithm: String
    ) throws -> TOTPProvisioning
}

@MainActor
protocol GlobalProtectControlling: AnyObject {
    var isGlobalProtectRunning: Bool { get }
    func launchGlobalProtect() throws
    func connect(credentials: Credentials, otpCode: String) async throws
    func disconnect() async throws
    func dumpAccessibilityTree() throws -> URL
}

@MainActor
protocol StatusMonitoring: AnyObject {
    var onStatusChange: ((VPNStatus) -> Void)? { get set }
    var currentStatus: VPNStatus { get }
    func start()
    func stop()
    func refresh()
}
