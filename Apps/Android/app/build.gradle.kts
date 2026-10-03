// The Android client (ADR-035).
//
// Needs the Android SDK, so it is included only where one is present — see the
// conditional include in settings.gradle.kts. The rules it plays by live in
// `:wire`, which has no Android dependency and is tested on a plain JDK; this
// module is the part that has to be built on a runner.

plugins {
    id("com.android.application")
    kotlin("android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "days.sunnie.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "days.sunnie.android"
        // Android 8.0. Old enough to cover any phone likely to be in use and new
        // enough to avoid desugaring work for a two-person app.
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
    }

    buildTypes {
        debug {
            // The debug APK is what gets sideloaded, so it is not minified: a
            // stack trace from the one person testing it is worth more than the
            // size saving.
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    // Kotlin sources live under `kotlin/` here as they do in `:wire`, rather
    // than in `java/`.
    sourceSets["main"].kotlin.srcDir("src/main/kotlin")
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(project(":wire"))

    implementation(platform("androidx.compose:compose-bom:2024.10.01"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

    debugImplementation("androidx.compose.ui:ui-tooling")
}
