import ActivityKit
import Foundation

struct JarvisActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum JarvisState: String, Codable, Hashable {
            case idle, listening, sending, speaking
        }
        var jarvisState: JarvisState
        var showLiveButton: Bool
        var isLiveStreaming: Bool
    }
}
