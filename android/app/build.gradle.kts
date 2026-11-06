import java.util.Properties
import java.security.KeyStore
import java.security.MessageDigest

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// This existing certificate must be preserved for updates without data loss.
val expectedCertificateSha256 = "716d350e47cffbd8d0e9d6e790c147f6d05fbd305c81cc0dc2ffeccb4c552991"
val signingPropertiesFile = rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.isFile) signingPropertiesFile.inputStream().use { load(it) }
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
fun verifyOriginalReleaseKey() {
    check(signingPropertiesFile.isFile) {
        "Release signing requires android/key.properties and the ORIGINAL keystore. See docs/ANDROID_SIGNING.md. No key will be generated."
    }
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach {
        check(!signingProperties.getProperty(it).isNullOrBlank()) { "Missing release signing property: $it" }
    }
    val originalKey = rootProject.file(signingProperties.getProperty("storeFile"))
    check(originalKey.isFile) { "Original release keystore is missing. Do not create a replacement." }
    val keyStore = KeyStore.getInstance(originalKey, signingProperties.getProperty("storePassword").toCharArray())
    val certificate = keyStore.getCertificate(signingProperties.getProperty("keyAlias"))
    check(certificate != null) { "Signing alias has no certificate." }
    val fingerprint = MessageDigest.getInstance("SHA-256").digest(certificate.encoded)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    check(fingerprint == expectedCertificateSha256) {
        "Release signing certificate mismatch. The original RECARE key is required; release build stopped."
    }
}
if (releaseRequested) verifyOriginalReleaseKey()
// Aggregate/abbreviated task names also resolve release work. Check the resolved
// graph before any tasks execute, so `build` cannot bypass the certificate pin.
gradle.taskGraph.whenReady {
    if (allTasks.any { it.project.path == ":app" && it.name.contains("release", ignoreCase = true) }) {
        verifyOriginalReleaseKey()
    }
}

android {
    namespace = "com.detabev.recare"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.detabev.recare"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("originalRelease") {
            if (signingPropertiesFile.isFile) {
                storeFile = signingProperties.getProperty("storeFile")?.let { rootProject.file(it) }
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("originalRelease")
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
