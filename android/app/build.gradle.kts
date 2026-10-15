import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Charge la clé de signature depuis android/key.properties (non commité).
// Si le fichier n'existe pas, on retombe sur la clé debug (pour `flutter run`).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.correctis"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requis par flutter_local_notifications (API Java 8 sur Android < 26)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Identifiant unique de l'app sur le Play Store
        applicationId = "com.correctis.app"
        // minSdk 23 minimum requis par flutter_local_notifications + Supabase
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // Audit 15/10/2026 : plus de repli silencieux sur la clé debug.
            // Un AAB signé debug serait refusé par Play (ou pire, accepté sur
            // un autre canal). Sans key.properties, le build release échoue
            // (voir le contrôle taskGraph plus bas) ; `flutter run` (debug)
            // n'est pas concerné.
            signingConfig = signingConfigs.getByName("release")
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
    // Requis pour `isCoreLibraryDesugaringEnabled` ci-dessus
    // (utilisé par flutter_local_notifications pour les API Java 8 récentes).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// Fait échouer tout build *release* si la clé de signature est absente.
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.project == project && it.name.contains("Release") }
    if (wantsRelease && !keystorePropertiesFile.exists()) {
        throw GradleException(
            "android/key.properties introuvable : le build release doit être signé " +
                "avec la clé d'upload Play (voir ANDROID_BUILD.md).",
        )
    }
}
