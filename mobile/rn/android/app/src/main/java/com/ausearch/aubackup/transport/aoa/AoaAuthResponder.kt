package com.ausearch.aubackup.transport.aoa

import org.json.JSONObject
import java.security.MessageDigest

/**
 * Pure Kotlin responder for the desktop's `transport.auth.challenge` envelope.
 *
 * This class is intentionally decoupled from Android APIs so the challenge/response
 * logic can be unit-tested on the JVM. The caller (e.g. `AoaClient`) is responsible
 * for parsing the incoming JSON envelope and encoding the returned response JSON
 * into an AOA frame.
 */
class AoaAuthResponder {

    /**
     * Builds the auth-challenge response for a validated desktop challenge.
     *
     * The response envelope mirrors the iOS USB auth handshake and keeps
     * `"dtis.mobile-pairing.v1"` inside the response body. The caller must encode
     * [responseEnvelopeJson] into an AOA frame using [responseFrameRequestId] as the
     * frame request id; this echoes the padded request id from the incoming challenge
     * frame so the desktop AOA adapter can correlate it.
     *
     * @throws AoaTransportError.AuthRejected if the challenge sid/opt/schema does not match.
     */
    fun respond(
        input: AuthChallengeInput,
        expectedSessionId: String,
        oneTimePasscode: String,
    ): AuthChallengeResponse {
        requireSchema(input.envelopeSchema == MOBILE_TRANSPORT_ENVELOPE_SCHEMA) {
            "unsupported envelope schema: ${input.envelopeSchema}"
        }
        requireSchema(input.operation == AUTH_OPERATION) {
            "unsupported operation: ${input.operation}"
        }
        requireSchema(input.bodySchema == MOBILE_PAIRING_SCHEMA) {
            "unsupported body schema: ${input.bodySchema}"
        }
        if (input.sid != expectedSessionId) {
            throw AoaTransportError.AuthRejected(
                "auth challenge sid does not match the prepared bootstrap session."
            )
        }

        val proof = sha256Hex("$oneTimePasscode${input.rand}")
        val responseEnvelopeJson = buildResponseEnvelope(proof)
        return AuthChallengeResponse(
            responseFrameRequestId = input.frameRequestId,
            responseEnvelopeJson = responseEnvelopeJson,
        )
    }

    private fun requireSchema(condition: Boolean, lazyMessage: () -> String) {
        if (!condition) {
            throw AoaTransportError.InvalidEnvelope(lazyMessage())
        }
    }

    private fun sha256Hex(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(input.toByteArray(Charsets.UTF_8))
        return hash.joinToString("") { "%02x".format(it) }
    }

    private fun buildResponseEnvelope(proof: String): String {
        return JSONObject().apply {
            put("body", JSONObject().apply {
                put("schema", MOBILE_PAIRING_SCHEMA)
                put("status", AUTH_STATUS_ACCEPTED)
                put("proof", proof)
            })
            put("request_id", AUTH_REQUEST_ID)
            put("schema", MOBILE_TRANSPORT_ENVELOPE_SCHEMA)
            put("status_code", 200)
        }.toString()
    }

    companion object {
        const val MOBILE_TRANSPORT_ENVELOPE_SCHEMA: String = "dtis.mobile-transport.v1"
        const val MOBILE_PAIRING_SCHEMA: String = "dtis.mobile-pairing.v1"
        const val AUTH_OPERATION: String = "transport.auth.challenge"
        const val AUTH_REQUEST_ID: String = "auth-challenge"
        const val AUTH_STATUS_ACCEPTED: String = "accepted"
    }
}

/**
 * Normalized representation of an incoming auth-challenge envelope.
 */
data class AuthChallengeInput(
    val frameRequestId: String,
    val envelopeSchema: String,
    val operation: String,
    val bodySchema: String,
    val sid: String,
    val rand: String,
)

/**
 * Result of [AoaAuthResponder.respond]: the JSON string to send back and the AOA
 * frame request id that must be echoed from the incoming challenge frame.
 */
data class AuthChallengeResponse(
    val responseFrameRequestId: String,
    val responseEnvelopeJson: String,
)
