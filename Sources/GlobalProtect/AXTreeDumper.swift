import ApplicationServices
import Foundation

enum AXTreeDumper {
    static func dump(application: AXUIElement, timestamp: Date = Date()) throws -> URL {
        let directory = logDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let fileURL = directory.appendingPathComponent("ax-dump-\(timestampText(timestamp)).txt")
        let contents = render(application: application)
        try Data(contents.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func render(application: AXUIElement) -> String {
        var lines: [String] = [line(for: application, depth: 0)]
        for window in applicationWindows(application) {
            appendTree(window, depth: 1, lines: &lines)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func applicationWindows(_ application: AXUIElement) -> [AXUIElement] {
        let declaredWindows = AXHelpers.windows(of: application)
        if !declaredWindows.isEmpty {
            return declaredWindows
        }
        return AXHelpers.allElements(in: application, maxDepth: 8) { element in
            AXHelpers.role(of: element) == AXHelpers.Role.window
        }
    }

    private static func appendTree(_ element: AXUIElement, depth: Int, lines: inout [String]) {
        guard depth <= 64 else {
            return
        }
        lines.append(line(for: element, depth: depth))
        for child in AXHelpers.children(of: element) {
            appendTree(child, depth: depth + 1, lines: &lines)
        }
    }

    private static func line(for element: AXUIElement, depth: Int) -> String {
        let roleValue = AXHelpers.role(of: element) ?? "unknown"
        let subroleValue = AXHelpers.subrole(of: element) ?? ""
        let titleValue = AXHelpers.title(of: element) ?? ""
        let descriptionValue = AXHelpers.elementDescription(of: element) ?? ""
        let identifierValue = AXHelpers.identifier(of: element) ?? ""
        let enabledValue = enabledText(of: element)
        let positionValue = positionText(of: element)
        let sizeValue = sizeText(of: element)
        let childCount = AXHelpers.children(of: element).count
        let valueValue = valueText(of: element)
        let fields = [
            "role=\(quoted(roleValue))",
            "subrole=\(quoted(subroleValue))",
            "title=\(quoted(titleValue))",
            "description=\(quoted(descriptionValue))",
            "identifier=\(quoted(identifierValue))",
            "enabled=\(enabledValue)",
            "position=\(positionValue)",
            "size=\(sizeValue)",
            "children=\(childCount)",
            "value=\(valueValue)"
        ]
        return String(repeating: "  ", count: depth) + fields.joined(separator: " ")
    }

    private static func enabledText(of element: AXUIElement) -> String {
        guard let isEnabled = AXHelpers.enabled(of: element) else {
            return "unknown"
        }
        return isEnabled ? "true" : "false"
    }

    private static func positionText(of element: AXUIElement) -> String {
        guard let point = AXHelpers.position(of: element) else {
            return "unknown"
        }
        return "\(Int(point.x)),\(Int(point.y))"
    }

    private static func sizeText(of element: AXUIElement) -> String {
        guard let sizeValue = AXHelpers.size(of: element) else {
            return "unknown"
        }
        return "\(Int(sizeValue.width))x\(Int(sizeValue.height))"
    }

    private static func valueText(of element: AXUIElement) -> String {
        if shouldRedact(element) {
            return "<redacted>"
        }
        guard let rawValue = AXHelpers.value(of: element) else {
            return "-"
        }
        if let textValue = rawValue as? String {
            return quoted(textValue)
        }
        if let numberValue = rawValue as? NSNumber {
            return numberValue.stringValue
        }
        return "<complex>"
    }

    private static func shouldRedact(_ element: AXUIElement) -> Bool {
        let roleValue = AXHelpers.role(of: element) ?? ""
        let subroleValue = AXHelpers.subrole(of: element) ?? ""
        if roleValue == AXHelpers.Role.textField ||
            roleValue == AXHelpers.Role.secureTextField ||
            subroleValue == AXHelpers.Subrole.secureTextField {
            return true
        }
        let labelText = [
            AXHelpers.title(of: element),
            AXHelpers.elementDescription(of: element),
            AXHelpers.identifier(of: element),
            AXHelpers.placeholder(of: element)
        ].compactMap { $0 }.joined(separator: " ")
        return AXHelpers.text(labelText, containsAny: ["password", "secret"])
    }

    private static func quoted(_ textValue: String) -> String {
        "\"\(sanitized(textValue))\""
    }

    private static func sanitized(_ textValue: String) -> String {
        textValue
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func timestampText(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: timestamp)
    }

    private static func logDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OneTapVPN", isDirectory: true)
    }
}
