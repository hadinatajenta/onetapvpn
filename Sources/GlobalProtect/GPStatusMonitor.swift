import Foundation

@MainActor
final class GPStatusMonitor: StatusMonitoring {
    var onStatusChange: ((VPNStatus) -> Void)?
    private(set) var currentStatus: VPNStatus = .unknown

    private var timer: Timer?
    private let refreshInterval: TimeInterval = 3

    func start() {
        if timer == nil {
            let newTimer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
        refresh()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard let logText = GlobalProtectLog.readTail() else {
            return
        }
        guard let newStatus = GlobalProtectLog.status(fromLogText: logText) else {
            return
        }
        apply(newStatus)
    }

    private func apply(_ newStatus: VPNStatus) {
        guard newStatus != currentStatus else {
            return
        }
        currentStatus = newStatus
        onStatusChange?(newStatus)
    }
}

enum GlobalProtectLog {
    static let maximumTailBytes = 256 * 1024

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/PaloAltoNetworks/GlobalProtect/PanGPA.log")
    }

    static func currentSize() -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return nil
        }
        return sizeNumber.uint64Value
    }

    static func readTail(maxBytes: Int = maximumTailBytes) -> String? {
        guard maxBytes > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        do {
            let fileSize = try handle.seekToEnd()
            let startOffset = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
            try handle.seek(toOffset: startOffset)
            guard let tailData = try handle.readToEnd() else {
                return nil
            }
            return String(decoding: tailData, as: UTF8.self)
        } catch {
            return nil
        }
    }

    static func read(fromOffset offset: UInt64, maxBytes: Int = maximumTailBytes) -> String? {
        guard maxBytes > 0, let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer {
            try? handle.close()
        }
        do {
            let fileSize = try handle.seekToEnd()
            let effectiveOffset = fileSize >= offset ? offset : 0
            guard fileSize > effectiveOffset else {
                return nil
            }
            let tailStart = fileSize > UInt64(maxBytes) ? fileSize - UInt64(maxBytes) : 0
            let startOffset = max(effectiveOffset, tailStart)
            try handle.seek(toOffset: startOffset)
            guard let appendedData = try handle.readToEnd(), !appendedData.isEmpty else {
                return nil
            }
            return String(decoding: appendedData, as: UTF8.self)
        } catch {
            return nil
        }
    }

    static func status(fromLogText logText: String) -> VPNStatus? {
        let portalStatusValue = lastValue(of: "portal-status", in: logText)?.lowercased() ?? ""
        if portalStatusValue.contains("user authentication failed") {
            return .failed("GlobalProtect authentication failed.")
        }
        guard let stateValue = lastValue(of: "state", in: logText)?.lowercased() else {
            return nil
        }
        switch stateValue {
        case "connected":
            return .connected
        case "disconnected":
            return .disconnected
        default:
            if stateValue.hasPrefix("connecting") || stateValue.contains("retrieving configuration") {
                return .connecting
            }
            if stateValue.hasPrefix("disconnecting") {
                return .disconnecting
            }
            return nil
        }
    }

    static func stateName(fromLogText logText: String) -> String? {
        lastValue(of: "state", in: logText)?.lowercased()
    }

    static func authenticationFailureMessage(inLogText logText: String) -> String? {
        let normalizedValue = logText.lowercased()
        if normalizedValue.contains("user authentication failed") {
            return "GlobalProtect authentication failed."
        }
        let statusValues = [
            lastValue(of: "portal-status", in: logText),
            lastValue(of: "state", in: logText)
        ].compactMap { $0 }.joined(separator: " ").lowercased()
        let markers = ["invalid", "incorrect", "denied"]
        guard markers.contains(where: { statusValues.contains($0) }) else {
            return nil
        }
        return "GlobalProtect authentication failed."
    }

    static func lastValue(of tag: String, in logText: String) -> String? {
        let closingTag = "</\(tag)>"
        guard let closingRange = logText.range(of: closingTag, options: [.backwards, .caseInsensitive]) else {
            return nil
        }
        let prefix = logText[..<closingRange.lowerBound]
        let openingTag = "<\(tag)>"
        guard let openingRange = prefix.range(of: openingTag, options: [.backwards, .caseInsensitive]) else {
            return nil
        }
        let rawValue = prefix[openingRange.upperBound...]
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return decodedEntities(trimmedValue)
    }

    private static func decodedEntities(_ textValue: String) -> String {
        var decodedValue = textValue
        decodedValue = decodedValue.replacingOccurrences(of: "&lt;", with: "<")
        decodedValue = decodedValue.replacingOccurrences(of: "&gt;", with: ">")
        decodedValue = decodedValue.replacingOccurrences(of: "&quot;", with: "\"")
        decodedValue = decodedValue.replacingOccurrences(of: "&apos;", with: "'")
        decodedValue = decodedValue.replacingOccurrences(of: "&amp;", with: "&")
        return decodedValue
    }
}
