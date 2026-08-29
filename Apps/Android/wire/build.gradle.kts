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

kotlin {
    jvmToolchain(21)
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    testImplementation(kotlin("test"))
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("passed", "failed", "skipped") }
}
