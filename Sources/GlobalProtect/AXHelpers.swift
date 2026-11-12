import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AXHelpers {
    enum Role {
        static let application = kAXApplicationRole
        static let window = kAXWindowRole
        static let button = kAXButtonRole
        static let textField = kAXTextFieldRole
        static let secureTextField = "AXSecureTextField"
        static let staticText = kAXStaticTextRole
        static let menuItem = kAXMenuItemRole
        static let menuButton = kAXMenuButtonRole
        static let popUpButton = kAXPopUpButtonRole
        static let menuBarItem = kAXMenuBarItemRole
    }

    enum Subrole {
        static let secureTextField = kAXSecureTextFieldSubrole
    }

    static func attributeValue(of element: AXUIElement, named attribute: CFString) -> AnyObject? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success else {
            return nil
        }
        return rawValue
    }

    static func elementValue(of element: AXUIElement, named attribute: CFString) -> AXUIElement? {
        guard let rawValue = attributeValue(of: element, named: attribute),
              CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let elementValue = rawValue as! AXUIElement
        return elementValue
    }

    static func stringAttribute(of element: AXUIElement, named attribute: CFString) -> String? {
        guard let rawValue = attributeValue(of: element, named: attribute) else {
            return nil
        }
        if let text = rawValue as? String {
            return text
        }
        if let number = rawValue as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    static func boolAttribute(of element: AXUIElement, named attribute: CFString) -> Bool? {
        guard let rawValue = attributeValue(of: element, named: attribute) else {
            return nil
        }
        if let number = rawValue as? NSNumber {
            return number.boolValue
        }
        if let flag = rawValue as? Bool {
            return flag
        }
        return nil
    }

    static func elementArrayAttribute(of element: AXUIElement, named attribute: CFString) -> [AXUIElement] {
        guard let rawValue = attributeValue(of: element, named: attribute),
              CFGetTypeID(rawValue) == CFArrayGetTypeID(),
              let elements = rawValue as? [AXUIElement] else {
            return []
        }
        return elements
    }

    static func role(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXRoleAttribute as CFString)
    }

    static func subrole(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXSubroleAttribute as CFString)
    }

    static func title(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXTitleAttribute as CFString)
    }

    static func elementDescription(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXDescriptionAttribute as CFString)
    }

    static func identifier(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXIdentifierAttribute as CFString)
    }

    static func placeholder(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXPlaceholderValueAttribute as CFString)
    }

    static func value(of element: AXUIElement) -> AnyObject? {
        attributeValue(of: element, named: kAXValueAttribute as CFString)
    }

    static func stringValue(of element: AXUIElement) -> String? {
        stringAttribute(of: element, named: kAXValueAttribute as CFString)
    }

    static func enabled(of element: AXUIElement) -> Bool? {
        boolAttribute(of: element, named: kAXEnabledAttribute as CFString)
    }

    static func position(of element: AXUIElement) -> CGPoint? {
        guard let axValue = axValue(of: element, named: kAXPositionAttribute as CFString) else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    static func size(of element: AXUIElement) -> CGSize? {
        guard let axValue = axValue(of: element, named: kAXSizeAttribute as CFString) else {
            return nil
        }
        var sizeValue = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &sizeValue) else {
            return nil
        }
        return sizeValue
    }

    static func children(of element: AXUIElement) -> [AXUIElement] {
        elementArrayAttribute(of: element, named: kAXChildrenAttribute as CFString)
    }

    static func windows(of element: AXUIElement) -> [AXUIElement] {
        elementArrayAttribute(of: element, named: kAXWindowsAttribute as CFString)
    }

    static func firstElement(
        in root: AXUIElement,
        maxDepth: Int = 12,
        where predicate: (AXUIElement) -> Bool
    ) -> AXUIElement? {
        if predicate(root) {
            return root
        }
        guard maxDepth > 0 else {
            return nil
        }
        for child in children(of: root) {
            if let match = firstElement(in: child, maxDepth: maxDepth - 1, where: predicate) {
                return match
            }
        }
        return nil
    }

    static func allElements(
        in root: AXUIElement,
        maxDepth: Int = 12,
        where predicate: (AXUIElement) -> Bool
    ) -> [AXUIElement] {
        var matches: [AXUIElement] = []
        if predicate(root) {
            matches.append(root)
        }
        guard maxDepth > 0 else {
            return matches
        }
        for child in children(of: root) {
            matches.append(contentsOf: allElements(in: child, maxDepth: maxDepth - 1, where: predicate))
        }
        return matches
    }

    static func normalizedText(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased()
    }

    static func text(_ text: String, matchesAny candidates: [String]) -> Bool {
        let normalizedValue = normalizedText(text)
        guard !normalizedValue.isEmpty else {
            return false
        }
        let valueWords = Set(normalizedValue.split(separator: " ").map(String.init))
        for candidate in candidates {
            let normalizedCandidate = normalizedText(candidate)
            guard !normalizedCandidate.isEmpty else {
                continue
            }
            if normalizedValue == normalizedCandidate {
                return true
            }
            let candidateWords = normalizedCandidate.split(separator: " ").map(String.init)
            if !candidateWords.isEmpty && candidateWords.allSatisfy({ valueWords.contains($0) }) {
                return true
            }
        }
        return false
    }

    static func text(_ text: String, containsAny candidates: [String]) -> Bool {
        let normalizedValue = normalizedText(text)
        guard !normalizedValue.isEmpty else {
            return false
        }
        return candidates.contains { candidate in
            let normalizedCandidate = normalizedText(candidate)
            return !normalizedCandidate.isEmpty && normalizedValue.contains(normalizedCandidate)
        }
    }

    static func labels(of element: AXUIElement) -> [String] {
        [
            title(of: element),
            elementDescription(of: element),
            stringValue(of: element),
            identifier(of: element)
        ].compactMap { $0 }.filter { !$0.isEmpty }
    }

    static func hasLabel(_ element: AXUIElement, matchingAny candidates: [String]) -> Bool {
        labels(of: element).contains { text($0, matchesAny: candidates) }
    }

    static func hasLabel(_ element: AXUIElement, containing textValue: String) -> Bool {
        labels(of: element).contains { text($0, containsAny: [textValue]) }
    }

    static func findButton(
        in root: AXUIElement,
        titles: [String],
        maxDepth: Int = 14
    ) -> AXUIElement? {
        firstElement(in: root, maxDepth: maxDepth) { element in
            guard role(of: element) == Role.button else {
                return false
            }
            return hasLabel(element, matchingAny: titles)
        }
    }

    static func findButton(
        in root: AXUIElement,
        containing textValue: String,
        maxDepth: Int = 14
    ) -> AXUIElement? {
        firstElement(in: root, maxDepth: maxDepth) { element in
            let roleValue = role(of: element)
            guard roleValue == Role.button || roleValue == Role.menuButton || roleValue == Role.popUpButton else {
                return false
            }
            return hasLabel(element, containing: textValue)
        }
    }

    static func findElement(
        in root: AXUIElement,
        role requiredRole: String,
        titles: [String],
        maxDepth: Int = 14
    ) -> AXUIElement? {
        firstElement(in: root, maxDepth: maxDepth) { element in
            guard role(of: element) == requiredRole else {
                return false
            }
            return hasLabel(element, matchingAny: titles)
        }
    }

    static func isSecureTextField(_ element: AXUIElement) -> Bool {
        subrole(of: element) == Subrole.secureTextField || role(of: element) == Role.secureTextField
    }

    static func isTextInput(_ element: AXUIElement) -> Bool {
        guard let roleValue = role(of: element) else {
            return false
        }
        return roleValue == Role.textField || roleValue == Role.secureTextField || isSecureTextField(element)
    }

    static func allTextFields(in root: AXUIElement, maxDepth: Int = 16) -> [AXUIElement] {
        allElements(in: root, maxDepth: maxDepth) { isTextInput($0) }
    }

    static func fieldLabels(of element: AXUIElement) -> [String] {
        [
            title(of: element),
            elementDescription(of: element),
            placeholder(of: element),
            identifier(of: element)
        ].compactMap { $0 }.filter { !$0.isEmpty }
    }

    static func hasFieldLabel(_ element: AXUIElement, matchingAny candidates: [String]) -> Bool {
        fieldLabels(of: element).contains { text($0, containsAny: candidates) }
    }

    static func findTextField(
        in root: AXUIElement,
        labels candidates: [String],
        maxDepth: Int = 16
    ) -> AXUIElement? {
        allTextFields(in: root, maxDepth: maxDepth).first { element in
            guard !isSecureTextField(element) else {
                return false
            }
            return hasFieldLabel(element, matchingAny: candidates)
        }
    }

    static func findSecureTextField(in root: AXUIElement, maxDepth: Int = 16) -> AXUIElement? {
        allTextFields(in: root, maxDepth: maxDepth).first { isSecureTextField($0) }
    }

    static func findPasswordField(in root: AXUIElement, maxDepth: Int = 16) -> AXUIElement? {
        if let secureField = findSecureTextField(in: root, maxDepth: maxDepth) {
            return secureField
        }
        return allTextFields(in: root, maxDepth: maxDepth).first { element in
            guard !isSecureTextField(element) else {
                return false
            }
            return hasFieldLabel(element, matchingAny: ["password"])
        }
    }

    static func isSameElement(_ first: AXUIElement, _ second: AXUIElement) -> Bool {
        CFEqual(first, second)
    }

    @discardableResult
    static func setValue(_ textValue: String, on element: AXUIElement) -> Bool {
        let cfValue: CFTypeRef = textValue as CFString
        return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, cfValue) == .success
    }

    @discardableResult
    static func focus(_ element: AXUIElement) -> Bool {
        let focusError = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        guard focusError == .success else {
            return false
        }
        return isFocused(element)
    }

    @discardableResult
    static func press(_ element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func typeText(_ textValue: String, into element: AXUIElement, replacingExisting: Bool = true) -> Bool {
        guard focus(element) else {
            return false
        }
        guard isOwningProcessFrontmost(element) else {
            return false
        }
        if replacingExisting {
            selectAllText()
        }
        guard isFocused(element) else {
            return false
        }
        return typeText(textValue)
    }

    @discardableResult
    private static func typeText(_ textValue: String) -> Bool {
        let characters = Array(textValue)
        guard !characters.isEmpty else {
            return true
        }
        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            return false
        }
        let chunkSize = 20
        var offset = 0
        while offset < characters.count {
            let end = min(offset + chunkSize, characters.count)
            let chunk = Array(String(characters[offset..<end]).utf16)
            guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
                return false
            }
            chunk.withUnsafeBufferPointer { buffer in
                keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            offset = end
            Thread.sleep(forTimeInterval: 0.01)
        }
        return true
    }

    private static func isOwningProcessFrontmost(_ element: AXUIElement) -> Bool {
        var processIdentifier: pid_t = 0
        guard AXUIElementGetPid(element, &processIdentifier) == .success else {
            return false
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier
    }

    private static func isFocused(_ element: AXUIElement) -> Bool {
        for _ in 0..<3 {
            if boolAttribute(of: element, named: kAXFocusedAttribute as CFString) == true {
                return true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
    }

    private static func selectAllText() {
        guard let eventSource = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
    }

    private static func axValue(of element: AXUIElement, named attribute: CFString) -> AXValue? {
        guard let rawValue = attributeValue(of: element, named: attribute),
              CFGetTypeID(rawValue) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = rawValue as! AXValue
        return axValue
    }
}
