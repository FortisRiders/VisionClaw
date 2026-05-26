package com.meta.wearable.dat.externalsampleapps.cameraaccess

import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.JarvisChat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JarvisChatTest {

    @Test
    fun `makeId returns 8 character lowercase hex string`() {
        val id = JarvisChat.makeId()
        assertEquals(8, id.length)
        assertTrue(id.all { it.isLetterOrDigit() })
        assertEquals(id, id.lowercase())
    }

    @Test
    fun `makeId generates unique values`() {
        val ids = (1..100).map { JarvisChat.makeId() }.toSet()
        assertEquals(100, ids.size)
    }

    @Test
    fun `autoTitle takes first 5 words`() {
        val result = JarvisChat.autoTitle("one two three four five six seven")
        assertEquals("one two three four five", result)
    }

    @Test
    fun `autoTitle returns New Chat for empty string`() {
        val result = JarvisChat.autoTitle("")
        assertEquals("New Chat", result)
    }

    @Test
    fun `autoTitle returns New Chat for blank string`() {
        val result = JarvisChat.autoTitle("   ")
        assertEquals("New Chat", result)
    }

    @Test
    fun `autoTitle handles single word`() {
        val result = JarvisChat.autoTitle("Hello")
        assertEquals("Hello", result)
    }

    @Test
    fun `data class copy works correctly`() {
        val original = JarvisChat(
            id = "abc12345",
            title = "Original",
            previewText = "Preview",
            sessionKey = "agent:main:glass",
        )
        val copied = original.copy(title = "Updated")
        assertEquals("Updated", copied.title)
        assertEquals(original.id, copied.id)
        assertEquals(original.sessionKey, copied.sessionKey)
    }

    @Test
    fun `default createdAt is recent`() {
        val before = System.currentTimeMillis()
        val chat = JarvisChat(id = "test", title = "T", previewText = "", sessionKey = "k")
        val after = System.currentTimeMillis()
        assertTrue(chat.createdAt in before..after)
    }

    @Test
    fun `data class equality based on content`() {
        val a = JarvisChat(id = "abc", title = "T", previewText = "", createdAt = 1000L, updatedAt = 1000L, sessionKey = "k")
        val b = JarvisChat(id = "abc", title = "T", previewText = "", createdAt = 1000L, updatedAt = 1000L, sessionKey = "k")
        assertEquals(a, b)
    }

    @Test
    fun `data class inequality when id differs`() {
        val a = JarvisChat(id = "abc", title = "T", previewText = "", createdAt = 1000L, updatedAt = 1000L, sessionKey = "k")
        val b = JarvisChat(id = "xyz", title = "T", previewText = "", createdAt = 1000L, updatedAt = 1000L, sessionKey = "k")
        assertNotEquals(a, b)
    }
}
