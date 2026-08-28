package com.ausearch.aubackup.transport.aoa

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager

/**
 * React Package that registers the AOA transport native module.
 *
 * The module is constructed with the shared [AoaClient] singleton so the
 * native client survives React Native reloads and is shared between the
 * application and the module.
 */
class AoaTransportPackage : ReactPackage {
    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> {
        return listOf(
            AoaTransportModule(
                reactContext,
                AoaClient.getInstance(reactContext.applicationContext),
            ),
        )
    }

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> {
        return emptyList()
    }
}
