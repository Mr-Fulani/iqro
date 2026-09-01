import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
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

android {
    namespace = "forum.iqro.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
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
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
