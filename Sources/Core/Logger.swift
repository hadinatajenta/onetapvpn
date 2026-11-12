import os

enum AppLogger {
    private static let logger = Logger(subsystem: "com.erendt.onetapvpn", category: "app")

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
