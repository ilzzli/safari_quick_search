enum SwipeLogger {
    static func debug(_ message: @autoclosure () -> String) {
        #if SQS_Debug
        print("[Swipe] " + message())
        #endif
    }
}
