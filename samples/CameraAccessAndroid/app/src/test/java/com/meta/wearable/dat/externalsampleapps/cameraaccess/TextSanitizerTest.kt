package com.meta.wearable.dat.externalsampleapps.cameraaccess

import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.TextSanitizer
import org.junit.Assert.assertEquals
import org.junit.Test

class TextSanitizerTest {

    @Test
    fun `removes fenced code blocks`() {
        val input = "Here is code:\n```kotlin\nval x = 1\n```\nDone."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Here is code: Done.", result)
    }

    @Test
    fun `replaces URLs with link`() {
        val input = "Check out https://example.com for more info."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Check out link for more info.", result)
    }

    @Test
    fun `replaces http URLs`() {
        val input = "Visit http://example.com now."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Visit link now.", result)
    }

    @Test
    fun `strips bold markers`() {
        val input = "This is **bold** text."
        val result = TextSanitizer.sanitize(input)
        assertEquals("This is bold text.", result)
    }

    @Test
    fun `strips italic markers`() {
        val input = "This is *italic* text."
        val result = TextSanitizer.sanitize(input)
        assertEquals("This is italic text.", result)
    }

    @Test
    fun `strips underscore bold`() {
        val input = "This is __bold__ text."
        val result = TextSanitizer.sanitize(input)
        assertEquals("This is bold text.", result)
    }

    @Test
    fun `strips underscore italic`() {
        val input = "This is _italic_ text."
        val result = TextSanitizer.sanitize(input)
        assertEquals("This is italic text.", result)
    }

    @Test
    fun `strips inline code`() {
        val input = "Use `println` to print."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Use println to print.", result)
    }

    @Test
    fun `strips heading markers`() {
        val input = "# Title\nBody text."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Title Body text.", result)
    }

    @Test
    fun `strips level 3 heading`() {
        val input = "### Section\nContent."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Section Content.", result)
    }

    @Test
    fun `collapses multiple spaces`() {
        val input = "Hello   world   foo."
        val result = TextSanitizer.sanitize(input)
        assertEquals("Hello world foo.", result)
    }

    @Test
    fun `trims leading and trailing whitespace`() {
        val input = "   Hello world   "
        val result = TextSanitizer.sanitize(input)
        assertEquals("Hello world", result)
    }

    @Test
    fun `handles plain text unchanged`() {
        val input = "Hello, how are you today?"
        val result = TextSanitizer.sanitize(input)
        assertEquals("Hello, how are you today?", result)
    }

    @Test
    fun `handles empty string`() {
        val result = TextSanitizer.sanitize("")
        assertEquals("", result)
    }

    @Test
    fun `handles combined markdown`() {
        val input = "## Heading\n**Bold** and *italic* with `code` and https://example.com"
        val result = TextSanitizer.sanitize(input)
        assertEquals("Heading Bold and italic with code and link", result)
    }

    @Test
    fun `collapses newlines into spaces`() {
        val input = "Line one\n\nLine two"
        val result = TextSanitizer.sanitize(input)
        assertEquals("Line one Line two", result)
    }
}
