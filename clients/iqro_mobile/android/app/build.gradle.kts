import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.compose") version "2.3.21"
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningFile = rootProject.file("key.properties")
val hasReleaseSigning = releaseSigningFile.exists()
if (hasReleaseSigning) {
    releaseSigningFile.inputStream().use { stream ->
        releaseSigningProperties.load(stream)
    }
    val missingKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        .filter { releaseSigningProperties.getProperty(it).isNullOrBlank() }
    require(missingKeys.isEmpty()) {
        "android/key.properties is missing required release signing fields: ${missingKeys.joinToString()}"
    }
    require(rootProject.file(releaseSigningProperties.getProperty("storeFile")).isFile) {
        "The release keystore configured by android/key.properties does not exist"
    }
}

// Firebase Analytics reads its app ID from resources when the app starts. The
// values come from the same --dart-define-from-file=config/firebase.json as the
// Dart side (docs/analytics.md); builds without it get none.
val dartDefines: Map<String, String> =
    (project.findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it)).split("=", limit = 2) }
        .filter { it.size == 2 }
        .associate { it[0] to it[1] }

android {
    namespace = "forum.iqro.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        abortOnError = true
        checkReleaseBuilds = true
    }

    defaultConfig {
        applicationId = "forum.iqro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
        mapOf(
            "google_app_id" to "FIREBASE_ANDROID_APP_ID",
            "google_api_key" to "FIREBASE_ANDROID_API_KEY",
            "gcm_defaultSenderId" to "FIREBASE_SENDER_ID",
            "project_id" to "FIREBASE_PROJECT_ID",
        ).forEach { (resource, define) ->
            dartDefines[define]?.let { resValue("string", resource, it) }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
    buildFeatures {
        compose = true
    }

}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.glance:glance-appwidget:1.2.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
