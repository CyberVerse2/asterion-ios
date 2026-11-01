import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    application
}

val asterionVersion = (findProperty("asterion.version") as String?) ?: "0.1.0"
version = asterionVersion

kotlin {
    jvmToolchain(21)
    compilerOptions { jvmTarget = JvmTarget.JVM_17 }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

application {
    // Desktop entry point. The Compose Multiplatform UI lands here in phase 2;
    // until then this is a JVM shell proving core/ runs on Linux.
    mainClass.set("cloud.cyberverse.asterion.linux.MainKt")
    applicationName = "asterion"
    // So the installed launcher (and the AppImage) reports its own version.
    applicationDefaultJvmArgs = listOf("-Dasterion.version=$asterionVersion")
}

dependencies {
    implementation(project(":core"))
    implementation(libs.coroutines.core)
    implementation(libs.serialization.json)
    implementation(platform(libs.okhttp.bom))
    implementation(libs.okhttp)

    testImplementation(libs.junit)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.okhttp.mockwebserver)
}

tasks.test {
    javaLauncher = javaToolchains.launcherFor { languageVersion = JavaLanguageVersion.of(21) }
    systemProperty("asterion.contracts", rootDir.resolve("../../contracts").canonicalPath)
}
