import Foundation

var caseCount = 0
var failureCount = 0
let generator = TOTPGenerator()

func record(_ passed: Bool, _ name: String) {
    caseCount += 1
    if passed {
        print("PASS \(name)")
    } else {
        print("FAIL \(name)")
        failureCount += 1
    }
}

func checkCode(_ actual: String?, _ expected: String, _ name: String) {
    record(actual == expected, name)
}

func checkDecodedBase32(_ encoded: String, expected: Data, _ name: String) {
    do {
        record(try Base32.decode(encoded) == expected, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidBase32(_ encoded: String, _ name: String) {
    do {
        _ = try Base32.decode(encoded)
        record(false, name)
    } catch TOTPError.invalidSecret {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidSecret(_ secret: String, _ name: String) {
    do {
        _ = try generator.generateCode(
            secret: secret,
            digits: 6,
            period: 30,
            algorithm: "SHA1",
            date: Date(timeIntervalSince1970: 59)
        )
        record(false, name)
    } catch TOTPError.invalidSecret {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidURI(_ secret: String, _ name: String) {
    do {
        _ = try generator.generateCode(
            secret: secret,
            digits: 6,
            period: 30,
            algorithm: "SHA1",
            date: Date(timeIntervalSince1970: 59)
        )
        record(false, name)
    } catch TOTPError.invalidURI {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidProvisioningURI(_ uri: String, _ name: String) {
    do {
        _ = try generator.parseProvisioningURI(
            uri,
            defaultDigits: 6,
            defaultPeriod: 30,
            defaultAlgorithm: "SHA1"
        )
        record(false, name)
    } catch TOTPError.invalidURI {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidDigits(_ digits: Int, _ name: String) {
    do {
        _ = try generator.generateCode(
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            digits: digits,
            period: 30,
            algorithm: "SHA1",
            date: Date(timeIntervalSince1970: 59)
        )
        record(false, name)
    } catch TOTPError.invalidDigits {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkInvalidPeriod(_ period: Int, _ name: String) {
    do {
        _ = try generator.generateCode(
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            digits: 6,
            period: period,
            algorithm: "SHA1",
            date: Date(timeIntervalSince1970: 59)
        )
        record(false, name)
    } catch TOTPError.invalidPeriod {
        record(true, name)
    } catch {
        record(false, name)
    }
}

func checkUnsupportedAlgorithm(_ algorithm: String, _ name: String) {
    do {
        _ = try generator.generateCode(
            secret: "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
            digits: 6,
            period: 30,
            algorithm: algorithm,
            date: Date(timeIntervalSince1970: 59)
        )
        record(false, name)
    } catch TOTPError.unsupportedAlgorithm {
        record(true, name)
    } catch {
        record(false, name)
    }
}

let rfcSecret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
let rfcVectors: [(TimeInterval, String)] = [
    (59, "94287082"),
    (1111111109, "07081804"),
    (1111111111, "14050471"),
    (1234567890, "89005924"),
    (2000000000, "69279037"),
    (20000000000, "65353130")
]

checkDecodedBase32(
    rfcSecret,
    expected: Data("12345678901234567890".utf8),
    "Base32 decodes RFC 4648 vector"
)
checkDecodedBase32(
    "JBSWY3DPEHPK3PXP",
    expected: Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF]),
    "Base32 decodes Hello vector"
)
checkDecodedBase32(
    "jbswy3dp-ehpk3pxp",
    expected: Data("Hello!".utf8) + Data([0xDE, 0xAD, 0xBE, 0xEF]),
    "Base32 accepts lowercase and hyphens"
)
checkDecodedBase32(
    "MZXW6===",
    expected: Data("foo".utf8),
    "Base32 accepts padding"
)
checkInvalidBase32("JBSWY3DP!", "Base32 rejects invalid characters")
checkInvalidBase32("GEZDGNBVGY3TQOJQ1", "Base32 rejects invalid length")
checkInvalidBase32("", "Base32 rejects empty input")

for (timestamp, expected) in rfcVectors {
    let actual = try? generator.generateCode(
        secret: rfcSecret,
        digits: 8,
        period: 30,
        algorithm: "SHA1",
        date: Date(timeIntervalSince1970: timestamp)
    )
    checkCode(actual, expected, "RFC 6238 SHA1 at \(Int(timestamp))")
}

let sixDigitCode = try? generator.generateCode(
    secret: rfcSecret,
    digits: 6,
    period: 30,
    algorithm: "SHA1",
    date: Date(timeIntervalSince1970: 59)
)
checkCode(sixDigitCode, "287082", "RFC 6238 SHA1 six digits at 59")

let sha256Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA===="
let sha256Code = try? generator.generateCode(
    secret: sha256Secret,
    digits: 8,
    period: 30,
    algorithm: "SHA-256",
    date: Date(timeIntervalSince1970: 59)
)
checkCode(sha256Code, "46119246", "SHA256 code at 59")

let sha512Secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNA="
let sha512Code = try? generator.generateCode(
    secret: sha512Secret,
    digits: 8,
    period: 30,
    algorithm: "sha_512",
    date: Date(timeIntervalSince1970: 59)
)
checkCode(sha512Code, "90693936", "SHA512 code at 59")

let otpauthURI = "otpauth://totp/BRI:user?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8&period=30&algorithm=SHA1"
let uriCode = try? generator.generateCode(
    secret: otpauthURI,
    digits: 6,
    period: 60,
    algorithm: "SHA512",
    date: Date(timeIntervalSince1970: 59)
)
checkCode(uriCode, "94287082", "otpauth URI overrides digits period and algorithm")

let provisioning = try? generator.parseProvisioningURI(
    "otpauth://totp/Example:user?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&digits=8&period=60&algorithm=SHA256",
    defaultDigits: 6,
    defaultPeriod: 30,
    defaultAlgorithm: "SHA1"
)
record(
    provisioning?.secret == "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ",
    "Provisioning URI extracts secret"
)
record(provisioning?.digits == 8, "Provisioning URI extracts digits")
record(provisioning?.period == 60, "Provisioning URI extracts period")
record(provisioning?.algorithm == "SHA256", "Provisioning URI extracts algorithm")

let defaultProvisioning = try? generator.parseProvisioningURI(
    "otpauth://totp/Example:user?secret=JBSWY3DPEHPK3PXP",
    defaultDigits: 7,
    defaultPeriod: 60,
    defaultAlgorithm: "SHA512"
)
record(defaultProvisioning?.digits == 7, "Provisioning URI applies default digits")
record(defaultProvisioning?.period == 60, "Provisioning URI applies default period")
record(defaultProvisioning?.algorithm == "SHA512", "Provisioning URI applies default algorithm")

checkInvalidProvisioningURI("https://example.com/otpauth", "Provisioning parser rejects non-otpauth URI")
checkInvalidProvisioningURI(
    "otpauth://hotp/Example:user?secret=JBSWY3DPEHPK3PXP",
    "Provisioning parser rejects non-TOTP URI"
)

checkInvalidSecret("JBSWY3DP!", "Invalid raw secret throws invalidSecret")
checkInvalidURI("otpauth://hotp/BRI:user?secret=JBSWY3DPEHPK3PXP", "Non-TOTP URI throws invalidURI")
checkInvalidDigits(5, "Digits below range throw invalidDigits")
checkInvalidDigits(9, "Digits above range throw invalidDigits")
checkInvalidPeriod(14, "Period below range throw invalidPeriod")
checkInvalidPeriod(121, "Period above range throw invalidPeriod")
checkUnsupportedAlgorithm("MD5", "Unsupported algorithm throws unsupportedAlgorithm")

let remainingAt59 = generator.secondsRemaining(
    secret: rfcSecret,
    digits: 6,
    period: 30,
    algorithm: "SHA1",
    date: Date(timeIntervalSince1970: 59)
)
record(remainingAt59 == 1, "secondsRemaining at 59 is 1")

let remainingAt60 = generator.secondsRemaining(
    secret: rfcSecret,
    digits: 6,
    period: 30,
    algorithm: "SHA1",
    date: Date(timeIntervalSince1970: 60)
)
record(remainingAt60 == 30, "secondsRemaining at 60 is 30")

print("\(caseCount) cases, \(failureCount) failed")
exit(failureCount == 0 ? 0 : 1)
