@preconcurrency import AVFoundation
import AppKit
import Combine
import CoreMedia
import SwiftUI
import Vision

enum QRCodeScanError: LocalizedError {
    case emptyPayload
    case invalidPayload
    case unsupportedMigrationCode

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "The QR code did not contain any data."
        case .invalidPayload:
            return "This is not a TOTP authenticator QR code."
        case .unsupportedMigrationCode:
            return "Google Authenticator export codes are not supported. Scan a standard TOTP QR code."
        }
    }
}

struct QRCodeScannerView: View {
    let onPayload: (String) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var scanner = QRCodeScannerController()
    @State private var scanError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            preview
            if let scanError {
                Label(scanError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            controls
        }
        .padding(24)
        .frame(width: 520)
        .task {
            await scanner.start()
        }
        .onDisappear {
            scanner.stop()
        }
        .onReceive(scanner.$scannedPayload) { payload in
            guard let payload else {
                return
            }
            scanError = nil
            do {
                try onPayload(payload)
                dismiss()
            } catch {
                scanError = error.localizedDescription
                scanner.resume()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scan Authenticator QR Code")
                .font(.title2.weight(.semibold))
            Text("Point the camera at the QR code from your authenticator app.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var preview: some View {
        ZStack {
            CameraPreviewView(session: scanner.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)

            if scanner.state == .ready {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 210, height: 210)
                    .shadow(radius: 2)
                    .accessibilityHidden(true)
            } else {
                scannerStateOverlay
            }
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var scannerStateOverlay: some View {
        switch scanner.state {
        case .idle, .requestingPermission:
            scannerMessage {
                ProgressView()
                Text("Starting camera...")
            }
        case .unauthorized:
            scannerMessage {
                Image(systemName: "camera.fill")
                    .font(.title2)
                Text("Camera access is required to scan the QR code.")
                    .font(.headline)
                Text("Enable OneTapVPN in System Settings > Privacy & Security > Camera.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .unavailable:
            scannerMessage {
                Image(systemName: "video.slash")
                    .font(.title2)
                Text("No camera is available.")
                    .font(.headline)
                Text("Paste the TOTP secret or otpauth URI instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            scannerMessage {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                Text(message)
                    .font(.callout)
            }
        case .ready:
            EmptyView()
        }
    }

    private func scannerMessage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 8) {
            content()
        }
        .multilineTextAlignment(.center)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(24)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            if scanner.state == .unauthorized {
                Button("Try Again") {
                    Task {
                        await scanner.start()
                    }
                }
                Button("Open System Settings") {
                    scanner.openCameraSettings()
                }
            }
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}

@MainActor
final class QRCodeScannerController: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case requestingPermission
        case ready
        case unauthorized
        case unavailable
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var scannedPayload: String?

    let session = AVCaptureSession()

    private let cameraQueue = DispatchQueue(label: "com.erendt.onetapvpn.qr-code-scanner")
    private var isConfigured = false
    private var isActive = false

    func start() async {
        isActive = true
        guard !isConfigured else {
            resume()
            return
        }

        state = .requestingPermission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            let isGranted = await requestCameraAccess()
            guard isActive else {
                return
            }
            guard isGranted else {
                state = .unauthorized
                return
            }
            configureSession()
        case .denied, .restricted:
            state = .unauthorized
        @unknown default:
            state = .failed("Camera access is not available.")
        }
    }

    func stop() {
        isActive = false
        cameraQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func resume() {
        scannedPayload = nil
        guard isActive, isConfigured else {
            return
        }
        cameraQueue.async { [session] in
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    func openCameraSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        ) else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    private func requestCameraAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private func configureSession() {
        guard isActive else {
            return
        }
        guard !isConfigured else {
            resume()
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            state = .unavailable
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            session.beginConfiguration()
            session.sessionPreset = .high

            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                state = .failed("The camera could not be configured.")
                return
            }

            session.addInput(input)
            session.addOutput(output)
            session.commitConfiguration()

            output.setSampleBufferDelegate(self, queue: cameraQueue)

            isConfigured = true
            state = .ready
            cameraQueue.async { [session] in
                session.startRunning()
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func handleScannedPayload(_ payload: String) {
        guard isActive, scannedPayload == nil else {
            return
        }
        scannedPayload = payload
        cameraQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }
}

extension QRCodeScannerController: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return
        }

        guard let observations = request.results,
              let payload = observations.compactMap(\.payloadStringValue).first(where: { !$0.isEmpty }) else {
            return
        }

        Task { @MainActor [weak self] in
            self?.handleScannedPayload(payload)
        }
    }
}

private struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let previewView = CameraPreviewNSView()
        previewView.previewLayer.session = session
        return previewView
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.previewLayer.session = session
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: ()) {
        nsView.previewLayer.session = nil
    }
}

private final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = previewLayer
        previewLayer.videoGravity = .resizeAspect
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
