package com.ausearch.aubackup.transport.aoa

sealed class AoaTransportError(message: String) : Exception(message) {
    class InvalidBootstrap(message: String) : AoaTransportError(message)
    class ConnectionUnavailable(message: String) : AoaTransportError(message)
    class ConnectionLost(message: String) : AoaTransportError(message)
    class SendFailed(message: String) : AoaTransportError(message)
    class ResponseTimedOut(message: String) : AoaTransportError(message)
    class InvalidEnvelope(message: String) : AoaTransportError(message)
    class AuthRejected(message: String) : AoaTransportError(message)
}
