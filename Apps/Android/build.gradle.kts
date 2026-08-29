// Root build file. Plugin versions are declared here and applied per module, so
// the two modules cannot drift onto different Kotlin releases.

plugins {
    kotlin("jvm") version "2.0.21" apply false
    kotlin("plugin.serialization") version "2.0.21" apply false
}
