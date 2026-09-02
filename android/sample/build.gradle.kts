plugins {
    id("com.android.application")
    kotlin("android")
}

android {
    namespace = "io.github.xesam.android.localasset.sample"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.xesam.android.localasset.sample"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "0.0.1"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    testOptions {
        unitTests.isIncludeAndroidResources = false
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets", "../../shared")
        }
    }
}

kotlin {
    jvmToolchain(21)
}

/*
  SampleFlowContractTest 用 File("../../shared/demo/...") 直读演示页做断言，
  而这些文件不在测试任务的声明输入里 —— 改完 HTML 直接跑 ./gradlew test 会
  报 UP-TO-DATE 假绿。声明为输入后，Gradle 感知到 HTML 变化即重跑。

  scripts/test.sh 一直带 --rerun-tasks，故正式门禁不受此影响；这里修的是
  开发者本地手跑时的陷阱。
*/
tasks.withType<Test>().configureEach {
    inputs.dir(rootProject.file("../shared/demo"))
        .withPathSensitivity(PathSensitivity.RELATIVE)
        .withPropertyName("sharedDemoPages")
}

dependencies {
    implementation(project(":localasset-core"))
    implementation(project(":localasset-webview"))
    implementation("androidx.activity:activity-ktx:1.9.2")
    testImplementation(kotlin("test"))
}
