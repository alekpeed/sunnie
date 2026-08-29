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
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "SunnieDaysAndroid"

include(":wire")
