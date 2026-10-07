import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val hasReleaseSigning = listOf(
    "keyAlias",
    "keyPassword",
    "storeFile",
    "storePassword",
).all { key ->
    val value = keystoreProperties.getProperty(key)
    !value.isNullOrBlank()
}

// Developer builds: `--dart-define=NEOSTATION_FLAVOR=<name>` (e.g. `pup`)
// installs as `com.neogamelab.neostation.<name>` / "NeoStation <Name>" so it
// runs side by side with the release. Flutter passes dart-defines to Gradle as
// a comma-separated list of base64-encoded `KEY=value` entries. Must match
// lib/utils/build_flavor.dart.
val neostationFlavor: String = (project.findProperty("dart-defines") as String?)
    ?.split(",")
    ?.map { String(java.util.Base64.getDecoder().decode(it)) }
    ?.firstOrNull { it.startsWith("NEOSTATION_FLAVOR=") }
    ?.substringAfter("=")
    ?.trim()
    .orEmpty()

android {
    namespace = "com.neogamelab.neostation"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.neogamelab.neostation"
        manifestPlaceholders["appName"] = "NeoStation"
        if (neostationFlavor.isNotEmpty()) {
            applicationIdSuffix = ".$neostationFlavor"
            manifestPlaceholders["appName"] =
                "NeoStation " + neostationFlavor.replaceFirstChar { it.uppercase() }
        }
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
