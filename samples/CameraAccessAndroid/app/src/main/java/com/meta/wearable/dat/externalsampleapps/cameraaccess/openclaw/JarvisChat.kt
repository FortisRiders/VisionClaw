package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import java.util.UUID

data class JarvisChat(
    val id: String,
    var title: String,
    var previewText: String,
    val createdAt: Long = System.currentTimeMillis(),
    var updatedAt: Long = System.currentTimeMillis(),
    val sessionKey: String,
) {
    companion object {
        fun makeId(): String =
            UUID.randomUUID().toString().replace("-", "").take(8).lowercase()

        fun autoTitle(text: String): String {
            val words = text.trim().split("\\s+".toRegex()).take(5).joinToString(" ")
            return words.ifEmpty { "New Chat" }
        }
    }
}
