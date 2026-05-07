import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = File(rootDir, "key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.reader(Charsets.UTF_8).use { keystoreProperties.load(it) }
}

// Tüm imzalama özellikleri mevcutsa true — signingConfigs ve buildTypes aynı koşulu kullanır.
val hasFullSigningConfig: Boolean =
    keystorePropertiesFile.exists() &&
    keystoreProperties.getProperty("keyAlias") != null &&
    keystoreProperties.getProperty("keyPassword") != null &&
    keystoreProperties.getProperty("storeFile") != null &&
    keystoreProperties.getProperty("storePassword") != null

android {
    // Play Store / mevcut Kotlin uygulaması ile aynı paket — değiştirmeyin.
    namespace = "com.serdarza.rotalink"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Play Store güncellemesi için Kotlin ile aynı applicationId olmalı.
        applicationId = "com.serdarza.rotalink"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // Bazı OEM’lerde sıkıştırılmamış .so + ADB aktarımında imza doğrulama hatası azalır.
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        // Release config yalnızca tüm imzalama bilgileri tamam olduğunda oluşturulur.
        // hasFullSigningConfig false ise bu blok atlanır; buildTypes.release debug anahtarına düşer.
        if (hasFullSigningConfig) {
            create("release") {
                keyAlias     = keystoreProperties.getProperty("keyAlias")
                keyPassword  = keystoreProperties.getProperty("keyPassword")
                storeFile    = rootProject.file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig =
                if (hasFullSigningConfig) {
                    signingConfigs.getByName("release")
                } else {
                    println(
                        "UYARI: android/key.properties yok veya eksik — release APK/AAB debug anahtarıyla imzalanıyor. " +
                            "Play Store için key.properties + keystore dosyalarını kontrol edin.",
                    )
                    signingConfigs.getByName("debug")
                }
            // R8 kod küçültme + kaynak temizleme → APK boyutu ve tersine mühendislik koruması.
            // flutter build apk --obfuscate --split-debug-info=build/debug-info ile tam obfuscation.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Flutter Gradle eklentisi bazen [compileOptions] birleşiminden önce AAR metadata kontrolü yapıyor;
// desugaring bayrağını değerlendirme sonunda tekrar işaretle (checkDebugAarMetadata geçsin).
afterEvaluate {
    android.compileOptions.isCoreLibraryDesugaringEnabled = true
}
