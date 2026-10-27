package com.serdarza.rotalink

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.util.TypedValue
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL

/** Shared Android layout for normal messages and explicitly paired debug tests. */
class RotalinkMessagingService : FlutterFirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data = message.data
        val isTest = data["type"] == "rotalink_admin_test"
        if ((!isTest && data["type"] != "rotalink_admin") || data["notificationRenderer"] != "2") return
        val prefs = getSharedPreferences(AdminTestNotificationSession.PREFS, Context.MODE_PRIVATE)
        if (isTest) {
            if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0 ||
                prefs.getString("id", null) != data["testSession"] ||
                prefs.getLong("expiry", 0) <= System.currentTimeMillis()) return
        } else if (!prefs.getBoolean("publicEnabled", false)) return
        val delivery = data[if (isTest) "testDelivery" else "notificationId"] ?: return
        if (!Regex(if (isTest) "^[a-f0-9-]{36}$" else "^[A-Za-z0-9_-]{16,80}$").matches(delivery)) return
        val route = data["route"] ?: ""
        if (route !in listOf("", "anasayfa", "kampanyalar", "tatiller", "kis-kesfet", "rota", "ara", "tesisler", "pro", "external")) return
        val link = data["link"] ?: ""
        if (link.isNotEmpty()) {
            val url = Uri.parse(link)
            if (url.scheme != "https" || url.host.isNullOrEmpty() || url.userInfo != null) return
        } else if (route == "external") return
        val title = data["title"]?.takeIf { it.isNotBlank() && it.length <= 100 } ?: return
        val body = data["body"]?.takeIf { it.isNotBlank() && it.length <= 300 } ?: return
        try {
            val manager = getSystemService(NotificationManager::class.java)
            val channel = if (isTest) "rotalink_admin_test" else "rotalink_updates"
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel(channel, if (isTest) "Yönetici telefon testleri" else "Rotalink bildirimleri", NotificationManager.IMPORTANCE_HIGH))
            val id = 950000 + (delivery.hashCode() and 1023)
            // Same callback contract as flutter_local_notifications, with a validated
            // embedded target so tapping does not race the background Dart event.
            val intent = Intent(this, MainActivity::class.java).apply {
                action = "SELECT_NOTIFICATION"
                setData(Uri.parse("rotalink-internal://admin-test/$delivery"))
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("notificationId", id)
                putExtra("payload", (if (isTest) "admin_test:native2:" else "admin_push:") + JSONObject(data).toString())
            }
            val pending = PendingIntent.getActivity(this, id, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = NotificationCompat.Builder(this, channel)
                .setSmallIcon(R.drawable.ic_stat_rotalink).setColor(getColor(R.color.primary))
                .setContentTitle(title).setContentText(body).setContentIntent(pending)
                .setAutoCancel(true).setPriority(NotificationCompat.PRIORITY_HIGH)
            val picture = loadPicture(data["imageUrl"], isTest)
            if (picture == null || Build.VERSION.SDK_INT < 31) {
                builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
                if (picture != null) {
                    val square = Bitmap.createBitmap(192, 192, Bitmap.Config.ARGB_8888)
                    val canvas = android.graphics.Canvas(square)
                    val ratio = minOf(192f / picture.width, 192f / picture.height)
                    val w = picture.width * ratio
                    val h = picture.height * ratio
                    canvas.drawBitmap(picture, null, android.graphics.RectF((192-w)/2, (192-h)/2, (192+w)/2, (192+h)/2), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
                    builder.setLargeIcon(square)
                }
            } else {
                // Decorated style keeps Android's trusted app/icon header. Text wraps;
                // FIT_CENTER displays the entire image in the remaining bounded area.
                val view = RemoteViews(packageName, R.layout.admin_test_notification)
                view.setTextViewText(R.id.admin_notification_title, title)
                view.setTextViewText(R.id.admin_notification_body, body)
                val width = (resources.displayMetrics.widthPixels - dp(80)).coerceAtLeast(dp(220))
                val titleSize = sp(15f)
                var bodySize = sp(13f)
                val titleHeight = textHeight(title, titleSize, width, bold = true)
                while (bodySize > sp(11f) && titleHeight + textHeight(body, bodySize, width) > dp(174)) {
                    bodySize -= sp(0.5f)
                }
                val imageHeight = (dp(232) - titleHeight - textHeight(body, bodySize, width) - dp(14))
                    .coerceIn(dp(32), dp(156))
                view.setTextViewTextSize(R.id.admin_notification_title, TypedValue.COMPLEX_UNIT_PX, titleSize)
                view.setTextViewTextSize(R.id.admin_notification_body, TypedValue.COMPLEX_UNIT_PX, bodySize)
                view.setImageViewBitmap(R.id.admin_notification_picture, picture)
                if (Build.VERSION.SDK_INT >= 31) view.setViewLayoutHeight(
                    R.id.admin_notification_picture, imageHeight.toFloat(), TypedValue.COMPLEX_UNIT_PX)
                // The normal compact notification remains Android's standard title/text.
                builder.setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomBigContentView(view)
            }
            if (NotificationManagerCompat.from(this).areNotificationsEnabled()) manager.notify(delivery, id, builder.build())
        } catch (_: Exception) {
            // Never log FCM/session/image credentials or user content.
        }
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun sp(value: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, value, resources.displayMetrics)
    private fun textHeight(text: String, size: Float, width: Int, bold: Boolean = false): Int {
        val paint = TextPaint().apply {
            textSize = size
            if (bold) typeface = android.graphics.Typeface.DEFAULT_BOLD
        }
        return StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).build().height
    }

    private fun loadPicture(value: String?, isTest: Boolean): Bitmap? {
        if (value == null) return null
        val uri = Uri.parse(value)
        if (uri.scheme != "https" || uri.host != "admin.rotalink.tr" || uri.query != null || uri.fragment != null ||
            !Regex(if (isTest) "^/device-test/image/[A-Za-z0-9_-]{43}/[a-f0-9-]{36}\\.(jpg|png)$" else "^/media/[a-f0-9-]{36}\\.(jpg|png)$").matches(uri.path ?: "")) return null
        var connection: HttpURLConnection? = null
        return try {
            connection = URL(value).openConnection() as HttpURLConnection
            connection.instanceFollowRedirects = false
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            if (connection.responseCode != 200 || connection.contentLengthLong > 1024 * 1024) return null
            if (connection.contentType?.substringBefore(';') !in listOf("image/jpeg", "image/png")) return null
            val out = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(8192)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    if (out.size() + count > 1024 * 1024) return null
                    out.write(buffer, 0, count)
                }
            }
            val bytes = out.toByteArray()
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0 || bounds.outWidth.toLong() * bounds.outHeight > 16000000) return null
            val options = BitmapFactory.Options().apply { inSampleSize = 1 }
            while (maxOf(bounds.outWidth, bounds.outHeight) / options.inSampleSize > 1024) options.inSampleSize *= 2
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        } catch (_: Exception) { null } finally { connection?.disconnect() }
    }
}
