import XCTest
@testable import CameraAccess

final class TextSanitizerTests: XCTestCase {

    func test_fencedCodeBlock_isRemoved() {
        let input = "Here is some code:\n```\nlet x = 1\n```\nDone."
        let result = TextSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("```"))
        XCTAssertFalse(result.contains("let x = 1"))
    }

    func test_fencedCodeBlock_multiline_isRemovedEntirely() {
        let input = "Intro\n```swift\nfunc foo() {\n    return 42\n}\n```\nOutro"
        let result = TextSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("func foo"))
        XCTAssertTrue(result.contains("Intro"))
        XCTAssertTrue(result.contains("Outro"))
    }

    func test_httpURL_replacedWithLink() {
        let result = TextSanitizer.sanitize("Visit http://example.com for info.")
        XCTAssertFalse(result.contains("http://"))
        XCTAssertTrue(result.contains("link"))
    }

    func test_httpsURL_replacedWithLink() {
        let result = TextSanitizer.sanitize("See https://example.com/path?q=1 here.")
        XCTAssertFalse(result.contains("https://"))
        XCTAssertTrue(result.contains("link"))
    }

    func test_boldMarkdown_stripped() {
        let result = TextSanitizer.sanitize("This is **bold** text.")
        XCTAssertEqual(result, "This is bold text.")
    }

    func test_italicMarkdown_stripped() {
        let result = TextSanitizer.sanitize("This is *italic* text.")
        XCTAssertEqual(result, "This is italic text.")
    }

    func test_doubleUnderscoreMarkdown_stripped() {
        let result = TextSanitizer.sanitize("This is __underline__ text.")
        XCTAssertEqual(result, "This is underline text.")
    }

    func test_singleUnderscoreMarkdown_stripped() {
        let result = TextSanitizer.sanitize("This is _emphasis_ text.")
        XCTAssertEqual(result, "This is emphasis text.")
    }

    func test_inlineCode_backtickStripped() {
        let result = TextSanitizer.sanitize("Call the `foo()` function.")
        XCTAssertEqual(result, "Call the foo() function.")
    }

    func test_h1Heading_markerRemoved() {
        let result = TextSanitizer.sanitize("# Title")
        XCTAssertEqual(result, "Title")
    }

    func test_h2Heading_markerRemoved() {
        let result = TextSanitizer.sanitize("## Sub")
        XCTAssertEqual(result, "Sub")
    }

    func test_multiLevelHeading_markerRemoved() {
        let result = TextSanitizer.sanitize("### Deep Section")
        XCTAssertEqual(result, "Deep Section")
    }

    func test_consecutiveNewlines_collapsedToSingleSpace() {
        let result = TextSanitizer.sanitize("Line one\n\nLine two\n\n\nLine three")
        XCTAssertFalse(result.contains("\n\n"))
        XCTAssertTrue(result.contains("Line one"))
        XCTAssertTrue(result.contains("Line two"))
        XCTAssertTrue(result.contains("Line three"))
    }

    func test_emptyString_returnsEmpty() {
        XCTAssertEqual(TextSanitizer.sanitize(""), "")
    }

    func test_plainText_returnedUnchanged() {
        let plain = "Just a normal sentence with no markdown."
        XCTAssertEqual(TextSanitizer.sanitize(plain), plain)
    }

    func test_mixed_boldAndURL_bothHandled() {
        let input = "Check **this** at https://example.com now."
        let result = TextSanitizer.sanitize(input)
        XCTAssertFalse(result.contains("**"))
        XCTAssertFalse(result.contains("https://"))
        XCTAssertTrue(result.contains("this"))
        XCTAssertTrue(result.contains("link"))
    }
}
