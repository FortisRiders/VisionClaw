import Foundation

enum TextSanitizer {
    static func sanitize(_ text: String) -> String {
        var result = text

        // Remove fenced code blocks first (before other rules strip their markers)
        result = replace(result, pattern: #"```[\s\S]*?```"#, with: "")

        // Replace URLs with "link" — prevents reading out https://...
        result = replace(result, pattern: #"https?://[^\s]+"#, with: "link")

        // Strip bold and italic markers, preserving inner text
        for pattern in [#"\*\*(.+?)\*\*"#, #"\*(.+?)\*"#, #"__(.+?)__"#, #"_(.+?)_"#, #"`(.+?)`"#] {
            result = replace(result, pattern: pattern, with: "$1", options: .dotMatchesLineSeparators)
        }

        // Strip markdown heading markers (# Title → Title)
        result = replace(result, pattern: #"^#{1,6}\s+"#, with: "", options: .anchorsMatchLines)

        // Collapse multiple whitespace/newlines into a single space
        result = replace(result, pattern: #"\s{2,}"#, with: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(
        _ text: String,
        pattern: String,
        with replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}
