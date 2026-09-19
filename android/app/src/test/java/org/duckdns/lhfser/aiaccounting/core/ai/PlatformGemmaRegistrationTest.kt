package org.duckdns.lhfser.aiaccounting.core.ai

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PlatformGemmaRegistrationTest {
    @Test
    fun registrationUsesOneImmutableCanonicalBaseUrlForRequestAndSavedOrigin() {
        var visibleBaseUrl = "  https://EXAMPLE.test:443/  "
        var requestBaseUrl: String? = null
        var savedBaseUrl: String? = null

        registerAgainstStableBaseUrl(
            rawBaseUrl = visibleBaseUrl,
            register = { registeredBaseUrl ->
                requestBaseUrl = registeredBaseUrl
                visibleBaseUrl = "https://other.example"
                "registration-response"
            },
            saveRegistration = { _, registeredBaseUrl ->
                savedBaseUrl = registeredBaseUrl
            }
        )

        assertEquals("https://example.test", requestBaseUrl)
        assertEquals("https://example.test", savedBaseUrl)
        assertEquals("https://other.example", visibleBaseUrl)
    }

    @Test
    fun registrationRejectsNonHttpsOrPathBaseUrls() {
        assertThrows(IllegalArgumentException::class.java) {
            canonicalizePlatformGemmaBaseUrl("http://example.test")
        }
        assertThrows(IllegalArgumentException::class.java) {
            canonicalizePlatformGemmaBaseUrl("https://example.test/api")
        }
    }
}
