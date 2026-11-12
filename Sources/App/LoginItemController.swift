import Foundation

enum LoginItemError: LocalizedError {
    case executableUnavailable
    case fileOperationFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            return "The OneTapVPN executable could not be located."
        case .fileOperationFailed(let message):
            return message.isEmpty ? "The launch agent file could not be updated." : message
        case .commandFailed(let message):
            return message.isEmpty ? "The launch agent command failed." : message
        }
    }
}

final class LoginItemController {
    private static let label = "com.erendt.onetapvpn"
    private static let launchCtlPath = "/bin/launchctl"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    var isEnabled: Bool {
        fileManager.fileExists(atPath: agentURL.path)
    }

    func setEnabled(_ isEnabled: Bool) async throws {
        if isEnabled {
            try await install()
        } else {
            try await uninstall()
        }
    }

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    private var agentURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
    }

    private func install() async throws {
        guard let executableURL = Bundle.main.executableURL else {
            throw LoginItemError.executableUnavailable
        }

        let propertyList = try Self.makePropertyList(executablePath: executableURL.path)
        let agentURL = self.agentURL
        let launchAgentsDirectory = self.launchAgentsDirectory

        try await Task.detached(priority: .userInitiated) {
            do {
                try FileManager.default.createDirectory(
                    at: launchAgentsDirectory,
                    withIntermediateDirectories: true
                )
                try propertyList.write(to: agentURL, options: .atomic)
            } catch {
                throw LoginItemError.fileOperationFailed(error.localizedDescription)
            }

            guard !Self.isServiceLoaded else {
                return
            }

            do {
                try Self.runLaunchCtl(arguments: ["bootstrap", Self.serviceTarget, agentURL.path])
            } catch {
                try? FileManager.default.removeItem(at: agentURL)
                throw error
            }
        }.value
    }

    private func uninstall() async throws {
        let agentURL = self.agentURL

        try await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: agentURL.path) else {
                return
            }

            do {
                try FileManager.default.removeItem(at: agentURL)
            } catch {
                throw LoginItemError.fileOperationFailed(error.localizedDescription)
            }

            _ = try? Self.runLaunchCtl(arguments: ["bootout", Self.serviceIdentifier])
        }.value
    }

    private static var serviceTarget: String {
        "gui/\(getuid())"
    }

    private static var serviceIdentifier: String {
        "\(serviceTarget)/\(label)"
    }

    private static var isServiceLoaded: Bool {
        (try? runLaunchCtl(arguments: ["print", serviceIdentifier])) != nil
    }

    private static func makePropertyList(executablePath: String) throws -> Data {
        let propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]

        do {
            return try PropertyListSerialization.data(
                fromPropertyList: propertyList,
                format: .xml,
                options: 0
            )
        } catch {
            throw LoginItemError.fileOperationFailed(error.localizedDescription)
        }
    }

    private static func runLaunchCtl(arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchCtlPath)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            throw LoginItemError.commandFailed(error.localizedDescription)
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if message.isEmpty {
                throw LoginItemError.commandFailed("launchctl exited with status \(process.terminationStatus).")
            }
            throw LoginItemError.commandFailed(message)
        }
    }
}
