// AGP 9 defaults to the new DSL, but the kotlin-android plugin the flutter
// gradle plugin relies on cannot run against it yet. Until that lands we stay
// on the old DSL (supported through AGP 9.x) and mute its deprecation notice.
@file:Suppress("DEPRECATION")

import java.io.FileInputStream
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Reads android/app/google-services.json (Firebase project config for
    // ch.kubbclub.app). NOTE: the build FAILS if that file is missing.
    id("com.google.gms.google-services")
}

// Local release builds read android/key.properties. On Codemagic the keystore
// is attached to the workflow and exposed through the CM_* env vars instead.
// When neither is present we sign with the debug keys, so a contributor without
// the upload keystore can still run `flutter build --release` for a smoke test.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseKeystore =
    keystorePropertiesFile.exists() || System.getenv("CM_KEYSTORE_PATH") != null

android {
    namespace = "ch.kubbclub.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Reverse-domain application id for the owned domain kubbclub.ch.
        // IMMUTABLE once published to the Play Store — registered as-is in
        // Firebase (FCM) too.
        applicationId = "ch.kubbclub.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            } else if (System.getenv("CM_KEYSTORE_PATH") != null) {
                keyAlias = System.getenv("CM_KEY_ALIAS")
                keyPassword = System.getenv("CM_KEY_PASSWORD")
                storeFile = file(System.getenv("CM_KEYSTORE_PATH"))
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
