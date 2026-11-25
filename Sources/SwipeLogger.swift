import os

enum SwipeLogger {
    private static let logger = Logger(subsystem: "local.SafariQuickSearch", category: "Swipe")

    static func debug(_ message: @autoclosure () -> String) {
        #if SQS_Debug
        let text = message()
        logger.debug("\(text, privacy: .public)")
        #endif
    }
}
