import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.titanlancsak.english_with_movies"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.titanlancsak.english_with_movies"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // The bundled tools (native-tools/build.sh) are built for 64-bit ARM, like almost every phone today.
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    packaging {
        jniLibs {
            // ffmpeg and whisper-cli are programs, not libraries: they must be extracted to run.
            useLegacyPackaging = true
            // Only 64-bit ARM: a phone without it should refuse the install, not crash later.
            excludes += listOf("lib/armeabi-v7a/**", "lib/x86/**", "lib/x86_64/**")
        }
    }

    // Release key: android/key.properties locally, or KEYSTORE_* variables on GitHub.
    // Without one (e.g. a fork), release builds are signed with the debug key.
    val keyProperties = Properties().apply {
        val file = rootProject.file("key.properties")
        if (file.exists()) file.inputStream().use { load(it) }
    }
    val storeFilePath = keyProperties.getProperty("storeFile") ?: System.getenv("KEYSTORE_FILE")
    signingConfigs {
        if (storeFilePath != null) {
            create("release") {
                storeFile = file(storeFilePath)
                storePassword = keyProperties.getProperty("storePassword") ?: System.getenv("KEYSTORE_PASSWORD")
                keyAlias = keyProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
                keyPassword = keyProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
