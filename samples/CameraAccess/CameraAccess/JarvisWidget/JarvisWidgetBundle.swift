import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

// Mirror of the main app's JarvisActivityAttributes — must match exactly.
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

@main
struct JarvisWidgetBundle: WidgetBundle {
    var body: some Widget {
        JarvisWidget()
    }
}
