import com.vanniktech.maven.publish.SonatypeHost

plugins {
    id("com.android.library")
    kotlin("android")
    id("com.vanniktech.maven.publish")
}

android {
    namespace = "io.github.xesam.android.localasset.core"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    testOptions {
        unitTests.isIncludeAndroidResources = false
    }
}

kotlin {
    jvmToolchain(21)
}

dependencies {
    // runBlocking bridge for AsyncResourceLoader (design.md §9.3). Pure Kotlin, not Android
    // framework — keeps the engine framework-free while giving async data sources a typed hook.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    testImplementation(kotlin("test"))
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}

tasks.withType<Test>().configureEach {
    systemProperty("localasset.repo.root", rootProject.projectDir.parentFile.absolutePath)
}

// --- Publishing (Maven Central Portal). Credentials are optional for build/test; only the
// publish/sign tasks require them. See android/gradle.properties for the property names. ---
mavenPublishing {
    coordinates(providers.gradleProperty("GROUP").get(), project.name, providers.gradleProperty("VERSION_NAME").get())
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL)
    if (providers.gradleProperty("signingKey").orNull != null) {
        signAllPublications()
    }
    pom {
        name = "LocalAsset Core"
        description = "Protocol-agnostic client resource resolution engine — pure Kotlin, no Android framework dependencies."
        inceptionYear = "2026"
        url = "https://github.com/xesam/local-asset"
        licenses {
            license {
                name = "Apache-2.0"
                url = "https://www.apache.org/licenses/LICENSE-2.0.txt"
            }
        }
        developers {
            developer {
                id = "xesam"
                name = "xesam"
                url = "https://github.com/xesam"
            }
        }
        scm {
            url = "https://github.com/xesam/local-asset"
            connection = "scm:git:github.com/xesam/local-asset.git"
            developerConnection = "scm:git:ssh://github.com/xesam/local-asset.git"
        }
    }
}
