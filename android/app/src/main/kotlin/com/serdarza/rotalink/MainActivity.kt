package com.serdarza.rotalink

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentSender
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.Settings
import androidx.core.view.WindowCompat
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.LocationSettingsRequest
import com.google.android.gms.location.Priority
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var locationSettingsResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 15 öncesinde de uçtan uca (edge-to-edge) çizim; Flutter tarafı
        // SystemUiMode.edgeToEdge ile sistem çubuğu boşluklarını kendisi yönetir.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AdminTestNotificationSession.register(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rotalink/location")
            .setMethodCallHandler { call, result ->
                if (call.method == "requestService") {
                    promptLocationService(result)
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

    /// Ayarlar sayfası yerine telefonun kendi “konumu aç” penceresini gösterir.
    private fun promptLocationService(result: MethodChannel.Result) {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 10_000L).build()
        val settings = LocationSettingsRequest.Builder()
            .addLocationRequest(request)
            .setAlwaysShow(true)
            .build()
        LocationServices.getSettingsClient(this)
            .checkLocationSettings(settings)
            .addOnSuccessListener { result.success(true) }
            .addOnFailureListener { error ->
                if (error is ResolvableApiException) {
                    try {
                        locationSettingsResult?.success(false)
                        locationSettingsResult = result
                        error.startResolutionForResult(this, REQUEST_LOCATION_SETTINGS)
                    } catch (_: IntentSender.SendIntentException) {
                        locationSettingsResult = null
                        result.success(false)
                    }
                } else {
                    result.success(false)
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_LOCATION_SETTINGS) {
            val pending = locationSettingsResult
            locationSettingsResult = null
            pending?.success(resultCode == Activity.RESULT_OK)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    companion object {
        private const val REQUEST_LOCATION_SETTINGS = 4510
    }
}
