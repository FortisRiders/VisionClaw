import Foundation

struct JarvisChat: Identifiable, Codable {
    let id: String
    var title: String
    var previewText: String
    var createdAt: Date
    var updatedAt: Date
    var sessionKey: String

    static func makeId() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased())
    }

    static func autoTitle(from text: String) -> String {
        let words = text.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? "New Chat" : words
    }
}
