@file:Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")

package com.ausearch.aubackup.transport.aoa

import android.app.Application
import android.content.Context
import com.facebook.react.bridge.Callback
import com.facebook.react.bridge.CatalystInstance
import com.facebook.react.bridge.JavaScriptModule
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.UIManager
import com.facebook.react.bridge.WritableMap
import com.facebook.react.turbomodule.core.interfaces.CallInvokerHolder
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], application = Application::class)
class AoaTransportModuleTest {

    private lateinit var reactContext: TestReactApplicationContext
    private lateinit var module: AoaTransportModule

    @Before
    fun setUp() {
        AoaClient.resetInstance()
        reactContext = TestReactApplicationContext(RuntimeEnvironment.getApplication())
        module = AoaTransportModule(reactContext)
    }

    @After
    fun tearDown() {
        AoaClient.resetInstance()
    }

    @Test
    fun `module name is AoaTransportModule`() {
        assertEquals("AoaTransportModule", module.name)
    }

    @Test
    fun `prepareBootstrap resolves promise with valid session and port`() {
        val promise = TestPromise()
        module.prepareBootstrap("sid-001", "123456", 8080, promise)
        assertTrue("prepareBootstrap should resolve", promise.isResolved)
        assertNull(promise.resolvedValue)
    }

    /**
     * Minimal concrete [ReactApplicationContext] for unit tests.
     *
     * [AoaTransportModule] only needs lifecycle state checks; the rest of the
     * ReactContext surface is intentionally stubbed out.
     */
    @Suppress("DEPRECATION")
    private class TestReactApplicationContext(context: Context) : ReactApplicationContext(context) {
        override fun <T : JavaScriptModule> getJSModule(jsInterface: Class<T>): T {
            throw UnsupportedOperationException()
        }

        override fun <T : NativeModule> hasNativeModule(nativeModuleInterface: Class<T>): Boolean = false

        override fun getNativeModules(): MutableCollection<NativeModule> = mutableListOf()

        override fun <T : NativeModule> getNativeModule(nativeModuleInterface: Class<T>): T? = null

        override fun getNativeModule(name: String): NativeModule? = null

        override fun getCatalystInstance(): CatalystInstance {
            throw UnsupportedOperationException()
        }

        override fun hasActiveCatalystInstance(): Boolean = false
        override fun hasActiveReactInstance(): Boolean = false
        override fun hasCatalystInstance(): Boolean = false
        override fun hasReactInstance(): Boolean = false

        override fun destroy() {}
        override fun handleException(e: Exception) {}
        override fun isBridgeless(): Boolean = false
        override fun getJavaScriptContextHolder(): com.facebook.react.bridge.JavaScriptContextHolder? = null
        override fun getJSCallInvokerHolder(): CallInvokerHolder? = null
        override fun getFabricUIManager(): UIManager? = null
        override fun getSourceURL(): String? = null
        override fun registerSegment(segmentId: Int, path: String, callback: Callback) {}
    }

    private class TestPromise : Promise {
        var isResolved = false
            private set
        var isRejected = false
            private set
        var resolvedValue: Any? = null
            private set
        var rejectedCode: String? = null
            private set
        var rejectedMessage: String? = null
            private set
        var rejectedThrowable: Throwable? = null
            private set

        override fun resolve(value: Any?) {
            isResolved = true
            resolvedValue = value
        }

        override fun reject(code: String?, message: String?) {
            reject(code, message, null)
        }

        override fun reject(code: String?, throwable: Throwable?) {
            reject(code, throwable?.message, throwable)
        }

        override fun reject(code: String?, message: String?, throwable: Throwable?) {
            isRejected = true
            rejectedCode = code
            rejectedMessage = message
            rejectedThrowable = throwable
        }

        override fun reject(throwable: Throwable) {
            reject(null, throwable.message, throwable)
        }

        override fun reject(throwable: Throwable, userInfo: WritableMap) {
            reject(null, throwable.message, throwable)
        }

        override fun reject(code: String?, userInfo: WritableMap) {
            reject(code, null, null)
        }

        override fun reject(code: String?, throwable: Throwable?, userInfo: WritableMap) {
            reject(code, throwable?.message, throwable)
        }

        override fun reject(code: String?, message: String?, userInfo: WritableMap) {
            reject(code, message, null)
        }

        override fun reject(code: String?, message: String?, throwable: Throwable?, userInfo: WritableMap?) {
            isRejected = true
            rejectedCode = code
            rejectedMessage = message
            rejectedThrowable = throwable
        }

        override fun reject(message: String) {
            reject(null, message, null)
        }
    }
}
