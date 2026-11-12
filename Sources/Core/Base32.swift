import Foundation

enum Base32 {
    static func decode(_ encodedSecret: String) throws -> Data {
        let sanitized = encodedSecret.filter { !$0.isWhitespace && $0 != "-" }
        guard !sanitized.isEmpty else {
            throw TOTPError.invalidSecret
        }

        let payload: String
        if let paddingStart = sanitized.firstIndex(of: "=") {
            let padding = sanitized[paddingStart...]
            guard padding.allSatisfy({ $0 == "=" }) else {
                throw TOTPError.invalidSecret
            }
            let paddingCount = padding.count
            guard [1, 3, 4, 6].contains(paddingCount) else {
                throw TOTPError.invalidSecret
            }
            payload = String(sanitized[..<paddingStart])
            guard (payload.count + paddingCount).isMultiple(of: 8) else {
                throw TOTPError.invalidSecret
            }
        } else {
            payload = sanitized
        }

        guard !payload.isEmpty else {
            throw TOTPError.invalidSecret
        }

        let unpaddedRemainder = payload.count % 8
        guard unpaddedRemainder != 1, unpaddedRemainder != 3, unpaddedRemainder != 6 else {
            throw TOTPError.invalidSecret
        }

        var decodedBytes: [UInt8] = []
        decodedBytes.reserveCapacity(payload.count * 5 / 8)
        var bitBuffer: UInt32 = 0
        var bufferedBitCount = 0

        for character in payload {
            guard let value = value(for: character) else {
                throw TOTPError.invalidSecret
            }
            bitBuffer = (bitBuffer << 5) | UInt32(value)
            bufferedBitCount += 5
            if bufferedBitCount >= 8 {
                bufferedBitCount -= 8
                decodedBytes.append(UInt8((bitBuffer >> UInt32(bufferedBitCount)) & 0xFF))
            }
        }

        if bufferedBitCount > 0 {
            let remainderMask = (UInt32(1) << UInt32(bufferedBitCount)) - 1
            guard bitBuffer & remainderMask == 0 else {
                throw TOTPError.invalidSecret
            }
        }

        return Data(decodedBytes)
    }

    private static func value(for character: Character) -> UInt8? {
        guard let asciiValue = character.asciiValue else {
            return nil
        }
        let uppercaseValue: UInt8
        if asciiValue >= 97 && asciiValue <= 122 {
            uppercaseValue = asciiValue - 32
        } else {
            uppercaseValue = asciiValue
        }
        switch uppercaseValue {
        case 65...90:
            return uppercaseValue - 65
        case 50...55:
            return uppercaseValue - 50 + 26
        default:
            return nil
        }
    }
}
