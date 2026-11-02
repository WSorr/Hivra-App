import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val publicRelease = System.getenv("HIVRA_RELEASE_CHANNEL") == "public"
val releaseKey = Properties()
if (publicRelease) {
    val keyFile = rootProject.file("key.properties")
    check(keyFile.isFile) { "Public release requires local android/key.properties" }
    keyFile.inputStream().use { releaseKey.load(it) }
    for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        check(!releaseKey.getProperty(name).isNullOrBlank()) {
            "Public release signing is missing $name"
        }
    }
}

val buildRustFfi by tasks.registering(Exec::class) {
    group = "build"
    description = "Build hivra Rust FFI libraries for Android ABIs"
    workingDir = rootProject.projectDir
    commandLine("sh", "${rootProject.projectDir}/build_rust_android.sh")
}

android {
    namespace = "com.hivra.hivra_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    sourceSets {
        getByName("main") {
            jniLibs.srcDir("build/generated/rustJniLibs")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.hivra.hivra_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (publicRelease) {
            create("release") {
                storeFile = rootProject.file(releaseKey.getProperty("storeFile"))
                storePassword = releaseKey.getProperty("storePassword")
                keyAlias = releaseKey.getProperty("keyAlias")
                keyPassword = releaseKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (publicRelease) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}

tasks.named("preBuild") {
    dependsOn(buildRustFfi)
}
