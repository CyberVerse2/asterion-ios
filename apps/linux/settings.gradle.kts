pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
        google()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
    }
}

rootProject.name = "AsterionLinux"

// Reuse the Android app's platform-free core as-is: same contracts,
// same paragraph rule, same API clients. No code is duplicated.
include(":core")
project(":core").projectDir = file("../android/core")

include(":desktop")
