package com.ausearch.aubackup.transport.aoa

/**
 * Exception thrown when an AOA frame is malformed or unsupported.
 *
 * Used by AoaFrameCodec for low-level wire-format errors such as invalid
 * version, invalid flags, length mismatch, or non-ASCII request IDs.
 */
class AoaFrameCodecException(message: String) : IllegalArgumentException(message)
