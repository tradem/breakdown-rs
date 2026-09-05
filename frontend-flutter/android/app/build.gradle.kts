plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Kotlin Gradle Plugin — required because android.builtInKotlin=false in
    // gradle.properties (Flutter template default for AGP 9 compatibility).
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "rs.breakdown.frontend_flutter"
    // Pinned above `flutter.compileSdkVersion` (currently 36):
    // `flutter_secure_storage` ships AAR metadata requiring compileSdk 37+.
    // Revisit when the Flutter stable template moves past 36.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "rs.breakdown.frontend_flutter"
        // OIDC redirect scheme (spec `flutter-auth-shell`, task 3.3): the
        // `oidcRedirectScheme` manifest placeholder is derived from the SAME
        // `OIDC_REDIRECT_URI` environment value that CI passes to Flutter as
        // `--dart-define=OIDC_REDIRECT_URI`, so the native deep-link
        // registration cannot drift from the Dart configuration. Default is
        // the canonical URI for both flavors (single application ID, no
        // Gradle flavors): `breakdown://auth/callback`.
        val oidcRedirectUri = System.getenv("OIDC_REDIRECT_URI")
            .orEmpty()
            .ifEmpty { "breakdown://auth/callback" }
        val oidcRedirectScheme = oidcRedirectUri
            .substringBefore("://")
            .substringBefore(":")
        require(
            oidcRedirectScheme.isNotBlank() &&
                !oidcRedirectScheme.contains("/")
        ) {
            "OIDC_REDIRECT_URI has no valid custom scheme: " +
                "'$oidcRedirectUri' (expected e.g. 'breakdown://auth/callback')"
        }
        // An explicitly passed `-PoidcRedirectScheme=...` must agree with
        // the derived scheme — a mismatch fails the build instead of
        // shipping a native registration the IdP redirect can never reach.
        val explicitScheme = project.findProperty("oidcRedirectScheme") as String?
        if (explicitScheme != null && explicitScheme != oidcRedirectScheme) {
            throw GradleException(
                "oidcRedirectScheme property ('$explicitScheme') does not " +
                    "match the scheme derived from OIDC_REDIRECT_URI " +
                    "('$oidcRedirectScheme'). Pass the same OIDC_REDIRECT_URI " +
                    "to Gradle and --dart-define."
            )
        }
        manifestPlaceholders["oidcRedirectScheme"] = oidcRedirectScheme
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
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
