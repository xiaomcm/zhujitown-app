import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// 读取 local.properties（站点地址 / 管理员凭据），避免把密钥硬编码进版本库
val localProps = Properties().apply {
    val f = rootProject.file("local.properties")
    if (f.exists()) {
        f.inputStream().use { load(it) }
    }
}
fun lp(key: String, default: String = ""): String =
    (localProps.getProperty(key) ?: System.getenv(key) ?: default).trim().trim('"')

android {
    namespace = "com.zhujitown.app"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.zhujitown.app"
        minSdk = 26
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"

        buildConfigField("String", "DEFAULT_SITE_URL", "\"${lp("SITE_URL", "https://www.zhujitown.com")}\"")
        // 不再内置任何管理员凭据：账号由用户在 App 内登录得到，令牌存本地 SharedPreferences
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            // 默认用 debug 签名，方便直接安装到手机；
            // 正式发布请改成自己的 keystore（signingConfigs 里配置 storeFile/storePassword/keyAlias/keyPassword）
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.15"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.10.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.4")

    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    debugImplementation("androidx.compose.ui:ui-tooling")

    // 网络
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-gson:2.11.0")
    implementation("com.google.code.gson:gson:2.11.0")

    // 图片
    implementation("io.coil-kt:coil-compose:2.6.0")

    // HTML 清洗 / 摘要提取
    implementation("org.jsoup:jsoup:1.18.1")

    // Chrome Custom Tabs（打开推广/购买链接）
    implementation("androidx.browser:browser:1.8.0")
}
