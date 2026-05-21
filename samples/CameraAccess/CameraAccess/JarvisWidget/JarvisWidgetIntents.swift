import AppIntents
import Foundation

private func postDarwinNotification(_ name: String) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFNotificationName(name as CFString),
        nil, nil, true
    )
}

struct StopJarvisIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Jarvis"
    static let description = IntentDescription("Stops Jarvis live listening mode.")

    func perform() async throws -> some IntentResult {
        postDarwinNotification("com.xiaoanliu.VisionClaw.widget.stopJarvis")
        return .result()
    }
}

struct StopSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Session"
    static let description = IntentDescription("Stops Jarvis and ends the stream session.")

    func perform() async throws -> some IntentResult {
        postDarwinNotification("com.xiaoanliu.VisionClaw.widget.stopSession")
        return .result()
    }
}

struct ToggleLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Live"
    static let description = IntentDescription("Opens VisionClaw to toggle live streaming.")
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
