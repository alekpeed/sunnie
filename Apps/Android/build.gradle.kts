// Root build file.
//
// Deliberately empty of plugin declarations: versions live in the
// `pluginManagement` block of settings.gradle.kts, so a module asks for a plugin
// by name and the version is decided in one place. Declaring them here with
// `apply false` would also make Gradle resolve the Android plugin markers on a
// machine that has no Android SDK and has therefore excluded `:app` — which
// turns an offline `:wire:test` into a network round trip for nothing.
