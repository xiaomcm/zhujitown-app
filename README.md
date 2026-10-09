# 主机镇 App（WordPress 原生客户端）

`https://www.zhujitown.com` 的原生移动客户端，**零 WebView**：Android 用 Jetpack Compose，iOS 用 SwiftUI，
正文由 REST 取回 HTML 后解析成数据块再逐块原生渲染。

```
zhujitown-android/   安卓工程（Kotlin + Compose，可直接 Android Studio 打开 / ./gradlew 编译）
zhujitown-ios/       iOS 工程（Swift 5 + SwiftUI，含真 Xcode 工程 + IPA 构建脚本）
zhujitown-auth/      WordPress 登录注册插件（服务端，给用户装机用）
.github/workflows/   云编译：Android APK + iOS IPA
outputs/             已编译产物（APK / 插件 zip）
```

## 一、账号登录 / 注册

**两个 App 都不再内置任何管理员凭据**。账号由用户在 App 内登录，令牌存本机。

自动降级三条路径（不用改代码，依站点实际情况选路）：

| 优先级 | 后端 | 判定 | 能力 |
|---|---|---|---|
| 1 | ZhuJiTown Auth 插件 | `/wp-json/zhujitown/v1/ping` 返回 200 | 登录 + **注册** + 找回密码 |
| 2 | JWT Authentication 插件 | `/wp-json/jwt-auth/v1/token` 存在 | 登录 |
| 3 | WordPress 应用密码 | 无需插件，WP 自带 | 登录 |

要让 App 内支持**注册**，给你的站点装 `zhujitown-auth` 插件（见该目录 README），
并在后台「设置 → 常规」勾选「任何人都可以注册」。

## 二、服务端插件

```
outputs/zhujitown-auth.zip   ← 后台「插件 → 安装插件 → 上传插件」
```

只用 WordPress 自带认证 API（`wp_authenticate` / `wp_insert_user` / `retrieve_password`），
不建库表、不动用户表、无第三方依赖。令牌为 HMAC-SHA256 自签名，密钥派生自站点 `AUTH_SALT`，30 天有效。

## 三、云编译

两个 workflow 都在仓库根目录（已写好，**推送到 GitHub 即自动触发**）：

| Workflow | 产物 | 触发 |
|---|---|---|
| `android.yml` | Release APK | push 或手点 Run workflow |
| `ios.yml` | IPA（unsigned / development / adhoc） | push 或手点选择模式 |

iOS 未签名 IPA 用 AltStore / Sideloadly / 巨魔安装即可免证书上机。

## 四、构建环境（Windows 本机已装）

JDK 17、Android SDK 34、Gradle 8.7、Swift 5.10.1 工具链都在 `~/.workbuddy/binaries/` 下，无需重复安装。
