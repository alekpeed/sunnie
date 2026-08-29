// The move contract, as plain Kotlin on the JVM.
//
// Deliberately no Android dependency. That is what lets these tests run on any
// machine with a JDK, and it is why this module holds the part of the client
// most worth being able to check quickly — the format the iPhone and the phone
// have to agree on.

plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
}

// Compiled by whatever JDK runs Gradle, but emitting Java 17 bytecode.
//
// Not a toolchain pin, deliberately. `app` consumes this module, and Android's
// D8 is the constraint: 17 is the highest bytecode level the Android toolchain
// supports without qualification, so a module targeting 21 would build fine on
// its own and fail only once the APK tried to dex it. Pinning the *target*
// rather than the toolchain also means this still builds on a machine that has
// only one JDK installed, which is the case on the container that runs these
// tests.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("passed", "failed", "skipped") }
}
