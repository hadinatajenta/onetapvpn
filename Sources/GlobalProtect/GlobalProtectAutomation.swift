import AppKit
import ApplicationServices
import Foundation

@MainActor
final class GlobalProtectAutomation: GlobalProtectControlling {
    private enum ConnectionState {
        case connected
        case disconnected
        case connecting
        case disconnecting
        case unknown
    }

    private struct LoginForm {
        let usernameField: AXUIElement?
        let passwordField: AXUIElement?
        let signInButton: AXUIElement?
    }

    private let bundleIdentifiers = [
        "com.paloaltonetworks.GlobalProtect.client",
        "com.paloaltonetworks.GlobalProtect"
    ]
    private let applicationPath = "/Applications/GlobalProtect.app"
    private let loginFormTimeout: TimeInterval = 10
    private let connectionTimeout: TimeInterval = 45
    private let disconnectionTimeout: TimeInterval = 15
    private let pollInterval: TimeInterval = 0.5
    private let panelOpenTimeout: TimeInterval = 2
    private let signInTitles = ["Sign In", "Log In", "Login"]

    var isGlobalProtectRunning: Bool {
        runningApplication != nil
    }

    private var runningApplication: NSRunningApplication? {
        for bundleIdentifier in bundleIdentifiers {
            if let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
                .first(where: { !$0.isTerminated }) {
                return application
            }
        }
        let applicationURL = URL(fileURLWithPath: applicationPath).resolvingSymlinksInPath()
        return NSWorkspace.shared.runningApplications.first { application in
            guard !application.isTerminated, let bundleURL = application.bundleURL else {
                return false
            }
            return bundleURL.resolvingSymlinksInPath() == applicationURL
        }
    }

    func launchGlobalProtect() throws {
        if isGlobalProtectRunning {
            return
        }
        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launchProcess.arguments = ["-a", applicationPath]
        do {
            try launchProcess.run()
        } catch {
            throw GlobalProtectError.applicationNotRunning
        }
        launchProcess.waitUntilExit()
        guard launchProcess.terminationStatus == 0 else {
            throw GlobalProtectError.applicationNotRunning
        }
        guard waitForRunningApplication(timeout: 10) else {
            throw GlobalProtectError.applicationNotRunning
        }
    }

    func connect(credentials: Credentials, otpCode: String) async throws {
        try requireAccessibilityPermission()
        if !isGlobalProtectRunning {
            try launchGlobalProtect()
        }
        guard let application = runningApplication else {
            throw GlobalProtectError.applicationNotRunning
        }
        let applicationElement = applicationElement(for: application)
        let panelRoot = try await openStatusPanel(applicationElement: applicationElement)

        if connectionState(from: statusText(in: panelRoot)) == .connected {
            closeStatusPanel(applicationElement: applicationElement)
            return
        }

        let connectButton = AXHelpers.findButton(in: panelRoot, titles: ["Connect"], maxDepth: 12)
        let existingSignInButton = AXHelpers.findButton(in: applicationElement, titles: signInTitles, maxDepth: 18)
        if let connectButton {
            guard AXHelpers.press(connectButton) else {
                throw GlobalProtectError.connectButtonNotFound
            }
        } else if existingSignInButton == nil {
            throw GlobalProtectError.connectButtonNotFound
        }

        guard let loginForm = await waitForLoginForm(applicationElement: applicationElement, timeout: loginFormTimeout) else {
            let finalForm = loginForm(in: applicationElement)
            if finalForm.signInButton != nil {
                throw GlobalProtectError.loginFieldsNotFound
            }
            throw GlobalProtectError.loginWindowNotFound
        }
        guard let usernameField = loginForm.usernameField, let passwordField = loginForm.passwordField else {
            throw GlobalProtectError.loginFieldsNotFound
        }

        let canTypeText = await activateApplication(application)
        try fillUsername(credentials.username, in: usernameField, canTypeText: canTypeText)
        guard fillPassword(credentials.passwordWithOTP(otpCode), in: passwordField, canTypeText: canTypeText) else {
            throw GlobalProtectError.loginFieldsNotFound
        }

        guard let signInButton = loginForm.signInButton ?? findSubmitButton(in: applicationElement) else {
            throw GlobalProtectError.signInButtonNotFound
        }
        let logOffset = GlobalProtectLog.currentSize() ?? 0
        guard AXHelpers.press(signInButton) else {
            throw GlobalProtectError.signInButtonNotFound
        }
        try await waitForConnectionResult(applicationElement: applicationElement, logOffset: logOffset)
    }

