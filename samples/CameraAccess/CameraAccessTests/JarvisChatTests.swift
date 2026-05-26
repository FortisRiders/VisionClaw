import XCTest
@testable import CameraAccess

final class JarvisChatTests: XCTestCase {

    // MARK: - makeId

    func test_makeId_returnsEightCharacters() {
        XCTAssertEqual(JarvisChat.makeId().count, 8)
    }

    func test_makeId_isLowercaseHex() {
        let id = JarvisChat.makeId()
        let allowedCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            id.unicodeScalars.allSatisfy { allowedCharacters.contains($0) },
            "makeId() should return only lowercase hex characters, got: \(id)"
        )
    }

    func test_makeId_twoCallsReturnDifferentValues() {
        let first = JarvisChat.makeId()
        let second = JarvisChat.makeId()
        XCTAssertNotEqual(first, second)
    }

    // MARK: - autoTitle

    func test_autoTitle_emptyString_returnsNewChat() {
        XCTAssertEqual(JarvisChat.autoTitle(from: ""), "New Chat")
    }

    func test_autoTitle_singleWord_returnsThatWord() {
        XCTAssertEqual(JarvisChat.autoTitle(from: "Hello"), "Hello")
    }

    func test_autoTitle_fiveWords_returnsAllFive() {
        let input = "one two three four five"
        XCTAssertEqual(JarvisChat.autoTitle(from: input), "one two three four five")
    }

    func test_autoTitle_sixWords_returnsOnlyFirstFive() {
        let input = "one two three four five six"
        XCTAssertEqual(JarvisChat.autoTitle(from: input), "one two three four five")
    }

    func test_autoTitle_leadingAndTrailingWhitespace_stripped() {
        let input = "  hello world  "
        let result = JarvisChat.autoTitle(from: input)
        XCTAssertFalse(result.hasPrefix(" "))
        XCTAssertFalse(result.hasSuffix(" "))
        XCTAssertTrue(result.contains("hello"))
        XCTAssertTrue(result.contains("world"))
    }

    func test_autoTitle_multipleSpacesBetweenWords_handledCorrectly() {
        let input = "one  two   three"
        let result = JarvisChat.autoTitle(from: input)
        XCTAssertTrue(result.contains("one"))
        XCTAssertTrue(result.contains("two"))
        XCTAssertTrue(result.contains("three"))
        XCTAssertFalse(result.contains("  "), "Result should not contain double spaces")
    }
}
