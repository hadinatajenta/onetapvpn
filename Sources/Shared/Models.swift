import Foundation

enum OTPPlacement: String, Codable, CaseIterable, Sendable {
    case append
    case prepend
}

struct Credentials: Codable, Equatable, Sendable {
    var portal: String
    var username: String
    var password: String
    var totpSecret: String
    var otpPlacement: OTPPlacement
    var otpSeparator: String
    var otpDigits: Int
    var otpPeriod: Int
    var otpAlgorithm: String

    static let defaultPortal = "vpn.bri.co.id"

    static var empty: Credentials {
        Credentials(
            portal: defaultPortal,
            username: "",
            password: "",
            totpSecret: "",
            otpPlacement: .append,
            otpSeparator: "",
            otpDigits: 6,
            otpPeriod: 30,
            otpAlgorithm: "SHA1"
        )
    }

    var isConfigured: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty &&
        !totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func passwordWithOTP(_ otpCode: String) -> String {
        switch otpPlacement {
        case .append:
            return password + otpSeparator + otpCode
        case .prepend:
            return otpCode + otpSeparator + password
        }
    }
}

enum VPNStatus: Equatable, Sendable {
    case unknown
    case disconnected
    case connecting
    case connected
    case disconnecting
    case failed(String)

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .connecting, .disconnecting:
            return true
        default:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .unknown:
            return "Checking status"
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting"
        case .failed(let message):
            return "Error: \(message)"
        }
    }
}

enum TOTPError: LocalizedError {
    case invalidSecret
    case unsupportedAlgorithm(String)
    case invalidDigits
    case invalidPeriod
    case invalidURI

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "The TOTP secret is not valid base32 or an otpauth URI."
        case .unsupportedAlgorithm(let algorithm):
            return "The TOTP algorithm \(algorithm) is not supported."
        case .invalidDigits:
            return "TOTP digits must be between 6 and 8."
        case .invalidPeriod:
            return "TOTP period must be between 15 and 120 seconds."
        case .invalidURI:
            return "The otpauth URI is not valid."
        }
    }
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain returned status \(status)."
        case .invalidData:
            return "The stored credential data could not be read."
        }
    }
}

enum GlobalProtectError: LocalizedError {
    case applicationNotRunning
    case accessibilityPermissionDenied
    case statusPanelNotFound
    case connectButtonNotFound
    case loginWindowNotFound
    case loginFieldsNotFound
    case signInButtonNotFound
    case authenticationFailed(String)
    case timeout(String)
    case unsupportedUI

    var errorDescription: String? {
        switch self {
        case .applicationNotRunning:
            return "GlobalProtect is not running."
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to control GlobalProtect."
        case .statusPanelNotFound:
            return "The GlobalProtect status panel could not be found."
        case .connectButtonNotFound:
            return "The GlobalProtect Connect button could not be found."
        case .loginWindowNotFound:
            return "The GlobalProtect login window did not appear."
        case .loginFieldsNotFound:
            return "The GlobalProtect username or password field could not be found."
        case .signInButtonNotFound:
            return "The GlobalProtect Sign In button could not be found."
        case .authenticationFailed(let message):
            return message.isEmpty ? "GlobalProtect authentication failed." : message
        case .timeout(let step):
            return "Timed out while waiting for GlobalProtect to \(step)."
        case .unsupportedUI:
            return "This GlobalProtect interface is not supported. Open the diagnostic report."
        }
    }
}
