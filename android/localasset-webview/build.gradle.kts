import com.vanniktech.maven.publish.SonatypeHost

plugins {
    id("com.android.library")
    kotlin("android")
    id("com.vanniktech.maven.publish")
}

android {
    namespace = "io.github.xesam.android.localasset.webview"
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
    api(project(":localasset-core"))
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation(kotlin("test"))
}

tasks.withType<Test>().configureEach {
    systemProperty("localasset.repo.root", rootProject.projectDir.parentFile.absolutePath)
}

mavenPublishing {
    coordinates(providers.gradleProperty("GROUP").get(), project.name, providers.gradleProperty("VERSION_NAME").get())
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL)
    if (providers.gradleProperty("signingKey").orNull != null) {
        signAllPublications()
    }
    pom {
        name = "LocalAsset WebView"
        description = "WebView bridge for LocalAsset — WebResourceResponse interception and CORS handling."
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
