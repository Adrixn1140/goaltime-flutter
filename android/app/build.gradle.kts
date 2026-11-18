import java.util.Properties
import java.util.Base64
import java.net.URI

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// La firma de release sale de `android/key.properties`, que NO se versiona (`android/.gitignore`).
// Debug sigue funcionando sin este archivo. Release exige firma propia y API HTTPS.
val releaseSigning: Properties? = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) archivo.inputStream().use { load(it) }
}.takeIf { it.containsKey("storeFile") }

android {
    signingConfigs {
        if (releaseSigning != null) {
            create("release") {
                storeFile = rootProject.file(releaseSigning.getProperty("storeFile"))
                storePassword = releaseSigning.getProperty("storePassword")
                keyAlias = releaseSigning.getProperty("keyAlias")
                keyPassword = releaseSigning.getProperty("keyPassword")
            }
        }
    }

    namespace = "com.goaltime.goaltime_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.goaltime.goaltime_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Nunca distribuir una versión release firmada silenciosamente con debug.
            signingConfig = if (releaseSigning != null) {
                signingConfigs.getByName("release")
            } else {
                null
            }
        }
    }
}

val validateProductionRelease = tasks.register("validateProductionRelease") {
    doLast {
        val signing = releaseSigning ?: throw GradleException(
            "Release requiere android/key.properties y un keystore propio. Ver docs/PRODUCCION.md."
        )
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword").forEach { key ->
            if (signing.getProperty(key).isNullOrBlank()) throw GradleException("Falta $key en key.properties")
        }
        if (!rootProject.file(signing.getProperty("storeFile")).isFile) {
            throw GradleException("No existe el keystore configurado. No se genera ni reemplaza automáticamente.")
        }
        val defines = (project.findProperty("dart-defines") as? String).orEmpty()
            .split(",").mapNotNull { encoded ->
                runCatching { String(Base64.getDecoder().decode(encoded), Charsets.UTF_8) }.getOrNull()
            }
        val api = defines.firstOrNull { it.startsWith("API_BASE_URL=") }?.substringAfter("=")
            ?: throw GradleException("Release requiere --dart-define=API_BASE_URL=https://TU_API_PUBLICA")
        val uri = runCatching { URI(api) }.getOrNull()
        val host = uri?.host?.lowercase().orEmpty()
        val local = host == "localhost" || host.endsWith(".local") || host.endsWith(".test") ||
            host.endsWith(".invalid") || host.endsWith(".example") || host == "example.com" ||
            host.contains(":") || host.matches(Regex("[0-9.]+"))
        if (uri == null || uri.scheme != "https" || !host.contains(".") || local ||
            uri.rawUserInfo != null || uri.rawQuery != null || uri.rawFragment != null ||
            uri.path.orEmpty() !in listOf("", "/") || uri.port !in listOf(-1, 443)) {
            throw GradleException("API_BASE_URL debe ser un origen HTTPS público, sin /api, credenciales ni parámetros.")
        }
    }
}

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateProductionRelease)
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
