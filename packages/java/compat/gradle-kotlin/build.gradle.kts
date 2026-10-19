import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.4.21"
}

repositories {
    mavenLocal() // packages/java installed with ./mvnw install
    mavenCentral()
}

val suggestedtestsVersion = providers.gradleProperty("suggestedtestsVersion").get()

dependencies {
    testImplementation("io.github.lesterkaufungen:suggestedtests:$suggestedtestsVersion")
    testImplementation(platform("org.junit:junit-bom:5.14.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testImplementation("junit:junit:4.13.2")
    testRuntimeOnly("org.junit.vintage:junit-vintage-engine") // runs the JUnit 4 rule test
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// Java 8 bytecode, like Android's oldest toolchains.
kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_1_8) }
}
java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
}

tasks.test {
    useJUnitPlatform()
    testLogging { events("passed", "skipped", "failed"); showStandardStreams = false }
}
