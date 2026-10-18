package com.serdarza.rotalink

import android.content.ActivityNotFoundException
import android.content.Intent
import android.os.Bundle
import android.provider.CalendarContract
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

        // Konaklama detayı → "Takvime Ekle": sistem takviminin etkinlik ekleme
        // ekranını açar. Kaydı kullanıcı onaylar; izin gerekmez.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rotalink/calendar")
            .setMethodCallHandler { call, result ->
                if (call.method != "addEvent") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val begin = (call.argument<Number>("beginMillis"))?.toLong()
                    ?: System.currentTimeMillis()
                val end = (call.argument<Number>("endMillis"))?.toLong()
                    ?: (begin + 60L * 60L * 1000L)
                val intent = Intent(Intent.ACTION_INSERT).apply {
                    data = CalendarContract.Events.CONTENT_URI
                    putExtra(CalendarContract.Events.TITLE, call.argument<String>("title") ?: "")
                    putExtra(
                        CalendarContract.Events.DESCRIPTION,
                        call.argument<String>("notes") ?: "",
                    )
                    putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, begin)
                    putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end)
                }
                try {
                    startActivity(intent)
                    result.success(true)
                } catch (e: ActivityNotFoundException) {
                    result.success(false)
                }
            }
    }
}
