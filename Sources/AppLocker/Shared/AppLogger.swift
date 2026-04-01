import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.mirxa.AppLocker"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let crypto = Logger(subsystem: subsystem, category: "crypto")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let intruder = Logger(subsystem: subsystem, category: "intruder")
    static let cloud = Logger(subsystem: subsystem, category: "cloud")
}
