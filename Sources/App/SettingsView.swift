import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var vpnController: VPNController
    let totpGenerator: TOTPGenerating
    let loginItemController: LoginItemController

    @State private var portal = Credentials.defaultPortal
    @State private var username = ""
    @State private var password = ""
    @State private var totpSecret = ""
    @State private var isShowingSecret = false
    @State private var isShowingScanner = false
    @State private var otpPlacement: OTPPlacement = .append
    @State private var otpSeparator = ""
    @State private var otpDigits = 6
    @State private var otpPeriod = 30
    @State private var otpAlgorithm = "SHA1"
    @State private var isAdvancedExpanded = false
    @State private var generatedCode = ""
    @State private var secondsRemaining = 0
    @State private var verificationError: String?
    @State private var isAccessibilityTrusted = AccessibilityPermission.isTrusted
    @State private var isLaunchAtLoginEnabled = false
    @State private var isUpdatingLaunchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var isRunningDiagnostic = false
    @State private var diagnosticMessage: String?
    @State private var diagnosticError: String?
    @State private var feedbackMessage: String?
    @State private var isFeedbackError = false
    @State private var isConfirmingDelete = false
    @State private var hasLoadedCredentials = false

    var body: some View {
        Form {
            statusSection
            connectionSection
            advancedSection
            verificationSection
            accessibilitySection
            automationSection
            actionsSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 520)
        .onAppear(perform: loadCredentialsIfNeeded)
        .task {
            await runVerificationTimer()
        }
        .confirmationDialog(
            "Delete saved credentials?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Credentials", role: .destructive, action: deleteCredentials)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the portal, username, password, and TOTP secret from the keychain.")
        }
        .sheet(isPresented: $isShowingScanner) {
            QRCodeScannerView { payload in
                try applyScannedPayload(payload)
            }
        }
    }

    private var statusSection: some View {
        Section("Status") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: statusSymbolName)
                    .font(.title3)
                    .foregroundStyle(statusTint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(vpnController.status.displayText)
                        .font(.headline)

                    if let lastError = vpnController.lastError {
                        Text(lastError)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            TextField("Portal", text: $portal, prompt: Text(Credentials.defaultPortal))
                .autocorrectionDisabled()

            TextField("Username", text: $username)
                .autocorrectionDisabled()

            SecureField("Password", text: $password)

            LabeledContent("TOTP secret") {
                HStack(spacing: 8) {
                    Group {
                        if isShowingSecret {
                            TextField("TOTP secret", text: $totpSecret)
                        } else {
                            SecureField("TOTP secret", text: $totpSecret)
                        }
                    }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("TOTP secret")

                    Toggle("Show", isOn: $isShowingSecret)
                        .toggleStyle(.button)
                        .controlSize(.small)
                        .accessibilityLabel(isShowingSecret ? "Hide TOTP secret" : "Show TOTP secret")
                }
            }

            HStack(spacing: 8) {
                Button {
                    isShowingScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }

                Text("Scan the QR code from your authenticator app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("OTP placement", selection: $otpPlacement) {
                Text("Append").tag(OTPPlacement.append)
                Text("Prepend").tag(OTPPlacement.prepend)
            }

            TextField("OTP separator", text: $otpSeparator, prompt: Text("Optional"))
                .autocorrectionDisabled()
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $isAdvancedExpanded) {
                Picker("Digits", selection: $otpDigits) {
                    Text("6").tag(6)
                    Text("7").tag(7)
                    Text("8").tag(8)
                }

                Picker("Period", selection: $otpPeriod) {
                    Text("30 seconds").tag(30)
                    Text("60 seconds").tag(60)
                    if otpPeriod != 30 && otpPeriod != 60 {
                        Text("\(otpPeriod) seconds").tag(otpPeriod)
                    }
                }

                Picker("Algorithm", selection: $otpAlgorithm) {
                    Text("SHA1").tag("SHA1")
                    Text("SHA256").tag("SHA256")
                    Text("SHA512").tag("SHA512")
                }
            }
        }
    }

    private var verificationSection: some View {
        Section("Verification") {
            VStack(alignment: .leading, spacing: 8) {
                Text(displayedCode)
                    .font(.system(size: 34, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel(displayedCodeAccessibilityLabel)

                if !hasVerificationSecret {
                    Label(
                        "Enter your TOTP secret to generate a verification code.",
                        systemImage: "info.circle"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let verificationError {
                    Label(verificationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("\(secondsRemaining) seconds remaining", systemImage: "clock")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("Compare this code with the code in your authenticator app.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var accessibilitySection: some View {
        Section("Accessibility") {
            LabeledContent("Permission") {
                Label(
                    isAccessibilityTrusted ? "Granted" : "Not granted",
                    systemImage: isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.primary)
            }

            HStack(spacing: 8) {
                Button("Request Permission", action: requestAccessibilityPermission)
                Button("Open System Settings") {
                    AccessibilityPermission.openSystemSettings()
                }
            }

            HStack(spacing: 8) {
                Button("Diagnostic Report", action: runDiagnosticReport)
                    .disabled(isRunningDiagnostic)

                if isRunningDiagnostic {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if !isAccessibilityTrusted {
                Text("Accessibility access lets OneTapVPN operate the GlobalProtect login window.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let diagnosticMessage {
                Label(diagnosticMessage, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let diagnosticError {
                Label(diagnosticError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var automationSection: some View {
        Section("Automation") {
            Toggle("Auto-reconnect", isOn: $vpnController.autoReconnect)
            Toggle("Connect at login", isOn: $vpnController.connectAtLogin)
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .disabled(isUpdatingLaunchAtLogin)

            if isUpdatingLaunchAtLogin {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating launch item...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if let launchAtLoginError {
                Label(launchAtLoginError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if let feedbackMessage {
                Label(
                    feedbackMessage,
                    systemImage: isFeedbackError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("Save", action: saveCredentials)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)

                Button("Test Connection", action: testConnection)
                    .disabled(vpnController.isBusy)
            }

            HStack(spacing: 8) {
                Button("Disconnect", action: disconnect)
                    .disabled(!vpnController.status.isConnected || vpnController.isBusy)

                Button("Delete Credentials", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        }
    }

    private var statusSymbolName: String {
        switch vpnController.status {
        case .connected:
            return "checkmark.shield.fill"
        case .connecting, .disconnecting:
            return "arrow.triangle.2.circlepath"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .unknown, .disconnected:
            return "shield"
        }
    }

    private var statusTint: Color {
        switch vpnController.status {
        case .connected:
            return .green
        case .connecting, .disconnecting:
            return .orange
        case .failed:
            return .red
        case .unknown, .disconnected:
            return .secondary
        }
    }

    private var hasVerificationSecret: Bool {
        !totpSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayedCode: String {
        if !hasVerificationSecret || generatedCode.isEmpty {
            return "------"
        }
        return generatedCode
    }

    private var displayedCodeAccessibilityLabel: String {
        if !hasVerificationSecret || generatedCode.isEmpty {
            return "No verification code available."
        }
        return "Verification code \(generatedCode)."
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { isLaunchAtLoginEnabled },
            set: { newValue in
                isLaunchAtLoginEnabled = newValue
                updateLaunchAtLogin(newValue)
            }
        )
    }

    private func loadCredentialsIfNeeded() {
        guard !hasLoadedCredentials else {
            return
        }
        hasLoadedCredentials = true
        isAccessibilityTrusted = AccessibilityPermission.isTrusted
        isLaunchAtLoginEnabled = loginItemController.isEnabled

        if let credentials = vpnController.loadCredentials() {
            portal = credentials.portal
            username = credentials.username
            password = credentials.password
            totpSecret = credentials.totpSecret
            otpPlacement = credentials.otpPlacement
            otpSeparator = credentials.otpSeparator
            otpDigits = credentials.otpDigits
            otpPeriod = credentials.otpPeriod
            otpAlgorithm = credentials.otpAlgorithm
        }

        refreshVerification()
    }

    private func runVerificationTimer() async {
        refreshVerification()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }
            refreshVerification()
        }
    }

    private func refreshVerification() {
        isAccessibilityTrusted = AccessibilityPermission.isTrusted

        let secret = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            generatedCode = ""
            secondsRemaining = 0
            verificationError = nil
            return
        }

        do {
            let now = Date()
            generatedCode = try totpGenerator.generateCode(
                secret: secret,
                digits: otpDigits,
                period: otpPeriod,
                algorithm: otpAlgorithm,
                date: now
            )
            secondsRemaining = totpGenerator.secondsRemaining(
                secret: secret,
                digits: otpDigits,
                period: otpPeriod,
                algorithm: otpAlgorithm,
                date: now
            )
            verificationError = nil
        } catch {
            generatedCode = ""
            secondsRemaining = 0
            verificationError = error.localizedDescription
        }
    }

    private func requestAccessibilityPermission() {
        AccessibilityPermission.requestIfNeeded()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            isAccessibilityTrusted = AccessibilityPermission.isTrusted
        }
    }

    private func runDiagnosticReport() {
        guard !isRunningDiagnostic else {
            return
        }

        isRunningDiagnostic = true
        diagnosticMessage = nil
        diagnosticError = nil

        Task { @MainActor in
            defer {
                isRunningDiagnostic = false
            }

            await Task.yield()

            do {
                let reportURL = try GlobalProtectAutomation().dumpAccessibilityTree()
                diagnosticMessage = "Diagnostic report created and shown in Finder."
                NSWorkspace.shared.activateFileViewerSelecting([reportURL])
            } catch {
                diagnosticError = error.localizedDescription
            }
        }
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        guard !isUpdatingLaunchAtLogin else {
            return
        }

        launchAtLoginError = nil
        isUpdatingLaunchAtLogin = true

        Task { @MainActor in
            do {
                try await loginItemController.setEnabled(isEnabled)
                isLaunchAtLoginEnabled = loginItemController.isEnabled
            } catch {
                isLaunchAtLoginEnabled = loginItemController.isEnabled
                launchAtLoginError = error.localizedDescription
            }
            isUpdatingLaunchAtLogin = false
        }
    }

    private func makeCredentials() -> Credentials? {
        let trimmedPortal = portal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedPortal.isEmpty,
              !trimmedUsername.isEmpty,
              !password.isEmpty,
              !trimmedSecret.isEmpty else {
            return nil
        }

        return Credentials(
            portal: trimmedPortal,
            username: trimmedUsername,
            password: password,
            totpSecret: trimmedSecret,
            otpPlacement: otpPlacement,
            otpSeparator: otpSeparator,
            otpDigits: otpDigits,
            otpPeriod: otpPeriod,
            otpAlgorithm: otpAlgorithm
        )
    }

    private func applyTrimmedValues(_ credentials: Credentials) {
        portal = credentials.portal
        username = credentials.username
        totpSecret = credentials.totpSecret
    }

    private func applyScannedPayload(_ payload: String) throws {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPayload.isEmpty else {
            throw QRCodeScanError.emptyPayload
        }

        if trimmedPayload.lowercased().hasPrefix("otpauth-migration://") {
            throw QRCodeScanError.unsupportedMigrationCode
        }

        if trimmedPayload.lowercased().hasPrefix("otpauth://") {
            let provisioning = try totpGenerator.parseProvisioningURI(
                trimmedPayload,
                defaultDigits: otpDigits,
                defaultPeriod: otpPeriod,
                defaultAlgorithm: otpAlgorithm
            )
            do {
                _ = try Base32.decode(provisioning.secret)
            } catch {
                throw QRCodeScanError.invalidPayload
            }
            totpSecret = provisioning.secret
            otpDigits = provisioning.digits
            otpPeriod = provisioning.period
            otpAlgorithm = provisioning.algorithm
        } else {
            do {
                _ = try Base32.decode(trimmedPayload)
            } catch {
                throw QRCodeScanError.invalidPayload
            }
            totpSecret = trimmedPayload
        }

        isShowingSecret = false
        refreshVerification()
        setFeedback("QR code scanned.", isError: false)
    }

    private func validateSecret() -> Bool {
        let secret = totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            setFeedback("Enter a TOTP secret.", isError: true)
            return false
        }

        do {
            _ = try totpGenerator.generateCode(
                secret: secret,
                digits: otpDigits,
                period: otpPeriod,
                algorithm: otpAlgorithm,
                date: Date()
            )
            return true
        } catch {
            setFeedback(error.localizedDescription, isError: true)
            return false
        }
    }

    private func saveCredentials() {
        guard validateSecret() else {
            return
        }
        guard let credentials = makeCredentials() else {
            setFeedback("Enter a portal, username, password, and TOTP secret.", isError: true)
            return
        }

        do {
            try vpnController.saveCredentials(credentials)
            applyTrimmedValues(credentials)
            setFeedback("Saved", isError: false)
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    private func testConnection() {
        guard validateSecret() else {
            return
        }
        guard let credentials = makeCredentials() else {
            setFeedback("Enter a portal, username, password, and TOTP secret.", isError: true)
            return
        }

        do {
            try vpnController.saveCredentials(credentials)
            applyTrimmedValues(credentials)
            setFeedback("Credentials saved. Testing connection.", isError: false)
            vpnController.testConnection()
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    private func disconnect() {
        vpnController.disconnect()
        setFeedback("Disconnecting.", isError: false)
    }

    private func deleteCredentials() {
        do {
            try vpnController.deleteCredentials()
            let empty = Credentials.empty
            portal = empty.portal
            username = empty.username
            password = empty.password
            totpSecret = empty.totpSecret
            otpPlacement = empty.otpPlacement
            otpSeparator = empty.otpSeparator
            otpDigits = empty.otpDigits
            otpPeriod = empty.otpPeriod
            otpAlgorithm = empty.otpAlgorithm
            isShowingSecret = false
            generatedCode = ""
            secondsRemaining = 0
            verificationError = nil
            setFeedback("Credentials deleted.", isError: false)
        } catch {
            setFeedback(error.localizedDescription, isError: true)
        }
    }

    private func setFeedback(_ message: String, isError: Bool) {
        feedbackMessage = message
        isFeedbackError = isError
    }
}
