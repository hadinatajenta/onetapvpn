import CryptoKit
import Foundation

struct TOTPGenerator: TOTPGenerating {
    private enum Algorithm {
        case sha1
        case sha256
        case sha512
    }

    private struct Configuration {
        var secret: String
        var digits: Int
        var period: Int
        var algorithm: Algorithm
    }

    func generateCode(secret: String, digits: Int, period: Int, algorithm: String, date: Date) throws -> String {
        let configuration = try resolvedConfiguration(
            secret: secret,
            digits: digits,
            period: period,
            algorithm: algorithm
        )
        let key = try Base32.decode(configuration.secret)
        let timeStep = floor(date.timeIntervalSince1970 / Double(configuration.period))
        let counter = timeStep > 0 ? UInt64(timeStep) : 0
        let hash = authenticationCode(
            key: key,
            message: counterMessage(counter),
            algorithm: configuration.algorithm
        )
        let code = dynamicTruncation(hash: hash, digits: configuration.digits)
        return formattedCode(code, digits: configuration.digits)
    }

    func secondsRemaining(secret: String, digits: Int, period: Int, algorithm: String, date: Date) -> Int {
        let resolvedPeriod = periodForCountdown(secret: secret, fallbackPeriod: period)
        guard (15...120).contains(resolvedPeriod) else {
            return 1
        }
        let remainder = date.timeIntervalSince1970.truncatingRemainder(dividingBy: Double(resolvedPeriod))
        let elapsedSeconds = Int(floor(remainder))
        let normalizedElapsed = ((elapsedSeconds % resolvedPeriod) + resolvedPeriod) % resolvedPeriod
        return resolvedPeriod - normalizedElapsed
    }

    private func resolvedConfiguration(
        secret: String,
        digits: Int,
        period: Int,
        algorithm: String
    ) throws -> Configuration {
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSecret.lowercased().hasPrefix("otpauth://") {
            return try parseURI(
                trimmedSecret,
                defaultDigits: digits,
                defaultPeriod: period,
                defaultAlgorithm: algorithm
            )
        }

        try validateDigits(digits)
        try validatePeriod(period)
        return Configuration(
            secret: trimmedSecret,
            digits: digits,
            period: period,
            algorithm: try parseAlgorithm(algorithm)
        )
    }

    private func parseURI(
        _ uri: String,
        defaultDigits: Int,
        defaultPeriod: Int,
        defaultAlgorithm: String
    ) throws -> Configuration {
        guard let components = URLComponents(string: uri),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp" else {
            throw TOTPError.invalidURI
        }

        let queryItems = components.queryItems ?? []
        guard let secret = queryValue(named: "secret", in: queryItems)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !secret.isEmpty else {
            throw TOTPError.invalidURI
        }

        var digits = defaultDigits
        if let digitsValue = queryValue(named: "digits", in: queryItems) {
            guard let parsedDigits = Int(digitsValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TOTPError.invalidDigits
            }
            digits = parsedDigits
        }

        var period = defaultPeriod
        if let periodValue = queryValue(named: "period", in: queryItems) {
            guard let parsedPeriod = Int(periodValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw TOTPError.invalidPeriod
            }
            period = parsedPeriod
        }

        var algorithm = defaultAlgorithm
        if let algorithmValue = queryValue(named: "algorithm", in: queryItems) {
            algorithm = algorithmValue
        }

        try validateDigits(digits)
        try validatePeriod(period)
        return Configuration(
            secret: secret,
            digits: digits,
            period: period,
            algorithm: try parseAlgorithm(algorithm)
        )
    }

    private func periodForCountdown(secret: String, fallbackPeriod: Int) -> Int {
        let trimmedSecret = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSecret.lowercased().hasPrefix("otpauth://"),
              let components = URLComponents(string: trimmedSecret),
              components.scheme?.lowercased() == "otpauth",
              components.host?.lowercased() == "totp",
              let periodValue = queryValue(named: "period", in: components.queryItems ?? []),
              let parsedPeriod = Int(periodValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return fallbackPeriod
        }
        return parsedPeriod
    }

    private func queryValue(named name: String, in queryItems: [URLQueryItem]) -> String? {
        queryItems.first(where: { $0.name.lowercased() == name })?.value
    }

    private func validateDigits(_ digits: Int) throws {
        guard (6...8).contains(digits) else {
            throw TOTPError.invalidDigits
        }
    }

    private func validatePeriod(_ period: Int) throws {
        guard (15...120).contains(period) else {
            throw TOTPError.invalidPeriod
        }
    }

    private func parseAlgorithm(_ name: String) throws -> Algorithm {
        let normalizedName = name
            .filter { $0.isLetter || $0.isNumber }
            .uppercased()
        switch normalizedName {
        case "SHA1":
            return .sha1
        case "SHA256":
            return .sha256
        case "SHA512":
            return .sha512
        default:
            throw TOTPError.unsupportedAlgorithm(name)
        }
    }

    private func authenticationCode(key: Data, message: Data, algorithm: Algorithm) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        switch algorithm {
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: symmetricKey))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: message, using: symmetricKey))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: message, using: symmetricKey))
        }
    }

    private func counterMessage(_ counter: UInt64) -> Data {
        let bigEndianCounter = counter.bigEndian
        return withUnsafeBytes(of: bigEndianCounter) { Data($0) }
    }

    private func dynamicTruncation(hash: Data, digits: Int) -> UInt32 {
        let bytes = [UInt8](hash)
        let offset = Int(bytes[bytes.count - 1] & 0x0F)
        let truncated = (UInt32(bytes[offset] & 0x7F) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        return truncated % decimalModulus(for: digits)
    }

    private func decimalModulus(for digits: Int) -> UInt32 {
        var modulus: UInt32 = 1
        for _ in 0..<digits {
            modulus *= 10
        }
        return modulus
    }

    private func formattedCode(_ code: UInt32, digits: Int) -> String {
        let codeText = String(code)
        let paddingCount = digits - codeText.count
        guard paddingCount > 0 else {
            return codeText
        }
        return String(repeating: "0", count: paddingCount) + codeText
    }
}
