// Root build file.
//
// Every plugin the build uses is declared here with `apply false`, and the
// versions come from the `pluginManagement` block in settings.gradle.kts so they
// are still stated once.
//
// Declaring them here rather than only in the modules is not tidiness. Gradle
// loads a plugin per classloader, and `:wire` asking for the Kotlin JVM plugin
// while `:app` asks for the Kotlin Android plugin loads Kotlin twice — which
// Gradle warns about as unsupported and liable to break the build. Naming both
// in the root gives them one classloader.
//
// The cost is that a module-less machine resolves the Android plugin markers it
// will never apply. That is one download, not a per-build tax, and it buys a
// build that is not relying on a warning staying harmless.

plugins {
    kotlin("jvm") apply false
    kotlin("android") apply false
    kotlin("plugin.serialization") apply false
    id("org.jetbrains.kotlin.plugin.compose") apply false
    id("com.android.application") apply false
}
