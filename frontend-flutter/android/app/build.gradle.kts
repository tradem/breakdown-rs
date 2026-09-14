// SPDX-License-Identifier: AGPL-3.0
// Copyright (C) 2024-2026 Breakdown RS Contributors
// Co-authored-by: omen-alpha (opencode-go)

import groovy.json.JsonSlurper
// Fully qualified `java.util.Base64` fails inside the Kotlin DSL script
// (`java` is a Project property there); import the class instead.
import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Kotlin Gradle Plugin — required because android.builtInKotlin=false in
    // gradle.properties (Flutter template default for AGP 9 compatibility).
    id("org.jetbrains.kotlin.android")
}

/// Single source for the OIDC redirect URI (task 3.3): `oidc-config.json`
/// next to this `android/` dir when present, else the `OIDC_REDIRECT_URI`
/// environment value, else the canonical dev default.
fun oidcRedirectUriFromConfig(): String {
    val configFile = rootProject.file("../oidc-config.json")
    if (configFile.isFile) {
        @Suppress("unchecked_cast")
        val parsed = JsonSlurper().parse(configFile) as Map<String, Any?>
        val fromFile = (parsed["OIDC_REDIRECT_URI"] as String?).orEmpty()
        if (fromFile.isNotBlank()) return fromFile
    }
    return System.getenv("OIDC_REDIRECT_URI")
        .orEmpty()
        .ifEmpty { "breakdown://auth/callback" }
}

