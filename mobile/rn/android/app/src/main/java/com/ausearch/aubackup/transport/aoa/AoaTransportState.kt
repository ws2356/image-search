package com.ausearch.aubackup.transport.aoa

enum class AoaTransportState {
    IDLE,
    PREPARING,
    AUTHENTICATING,
    CONNECTED,
    DISCONNECTED,
    FAILED,
}
