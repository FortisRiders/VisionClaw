package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

object TextSanitizer {
    fun sanitize(text: String): String {
        var result = text

        result = result.replace(Regex("```[\\s\\S]*?```"), "")
        result = result.replace(Regex("https?://\\S+"), "link")

        for (pattern in listOf(
            Regex("\\*\\*(.+?)\\*\\*", setOf(RegexOption.DOT_MATCHES_ALL)),
            Regex("\\*(.+?)\\*", setOf(RegexOption.DOT_MATCHES_ALL)),
            Regex("__(.+?)__", setOf(RegexOption.DOT_MATCHES_ALL)),
            Regex("_(.+?)_", setOf(RegexOption.DOT_MATCHES_ALL)),
            Regex("`(.+?)`", setOf(RegexOption.DOT_MATCHES_ALL)),
        )) {
            result = result.replace(pattern, "$1")
        }

        result = result.replace(Regex("^#{1,6}\\s+", RegexOption.MULTILINE), "")
        result = result.replace(Regex("\\s{2,}"), " ")
        return result.trim()
    }
}