    func disconnect() async throws {
        guard isGlobalProtectRunning else {
            return
        }
        try requireAccessibilityPermission()
        guard let application = runningApplication else {
            return
        }
        let applicationElement = applicationElement(for: application)
        let panelRoot = try await openStatusPanel(applicationElement: applicationElement)

        if connectionState(from: statusText(in: panelRoot)) == .disconnected {
            closeStatusPanel(applicationElement: applicationElement)
            return
        }

        let logOffset = GlobalProtectLog.currentSize() ?? 0
        try await pressDisconnectButton(in: applicationElement)
        try await waitForDisconnection(applicationElement: applicationElement, logOffset: logOffset)
    }

    func dumpAccessibilityTree() throws -> URL {
        try requireAccessibilityPermission()
        if !isGlobalProtectRunning {
            try launchGlobalProtect()
        }
        guard let application = runningApplication else {
            throw GlobalProtectError.applicationNotRunning
        }
        let applicationElement = applicationElement(for: application)
        return try AXTreeDumper.dump(application: applicationElement)
    }

    private func requireAccessibilityPermission() throws {
        guard AccessibilityPermission.isTrusted else {
            AccessibilityPermission.requestIfNeeded()
            throw GlobalProtectError.accessibilityPermissionDenied
        }
    }

