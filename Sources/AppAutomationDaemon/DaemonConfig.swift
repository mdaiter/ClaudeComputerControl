import Foundation

struct DaemonConfig {
    let socketPath: String
    let dryRun: Bool
    let safariHelperPath: String?
    let messagesHelperPath: String?

    static func fromEnvironment() -> DaemonConfig {
        let env = ProcessInfo.processInfo.environment
        let socketPath = env["APP_AUTOMATION_SOCKET"] ?? "/tmp/app-automation.sock"
        let dryRun = env["APP_AUTOMATION_DRY_RUN"] == "1"
        return DaemonConfig(
            socketPath: socketPath,
            dryRun: dryRun,
            safariHelperPath: env["APP_AUTOMATION_SAFARI_HELPER"],
            messagesHelperPath: env["APP_AUTOMATION_MESSAGES_HELPER"]
        )
    }
}
