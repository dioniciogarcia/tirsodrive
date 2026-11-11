import java.util.Properties
import java.io.FileInputStream

val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.tirso.tirsodrive.wear"
    compileSdk = 36

    defaultConfig {
        // Same id as the phone app, so the Wear Data Layer links the two (they run on different devices).
        applicationId = "com.tirso.tirsodrive"
        minSdk = 30
        targetSdk = 34
        versionCode = (project.findProperty("appVersionCode") as String?)?.toInt() ?: 1400
        versionName = (project.findProperty("appVersionName") as String?) ?: "0.14.0"
        ndk { abiFilters += listOf("arm64-v8a", "armeabi-v7a") }
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file("app/" + keyProps.getProperty("storeFile").substringAfterLast('/'))
            storePassword = keyProps.getProperty("storePassword")
            keyAlias = keyProps.getProperty("keyAlias")
            keyPassword = keyProps.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    packaging { jniLibs { useLegacyPackaging = true } }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.09.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("net.java.dev.jna:jna:5.14.0@aar")
    implementation("com.google.zxing:core:3.5.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
