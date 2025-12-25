import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics") // ✅ ADDED (Crashlytics plugin)
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun kp(name: String): String {
    return keystoreProperties.getProperty(name)
        ?: throw GradleException("Missing '$name' in android/key.properties")
}

android {
    namespace = "com.doraride.apps"

    // Keep using Flutter's configured SDK versions
    compileSdk = flutter.compileSdkVersion

    // ✅ FIX: Force installed NDK 26.1+ for 16KB memory page size support
    // Change this to the exact version you installed from Android Studio SDK Tools.
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.doraride.apps"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ✅ Signing config (expects ONLY these keys in android/key.properties):
    // storePassword, keyPassword, keyAlias, storeFile
    signingConfigs {
        create("release") {
            keyAlias = kp("keyAlias")
            keyPassword = kp("keyPassword")
            storePassword = kp("storePassword")
            storeFile = file(kp("storeFile"))
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
