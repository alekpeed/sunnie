// The Android side of Sunnie Days (ADR-035).
//
// Two modules, split by what can be verified where. `wire` is pure Kotlin on the
// JVM: it holds the move contract and its tests, and it builds and runs without
// an Android SDK — which means it can be checked on an ordinary machine rather
// than only on a CI runner. `app` is the Android client and needs the SDK, so it
// is built in CI.
//
// The split is the same reasoning as ADR-032, which pulled the shared Swift
// package off Apple so a third of that codebase could be compiled by someone
// without a Mac. The contract is the part most worth being able to run.

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    // One place for every plugin version, so the modules cannot drift onto
    // different Kotlin releases — and, because these are only resolved when a
    // project actually asks for the plugin, the Android ones cost nothing on a
    // machine where `:app` is excluded for want of an SDK.
    val kotlinVersion = "2.0.21"
    plugins {
        kotlin("jvm") version kotlinVersion
        kotlin("android") version kotlinVersion
        kotlin("plugin.serialization") version kotlinVersion
        // Since Kotlin 2.0 the Compose compiler ships with Kotlin itself and is
        // applied as its own plugin, versioned in lockstep with the release
        // above rather than independently.
        id("org.jetbrains.kotlin.plugin.compose") version kotlinVersion
        id("com.android.application") version "8.7.3"
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SunnieDaysAndroid"

include(":wire")

// `app` is included only where it can actually be built.
//
// Configuring an Android module without an SDK fails the whole build at
// configuration time — including `:wire:test`, which has no Android dependency
// and is the suite most worth being able to run anywhere. Making the include
// conditional keeps the contract tests runnable on a plain JDK, which is the
// entire reason the two modules are split.
//
// CI runners have the SDK, so `app` is included there and its absence locally is
// visible in the log rather than silent.
val androidSdk = sequenceOf(
    System.getenv("ANDROID_HOME"),
    System.getenv("ANDROID_SDK_ROOT"),
    file("local.properties")
        .takeIf { it.isFile }
        ?.readLines()
        ?.firstOrNull { it.startsWith("sdk.dir=") }
        ?.substringAfter("="),
).filterNotNull().firstOrNull { it.isNotBlank() && file(it).isDirectory }

if (androidSdk != null) {
    include(":app")
} else {
    logger.lifecycle(
        "No Android SDK found (ANDROID_HOME, ANDROID_SDK_ROOT, or sdk.dir in " +
            "local.properties). Skipping :app; :wire still builds and tests."
    )
}
