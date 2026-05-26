package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import java.util.UUID

data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: Role,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
) {
    enum class Role { USER, ASSISTANT }
}
