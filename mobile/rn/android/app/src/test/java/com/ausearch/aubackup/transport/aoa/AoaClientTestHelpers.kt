package com.ausearch.aubackup.transport.aoa

import android.os.ParcelFileDescriptor
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

/**
 * Shared state for a file-backed test pipe.
 *
 * Used by [BlockingFileInputStream] and [BlockingFileOutputStream] to signal when the writer
 * side has written data or closed, so the reader can block efficiently instead of polling.
 */
internal class FilePipeState {
    val writerClosed = AtomicBoolean(false)
    val lock = ReentrantLock()
    val dataAvailable = lock.newCondition()
}

/**
 * Blocking file-backed input stream used only by the test harness.
 *
 * Regular files opened through [ParcelFileDescriptor.open] return EOF immediately when no
 * data has been written yet. This wrapper waits on a condition signaled by the paired
 * [BlockingFileOutputStream], allowing two threads to use temp files as unidirectional pipes
 * without polling noise.
 */
internal class BlockingFileInputStream(
    private val descriptor: ParcelFileDescriptor,
    private val state: FilePipeState,
) : InputStream() {
    private val input = FileInputStream(descriptor.fileDescriptor)
    private val channel = input.channel
    @Volatile
    private var closed = false

    override fun read(): Int {
        val buffer = ByteArray(1)
        val read = read(buffer, 0, 1)
        return if (read < 0) -1 else buffer[0].toInt() and 0xFF
    }

    override fun read(b: ByteArray, off: Int, len: Int): Int {
        while (!closed) {
            val available = channel.size() - channel.position()
            if (available > 0) {
                val toRead = minOf(len.toLong(), available).toInt()
                val read = input.read(b, off, toRead)
                if (read > 0) return read
            }
            if (state.writerClosed.get()) {
                return -1
            }
            state.lock.withLock {
                while (!closed && !state.writerClosed.get() && channel.size() - channel.position() <= 0) {
                    try {
                        state.dataAvailable.awaitNanos(100_000_000)
                    } catch (_: InterruptedException) {
                        Thread.currentThread().interrupt()
                        return@withLock
                    }
                }
            }
        }
        return -1
    }

    override fun close() {
        closed = true
        state.lock.withLock { state.dataAvailable.signalAll() }
        input.close()
        descriptor.close()
    }
}

/**
 * Blocking file-backed output stream used only by the test harness.
 *
 * Writes are flushed immediately and the paired [BlockingFileInputStream] is signaled so the
 * reader thread wakes without polling.
 */
internal class BlockingFileOutputStream(
    private val descriptor: ParcelFileDescriptor,
    private val state: FilePipeState,
) : OutputStream() {
    private val output = FileOutputStream(descriptor.fileDescriptor)

    override fun write(b: Int) {
        output.write(b)
        output.flush()
        signalReader()
    }

    override fun write(b: ByteArray, off: Int, len: Int) {
        output.write(b, off, len)
        output.flush()
        signalReader()
    }

    override fun flush() {
        output.flush()
        signalReader()
    }

    override fun close() {
        state.writerClosed.set(true)
        state.lock.withLock { state.dataAvailable.signalAll() }
        output.close()
        descriptor.close()
    }

    private fun signalReader() {
        state.lock.withLock { state.dataAvailable.signalAll() }
    }
}