// Single build input for the OIDC redirect (issue #419, option 2b):
// read ONCE at script top level so both `defaultConfig` (validation) and
// the flavor blocks (per-flavor scheme derivation) consume the SAME value.
// `oidc-config.json` next to this `android/` dir when present, else the
// `OIDC_REDIRECT_URI` environment value, else the canonical dev default.
val oidcRedirectUri = oidcRedirectUriFromConfig()
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
// An explicitly passed `-PoidcRedirectScheme=...` must agree with the
// derived BASE scheme — a mismatch fails the build instead of shipping a
// native registration the Dart configuration can never reach. The property
// targets the base (prod) scheme; the dev flavor derives deterministically
// below, so one agreement proves both flavors.
val explicitScheme = project.findProperty("oidcRedirectScheme") as String?
if (explicitScheme != null && explicitScheme != oidcRedirectScheme) {
    throw GradleException(
        "oidcRedirectScheme property ('$explicitScheme') does not " +
            "match the scheme derived from OIDC_REDIRECT_URI " +
            "('$oidcRedirectScheme'). Pass the same OIDC_REDIRECT_URI " +
            "to Gradle and --dart-define."
    )
}
// Dev-scheme derivation (issue #419, option 2b): the dev flavor ships a
// DISTINCT application ID (`applicationIdSuffix = ".dev"` below) so a
// local dev install coexists with a published prod install (no
// certificate-mismatch uninstall dance). To keep the browser redirect
// unambiguous while both are installed, the dev scheme is the base scheme
// with a `-dev` suffix: `breakdown://` → `breakdown-dev://` — exactly one
// app ever receives the IdP redirect. http/https schemes are exempt
// (App-Links-style URIs are host-based, not scheme-ambiguous, and must not
// be mangled). The Dart side (`deriveOidcRedirectUri` in
// `lib/app_config.dart`) mirrors this derivation textually.
fun devRedirectScheme(scheme: String): String {
    if (scheme.equals("http", true) || scheme.equals("https", true)) return scheme
    // Idempotent: a scheme already carrying the dev suffix passes through
    // (must never become `-dev-dev`).
    if (scheme.lowercase().endsWith("-dev")) return scheme
    return "${scheme}-dev"
}
val oidcDevRedirectScheme = devRedirectScheme(oidcRedirectScheme)

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
        // Prod application ID — the published chain (alpha → stable) updates
        // in place under this ID. The dev flavor derives its own ID via
        // `applicationIdSuffix` below (issue #419, option 2b) so a local dev
        // build coexists with a published prod build instead of failing the
        // install with a certificate mismatch (debug-signed vs project key).
        applicationId = "rs.breakdown.frontend_flutter"
        // OIDC redirect scheme (spec `flutter-auth-shell`, task 3.3): the
        // BASE scheme is validated and checked against an explicit
        // `-PoidcRedirectScheme=` at the script top level; the per-flavor
        // placeholder is set in the flavor blocks (prod = base scheme,
        // dev = base scheme + `-dev`), so the native deep-link registration
        // always matches exactly one installed application ID.
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

    // dev/prod Gradle flavors (change add-android-release-workflow; the
    // flutter-scaffold spec scenario requires `flutter build apk --flavor
    // dev` to succeed). Since issue #419 (option 2b) the flavors ship
    // DISTINCT application IDs (`rs.breakdown.frontend_flutter` vs
    // `rs.breakdown.frontend_flutter.dev`) AND distinct redirect schemes — a local
    // dev install coexists with a published prod install, and the OAuth
    // redirect scheme always resolves to exactly one installed app. The
    // flavor only selects the Gradle build variant — the Dart flavor is
    // decided by the entrypoint (`lib/main.dart` = dev,
    // `lib/main_prod.dart` = prod) and the `--dart-define` set passed
    // alongside it. The release workflow builds
    // `--flavor prod -t lib/main_prod.dart`; the dev flavor is
    // dev-runtime-only and is never published.
    flavorDimensions += "channel"
    productFlavors {
        create("dev") {
            dimension = "channel"
            // Distinct application ID (issue #419, option 2b): a local dev
            // install no longer collides with a published prod install on
            // signing material (debug key vs project key).
            applicationIdSuffix = ".dev"
            // Scoped redirect scheme: `breakdown://` → `breakdown-dev://`
            // (see the top-level derivation) so the browser redirect can
            // never resolve to two installed apps. The dev IdP client
            // registration must allowlist the derived URI
            // (`docs/self-hosting.md` §4).
            manifestPlaceholders["oidcRedirectScheme"] = oidcDevRedirectScheme
            // Local dev runtime: without the CI release signing config,
            // the dev-flavor RELEASE build type falls back to debug
            // signing so `flutter run --release --flavor dev` keeps
            // working. The dev flavor is NEVER published (spec
            // flutter-release-artifacts), and the build type's own
            // signingConfig (set below when the release config exists)
            // takes precedence over this fallback.
            signingConfig = signingConfigs.getByName("debug")
        }
        create("prod") {
            dimension = "channel"
            // Published channel (GitHub Releases; D9 single-key signing).
            // Deliberately NO signingConfig here: without the CI release
            // signing config the prod release build is UNSIGNED — a
            // decisive unsigned artifact that can never be mistaken for
            // a signed release (no debug-keystore fallback, per design D9).
            // Redirect scheme = the validated BASE scheme.
            manifestPlaceholders["oidcRedirectScheme"] = oidcRedirectScheme
        }
    }

    signingConfigs {
        // Release signing (change add-android-release-workflow, spec
        // flutter-release-signing): material flows through environment
        // variables / CI secrets — NEVER the tree, and never hardcoded.
        //   * KEYSTORE_FILE — pre-decoded keystore path (the CI workflow
        //     decodes KEYSTORE_BASE64 into $RUNNER_TEMP), or
        //   * KEYSTORE_BASE64 — decoded here into build/keystore/ when
        //     KEYSTORE_FILE is absent, plus
        //   * KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD.
        // Partial configuration fails LOUDLY (a silently unsigned or
        // half-configured release build is worse than a failed one). With
        // NO signing variables at all, the config is simply absent and the
        // release build type below falls back per flavor.
        val envKeystoreFile = System.getenv("KEYSTORE_FILE")
        val envKeystoreBase64 = System.getenv("KEYSTORE_BASE64")
        val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
        val envKeyAlias = System.getenv("KEY_ALIAS")
        val envKeyPassword = System.getenv("KEY_PASSWORD")
        // KEYSTORE_FILE and KEYSTORE_BASE64 are ALTERNATIVE sources for the
        // keystore file (the CI workflow passes exactly one); the three
        // credential variables must travel together with exactly one of
        // them.
        val keystoreSources = listOfNotNull(envKeystoreFile, envKeystoreBase64).size
        val credentials = listOfNotNull(envKeystorePassword, envKeyAlias, envKeyPassword).size
        require((keystoreSources == 0 && credentials == 0) || (keystoreSources == 1 && credentials == 3)) {
            "Release signing is only partially configured: set ALL of " +
                "KEYSTORE_FILE or KEYSTORE_BASE64 (exactly one) plus " +
                "KEYSTORE_PASSWORD, KEY_ALIAS and KEY_PASSWORD — or none " +
                "of them (the build then falls back to the per-flavor " +
                "release signing below)."
        }
        if (keystoreSources == 1) {
            create("release") {
                storeFile = if (envKeystoreBase64 != null) {
                    val decoded = layout.buildDirectory
                        .file("keystore/release.keystore").get().asFile
                    decoded.parentFile.mkdirs()
                    decoded.writeBytes(
                        Base64.getDecoder().decode(envKeystoreBase64)
                    )
                    decoded
                } else {
                    file(envKeystoreFile!!)
                }
                storePassword = envKeystorePassword
                keyAlias = envKeyAlias
                keyPassword = envKeyPassword
                // APK Signature Scheme v3 (Proof-of-Rotation lineage):
                // makes the FIRST v3-signed release the lineage root, so a
                // future planned key rotation (e.g. to a post-quantum
                // algorithm once Android packaging supports it) can install
                // over existing installs WITHOUT uninstall. Verified against
                // the workflow fingerprint gate
                // (docs/release-signing-key-custody.md §6.1). v2 stays
                // enabled alongside — apksigner/AGP sign with both schemes.
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // CI (release workflow, `release` environment): signs with the
            // project keystore (signingConfig "release" above, created only
            // when ALL signing env vars are present). Absent → left unset
            // here, so the per-flavor signing below applies (dev → debug
            // fallback, prod → deliberately unsigned).
            signingConfigs.findByName("release")?.let {
                signingConfig = it
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
