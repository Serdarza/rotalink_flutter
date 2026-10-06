package com.serdarza.rotalink

import android.os.Bundle
import android.provider.Settings
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 öncesinde de uçtan uca (edge-to-edge) çizim; Flutter tarafı
        // SystemUiMode.edgeToEdge ile sistem çubuğu boşluklarını kendisi yönetir.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Ücretsiz Pro hakkı için: uygulama silinip yüklenince değişmez.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rotalink/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "androidId") {
                    result.success(
                        Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
                    )
                } else {
                    result.notImplemented()
                }
            }
    }
}
