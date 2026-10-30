pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// Include local AbrovaSync Android SDK for development
// Substitutes Maven dependency ir.abrova.sync:abrova-sync-android:1.0.0 with local build
val localSyncSdkDir = file("../../../android")
if (localSyncSdkDir.exists() && file("${localSyncSdkDir}/abrova_sync").exists()) {
    println("AbrovaSync: Including local Android SDK from ${localSyncSdkDir.absolutePath}")
    includeBuild(localSyncSdkDir) {
        name = "abrova-sync-sdk"
        dependencySubstitution {
            substitute(module("ir.abrova.sync:abrova-sync-android")).using(project(":abrova_sync"))
        }
    }
}

// Include local AbrovaPush Android SDK for development
// Substitutes Maven dependency ir.abrova:abrova-push-android with local build
val localPushSdkDir = file("../../../../abrovapush_project/android")
if (localPushSdkDir.exists() && file("${localPushSdkDir}/abrova-push").exists()) {
    println("AbrovaPush: Including local Android SDK from ${localPushSdkDir.absolutePath}")
    includeBuild(localPushSdkDir) {
        name = "abrova-push-sdk"
        dependencySubstitution {
            substitute(module("ir.abrova:abrova-push-android")).using(project(":abrova-push"))
        }
    }
}
