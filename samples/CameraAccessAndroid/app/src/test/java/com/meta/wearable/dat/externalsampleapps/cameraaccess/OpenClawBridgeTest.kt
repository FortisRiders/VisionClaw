package com.meta.wearable.dat.externalsampleapps.cameraaccess

import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.OpenClawBridge
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenClawBridgeTest {

    @Test
    fun `default session key is agent main main`() {
        val bridge = OpenClawBridge()
        assertEquals("agent:main:main", bridge.currentSessionKey)
    }

    @Test
    fun `switchToSession updates currentSessionKey`() {
        val bridge = OpenClawBridge()
        bridge.switchToSession("agent:main:chat-abcd1234")
        assertEquals("agent:main:chat-abcd1234", bridge.currentSessionKey)
    }

    @Test
    fun `switchToSession with history loads messages`() {
        val bridge = OpenClawBridge()
        val history = listOf(
            mapOf("role" to "user", "content" to "Hello"),
            mapOf("role" to "assistant", "content" to "Hi there"),
        )
        bridge.switchToSession("agent:main:chat-test", history)
        assertEquals("agent:main:chat-test", bridge.currentSessionKey)
    }

    @Test
    fun `switchProfile resets to default session key`() {
        val bridge = OpenClawBridge()
        bridge.switchToSession("agent:main:chat-custom")
        bridge.switchProfile()
        assertEquals("agent:main:main", bridge.currentSessionKey)
    }

    @Test
    fun `generateNewChatSessionKey returns chat format`() = runTest {
        val bridge = OpenClawBridge()
        val key = bridge.generateNewChatSessionKey()
        assertTrue(key.startsWith("agent:main:chat-"))
        assertEquals(8, key.removePrefix("agent:main:chat-").length)
    }

    @Test
    fun `resetSession keeps session key`() {
        val bridge = OpenClawBridge()
        bridge.switchToSession("agent:main:chat-test1234")
        bridge.resetSession()
        assertEquals("agent:main:chat-test1234", bridge.currentSessionKey)
    }
}