    private func waitForRunningApplication(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isGlobalProtectRunning {
                return true
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return isGlobalProtectRunning
    }

    private func applicationElement(for application: NSRunningApplication) -> AXUIElement {
        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(applicationElement, 2)
        return applicationElement
    }

    private func extrasMenuBarItem(applicationElement: AXUIElement) -> AXUIElement? {
        guard let menuBar = AXHelpers.elementValue(of: applicationElement, named: kAXExtrasMenuBarAttribute as CFString) else {
            return nil
        }
        return AXHelpers.children(of: menuBar).first
    }

    private func openStatusPanel(applicationElement: AXUIElement) async throws -> AXUIElement {
        if let existingRoot = statusRoot(in: applicationElement), panelScore(in: existingRoot) > 0 {
            return existingRoot
        }
        guard let menuBarItem = extrasMenuBarItem(applicationElement: applicationElement) else {
            throw GlobalProtectError.statusPanelNotFound
        }
        _ = AXHelpers.press(menuBarItem)
        if let panelRoot = await waitForStatusRoot(applicationElement: applicationElement, timeout: panelOpenTimeout) {
            return panelRoot
        }
        _ = AXHelpers.press(menuBarItem)
        if let panelRoot = await waitForStatusRoot(applicationElement: applicationElement, timeout: panelOpenTimeout) {
            return panelRoot
        }
        throw GlobalProtectError.statusPanelNotFound
    }

    private func waitForStatusRoot(applicationElement: AXUIElement, timeout: TimeInterval) async -> AXUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let panelRoot = statusRoot(in: applicationElement) {
                return panelRoot
            }
            await pause(0.1)
        }
        return statusRoot(in: applicationElement)
    }

    private func closeStatusPanel(applicationElement: AXUIElement) {
        guard statusRoot(in: applicationElement) != nil else {
            return
        }
        guard let menuBarItem = extrasMenuBarItem(applicationElement: applicationElement) else {
            return
        }
        _ = AXHelpers.press(menuBarItem)
    }

    private func applicationWindows(_ applicationElement: AXUIElement) -> [AXUIElement] {
        let declaredWindows = AXHelpers.windows(of: applicationElement)
        if !declaredWindows.isEmpty {
            return declaredWindows
        }
        return AXHelpers.allElements(in: applicationElement, maxDepth: 6) { element in
            AXHelpers.role(of: element) == AXHelpers.Role.window
        }
    }

    private func statusRoot(in applicationElement: AXUIElement) -> AXUIElement? {
        let windows = applicationWindows(applicationElement)
        var candidates = windows
        if let menuBarItem = extrasMenuBarItem(applicationElement: applicationElement) {
            candidates.append(menuBarItem)
        }
        var bestRoot: AXUIElement?
        var bestScore = 0
        for candidate in candidates {
            let score = panelScore(in: candidate)
            if score > bestScore {
                bestScore = score
                bestRoot = candidate
            }
        }
        if let bestRoot {
            return bestRoot
        }
        return windows.first
    }

    private func panelScore(in root: AXUIElement) -> Int {
        var score = 0
        if AXHelpers.findButton(in: root, titles: ["Connect", "Disconnect"], maxDepth: 12) != nil {
            score += 10
        }
        if AXHelpers.findButton(in: root, titles: signInTitles, maxDepth: 12) != nil {
            score += 4
        }
        if !AXHelpers.allTextFields(in: root, maxDepth: 12).isEmpty {
            score += 3
        }
        if connectionState(from: statusText(in: root)) != .unknown {
            score += 5
        }
        return score
    }

    private func statusText(in root: AXUIElement) -> String {
        let staticTextElements = AXHelpers.allElements(in: root, maxDepth: 14) { element in
            AXHelpers.role(of: element) == AXHelpers.Role.staticText
        }
        let textParts = staticTextElements.compactMap { element in
            AXHelpers.stringValue(of: element)
                ?? AXHelpers.title(of: element)
                ?? AXHelpers.elementDescription(of: element)
        }
        return textParts.joined(separator: " ")
    }

    private func connectionState(from textValue: String) -> ConnectionState {
        let normalizedValue = textValue.lowercased()
        guard !normalizedValue.isEmpty else {
            return .unknown
        }
        if normalizedValue.contains("not connected") || normalizedValue.contains("disconnected") {
            return .disconnected
        }
        if normalizedValue.contains("disconnecting") {
            return .disconnecting
        }
        if normalizedValue.contains("connected") {
            return .connected
        }
        if normalizedValue.contains("connecting") || normalizedValue.contains("retrieving configuration") {
            return .connecting
        }
        return .unknown
    }

    private func authenticationFailure(in textValue: String) -> Bool {
        let normalizedValue = textValue.lowercased()
        return normalizedValue.contains("user authentication failed")
            || normalizedValue.contains("invalid")
            || normalizedValue.contains("incorrect")
            || normalizedValue.contains("denied")
    }

    private func loginForm(in applicationElement: AXUIElement) -> LoginForm {
        let textFields = AXHelpers.allTextFields(in: applicationElement, maxDepth: 20)
        let nonSecureFields = textFields.filter { !AXHelpers.isSecureTextField($0) }
        let secureFields = textFields.filter { AXHelpers.isSecureTextField($0) }

        var usernameField: AXUIElement?
        for field in nonSecureFields where AXHelpers.hasFieldLabel(field, matchingAny: ["username", "user"]) {
            usernameField = field
            break
        }
        if usernameField == nil {
            usernameField = nonSecureFields.first
        }

        var passwordField: AXUIElement? = secureFields.first
        if passwordField == nil {
            for field in nonSecureFields {
                if let usernameField, AXHelpers.isSameElement(field, usernameField) {
                    continue
                }
                if AXHelpers.hasFieldLabel(field, matchingAny: ["password"]) {
                    passwordField = field
                    break
                }
            }
        }
        if passwordField == nil {
            passwordField = nonSecureFields.first { field in
                guard let usernameField else {
                    return true
                }
                return !AXHelpers.isSameElement(field, usernameField)
            }
        }

        return LoginForm(
            usernameField: usernameField,
            passwordField: passwordField,
            signInButton: findSubmitButton(in: applicationElement)
        )
    }

    private func findSubmitButton(in root: AXUIElement) -> AXUIElement? {
        if let signInButton = AXHelpers.findButton(in: root, titles: signInTitles, maxDepth: 20) {
            return signInButton
        }
        return AXHelpers.findButton(in: root, titles: ["Connect"], maxDepth: 20)
    }

    private func waitForLoginForm(applicationElement: AXUIElement, timeout: TimeInterval) async -> LoginForm? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let currentForm = loginForm(in: applicationElement)
            if currentForm.usernameField != nil && currentForm.passwordField != nil {
                return currentForm
            }
            if !isGlobalProtectRunning {
                return nil
            }
            await pause(0.25)
        }
        let finalForm = loginForm(in: applicationElement)
        if finalForm.usernameField != nil && finalForm.passwordField != nil {
            return finalForm
        }
        return nil
    }

    private func activateApplication(_ application: NSRunningApplication) async -> Bool {
        if application.isActive {
            return true
        }
        _ = application.activate(options: [])
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            if application.isActive {
                return true
            }
            await pause(0.05)
        }
        return application.isActive
    }

    private func fillUsername(_ username: String, in field: AXUIElement, canTypeText: Bool) throws {
        let currentValue = AXHelpers.stringValue(of: field) ?? ""
        if currentValue == username {
            return
        }
        if AXHelpers.setValue(username, on: field) {
            for _ in 0..<5 {
                if AXHelpers.stringValue(of: field) == username {
                    return
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        guard canTypeText, AXHelpers.typeText(username, into: field, replacingExisting: true) else {
            throw GlobalProtectError.loginFieldsNotFound
        }
        guard AXHelpers.stringValue(of: field) == username else {
            throw GlobalProtectError.loginFieldsNotFound
        }
    }

    private func fillPassword(_ password: String, in field: AXUIElement, canTypeText: Bool) -> Bool {
        if AXHelpers.setValue(password, on: field) {
            return true
        }
        guard canTypeText else {
            return false
        }
        return AXHelpers.typeText(password, into: field, replacingExisting: true)
    }

    private func waitForConnectionResult(applicationElement: AXUIElement, logOffset: UInt64) async throws {
        let deadline = Date().addingTimeInterval(connectionTimeout)
        while Date() < deadline {
            if !isGlobalProtectRunning {
                throw GlobalProtectError.applicationNotRunning
            }
            if isConnectionReportedApplicationSide(applicationElement: applicationElement) {
                closeStatusPanel(applicationElement: applicationElement)
                return
            }
            if let logText = GlobalProtectLog.read(fromOffset: logOffset) {
                if GlobalProtectLog.stateName(fromLogText: logText) == "connected" {
                    closeStatusPanel(applicationElement: applicationElement)
                    return
                }
                if GlobalProtectLog.authenticationFailureMessage(inLogText: logText) != nil {
                    throw GlobalProtectError.authenticationFailed("GlobalProtect authentication failed.")
                }
            }
            if let panelRoot = statusRoot(in: applicationElement),
               authenticationFailure(in: statusText(in: panelRoot)) {
                throw GlobalProtectError.authenticationFailed("GlobalProtect authentication failed.")
            }
            await pause(pollInterval)
        }
        if isConnectionReportedApplicationSide(applicationElement: applicationElement) {
            closeStatusPanel(applicationElement: applicationElement)
            return
        }
        throw GlobalProtectError.timeout("connect")
    }

    private func isConnectionReportedApplicationSide(applicationElement: AXUIElement) -> Bool {
        guard let panelRoot = statusRoot(in: applicationElement) else {
            return false
        }
        return connectionState(from: statusText(in: panelRoot)) == .connected
    }

    private func pressDisconnectButton(in applicationElement: AXUIElement) async throws {
        if let disconnectButton = AXHelpers.findButton(in: applicationElement, titles: ["Disconnect"], maxDepth: 18) {
            guard AXHelpers.press(disconnectButton) else {
                throw GlobalProtectError.unsupportedUI
            }
            return
        }
        guard let optionsButton = AXHelpers.findButton(in: applicationElement, containing: "Options Menu", maxDepth: 18) else {
            throw GlobalProtectError.unsupportedUI
        }
        guard AXHelpers.press(optionsButton) else {
            throw GlobalProtectError.unsupportedUI
        }
        await pause(0.5)
        if let disconnectMenuItem = AXHelpers.findElement(
            in: applicationElement,
            role: AXHelpers.Role.menuItem,
            titles: ["Disconnect"],
            maxDepth: 18
        ) {
            guard AXHelpers.press(disconnectMenuItem) else {
                throw GlobalProtectError.unsupportedUI
            }
            return
        }
        if let disconnectButton = AXHelpers.findButton(in: applicationElement, titles: ["Disconnect"], maxDepth: 18) {
            guard AXHelpers.press(disconnectButton) else {
                throw GlobalProtectError.unsupportedUI
            }
            return
        }
        throw GlobalProtectError.unsupportedUI
    }

    private func waitForDisconnection(applicationElement: AXUIElement, logOffset: UInt64) async throws {
        let deadline = Date().addingTimeInterval(disconnectionTimeout)
        while Date() < deadline {
            if !isGlobalProtectRunning {
                return
            }
            if isDisconnectionReportedApplicationSide(applicationElement: applicationElement) {
                closeStatusPanel(applicationElement: applicationElement)
                return
            }
            if let logText = GlobalProtectLog.read(fromOffset: logOffset),
               GlobalProtectLog.stateName(fromLogText: logText) == "disconnected" {
                closeStatusPanel(applicationElement: applicationElement)
                return
            }
            await pause(pollInterval)
        }
        if !isGlobalProtectRunning {
            return
        }
        if isDisconnectionReportedApplicationSide(applicationElement: applicationElement) {
            closeStatusPanel(applicationElement: applicationElement)
            return
        }
        throw GlobalProtectError.timeout("disconnect")
    }

    private func isDisconnectionReportedApplicationSide(applicationElement: AXUIElement) -> Bool {
        guard let panelRoot = statusRoot(in: applicationElement) else {
            return false
        }
        return connectionState(from: statusText(in: panelRoot)) == .disconnected
    }

    private func pause(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
