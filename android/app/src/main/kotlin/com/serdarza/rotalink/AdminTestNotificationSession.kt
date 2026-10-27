package com.serdarza.rotalink

import android.content.Context
import android.content.pm.ApplicationInfo
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Public pairing ID and expiry only. Bearer/FCM credentials stay in their existing stores. */
object AdminTestNotificationSession {
    const val PREFS = "rotalink_admin_notification_layout"
    fun register(context: Context, messenger: BinaryMessenger) {
        MethodChannel(messenger, "rotalink/admin_notification_layout").setMethodCallHandler { call, result ->
            if (call.method == "subscriptionStatus") {
                val ready = call.argument<Boolean>("ready") == true
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putBoolean("subscriptionReady", ready).apply()
                android.util.Log.i("RotalinkNotifications", if (ready) "subscription_ready" else "subscription_inactive")
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method == "public") {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                    .putBoolean("publicEnabled", call.argument<Boolean>("enabled") == true).apply()
                result.success(2)
                return@setMethodCallHandler
            }
            if (call.method != "configure") { result.notImplemented(); return@setMethodCallHandler }
            if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 || Build.VERSION.SDK_INT < 31) {
                result.success(0); return@setMethodCallHandler
            }
            val id = call.argument<String>("id")
            val expiry = call.argument<Number>("expiresAt")?.toLong() ?: 0L
            val now = System.currentTimeMillis()
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (id != null && Regex("^[a-f0-9-]{36}$").matches(id) && expiry > now && expiry <= now + 26 * 3600000L) {
                prefs.edit().putString("id", id).putLong("expiry", expiry).apply()
                result.success(2)
            } else {
                prefs.edit().remove("id").remove("expiry").apply()
                result.success(0)
            }
        }
    }
}
