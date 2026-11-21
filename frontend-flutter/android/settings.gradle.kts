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
    id("com.android.application") version "9.5.1" apply false
    // Built-in Kotlin (android.builtInKotlin=true) compiles the Kotlin
    // sources itself — KGP is NOT applied to any module. It IS still pinned
    // here, `apply false`, because AGP 9.5.1 bundles KGP 2.2.10 while
    // Flutter 3.47 hard-fails below 2.2.20 (DependencyVersionChecker reads
    // the KGP version from the build classpath). The declaration upgrades
    // that classpath and applies nothing, so no duplicate `kotlin` extension
    // is created. Re-check this pin when AGP or Flutter moves.
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
