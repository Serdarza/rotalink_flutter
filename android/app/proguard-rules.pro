# Flutter, Firebase, Play Services ve AdMob kendi consumer ProGuard kurallarıyla
# gelir; burada paketin tamamını "-keep" etmek R8 karartmasını devre dışı bırakır
# (Play Console: "DEX kodu optimizasyonu – kod karartma" uyarısı).
-dontwarn io.flutter.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# ── Kotlin Coroutines ────────────────────────────────────────────────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ── HTTP / Networking ────────────────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**

# ── Genel Reflection (JSON parse, enum, Parcelable) ─────────────────────────
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# ── Local Notifications ──────────────────────────────────────────────────────
-keep class com.dexterous.** { *; }

# ── Geolocator ───────────────────────────────────────────────────────────────
-keep class com.baseflow.geolocator.** { *; }
