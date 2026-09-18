package org.duckdns.lhfser.aiaccounting.core.ai

import java.net.URI

internal fun canonicalizePlatformGemmaBaseUrl(raw: String): String {
    val trimmed = raw.trim()
    val uri = runCatching { URI(trimmed) }.getOrNull()
    require(
        uri != null &&
            uri.scheme.equals("https", ignoreCase = true) &&
            !uri.host.isNullOrBlank() &&
            uri.userInfo == null &&
            uri.query == null &&
            uri.fragment == null &&
            (uri.path.isNullOrEmpty() || uri.path == "/")
    ) {
        "請先在設定輸入有效的 HTTPS Gemma 服務網址。"
    }

    val port = if (uri.port == 443) -1 else uri.port
    return URI("https", null, uri.host.lowercase(), port, null, null, null).toASCIIString()
}

internal fun <T> registerAgainstStableBaseUrl(
    rawBaseUrl: String,
    register: (registeredBaseUrl: String) -> T,
    saveRegistration: (response: T, registeredBaseUrl: String) -> Unit
): T {
    val registeredBaseUrl = canonicalizePlatformGemmaBaseUrl(rawBaseUrl)
    val response = register(registeredBaseUrl)
    saveRegistration(response, registeredBaseUrl)
    return response
}
