# 主机镇 Android App

`https://www.zhujitown.com` 的原生安卓客户端（WordPress REST API 驱动），Kotlin + Jetpack Compose 编写。

> **不是网页壳。** 正文由 `ArticleParser`（Jsoup）解析成数据块，再用 Compose 原生组件渲染：
> 原生表格、原生图片查看器、原生目录导航、原生链接跳转。工程里没有一个 WebView。

## 已实现功能

| 模块 | 说明 |
|---|---|
| 首页 | 首条大图头条卡 + 文章流，顶部横向分类筛选，下拉刷新，滚动到底自动续页 |
| 分类 | 全部分类网格（含文章数），点进去看该分类文章；管理员模式下有「草稿箱」入口 |
| 搜索 | 按关键词检索（走 WP `?search=`），支持商家名/机型 |
| 详情-正文 | 原生渲染：标题/正文/图片/表格/列表/引用/代码块；字号跟随设置，深色模式 |
| 详情-表格 | 站点正文大量表格 → 原生单元格 + 横向滚动 + 保留原站居中对齐，可点链接 |
| 详情-图片 | 原生查看器：单击关闭、双击放大、双指缩放拖动 |
| 详情-目录 | 自动抽取 h2/h3 生成目录，悬浮按钮打开，点击滚动定位 |
| 详情-延伸 | 相关阅读（同分类 6 篇）、上一篇/下一篇、评论列表（含头像） |
| 站内外链 | 正文链接走原生 LinkAnnotation：站内文章（`/3149.html`）App 内打开，站外推广链接走 Chrome 自定义标签页 |
| 收藏 | 本地收藏 + 正文离线缓存，断网也能看 |
| 设置 | 站点地址、管理员凭据、主题（跟随/浅色/深色）、正文字号、无图模式、清除缓存 |
| Deep Link | 在手机浏览器打开站点文章链接，可直接唤起 App |

## 环境要求

- Android Studio Koala(2024.1.1) 或更高（自带 JDK 17 + Gradle）
- minSdk 26（Android 8.0+），targetSdk 34

## 快速开始

1. 用 Android Studio **Open** 这个目录（不是单独打开 app 目录）
2. 如果提示 `local.properties` 缺少 SDK 路径，studio 会自己写；命令行构建则手动加一行  
   `sdk.dir=C\:\\Users\\<你的用户名>\\AppData\\Local\\Android\\Sdk`
3. Sync → Run。命令行构建：

```bash
./gradlew assembleDebug     # 调试包
./gradlew assembleRelease   # 发布包（未签名）
```

## 站点与密钥配置

默认已经填好站点与管理员凭据，位于 `local.properties`（**已在 .gitignore 中，不会进版本库**）：

```properties
SITE_URL=https://www.zhujitown.com
ADMIN_USER=admin
ADMIN_APP_PASSWORD=你的应用密码
```

构建时会被注入 `BuildConfig.DEFAULT_*`，App 首次启动即直连站点。  
运行时也可以在 App 内「设置」页修改站点地址和凭据（保存在手机本地，不会写回代码）。

> 凭据只用于读取草稿（`status=draft`）。若要发布到应用市场，建议把 `local.properties` 里的
> `ADMIN_USER`/`ADMIN_APP_PASSWORD` 清空后再打包，避免管理员凭据被打进 APK。

## 目录结构

```
app/src/main/java/com/zhujitown/app/
├── App.kt                     # Application，配置 Coil 图片缓存
├── MainActivity.kt            # 入口，处理文章链接 deep link
├── data/
│   ├── Models.kt              # WP REST 数据模型 + 封面/分类辅助方法
│   ├── Api.kt                 # Retrofit 接口、Basic Auth、超时与重试
│   ├── Prefs.kt               # 站点、凭据、主题、字号、收藏
│   ├── Cache.kt               # 正文离线缓存
│   └── AppViewModel.kt        # 列表/分类/搜索/设置状态
├── ui/
│   ├── AppRoot.kt             # 底部导航 + 搜索 + 分类筛选
│   ├── theme/Theme.kt         # Material3 主题
│   ├── components/
│   │   ├── PostCard.kt        # 列表卡片
│   │   ├── PostList.kt        # 下拉刷新 + 分页 + 头条大卡
│   │   ├── ArticleRenderer.kt # 块 → 原生组件（表格/图片/列表/引用/富文本链接）
│   │   └── ImageViewer.kt     # 原生缩放图片查看器
│   └── screens/               # 详情（原生渲染）、分类、收藏、设置
└── util/
    ├── ArticleParser.kt       # HTML → 原生渲染块（Block/Inline 模型）
    └── Html.kt                # 实体解码、纯文本摘要、日期格式化
```

## 站点适配要点

- 站点 PHP 渲染较慢，接口偶发 502/超时 → OkHttp 20s 连接 / 60s 读取 + 3 次重试
- 列表请求带 `_embed`，一次拿到封面图与分类名，省掉 N+1 请求
- 正文保留 inline style（站点表格靠 `text-align:center` 居中），CSS 只做移动端兜底
- 图片统一 `max-width:100%; height:auto`，去掉 WP 写死的 width/height
- 深色模式下正文配色单独走一套 CSS 变量
- `/wp-json/` 若被缓存插件拦截，App 会提示 403 并给出排查方向

## 云编译 APK（无需本地 Android Studio）

把目录推到 GitHub 仓库后，`.github/workflows/android.yml` 会在每次 push / 手动触发时编译
并上传 `app-release.apk` 到 Actions 产物。若要用管理员凭据，在仓库 Settings → Secrets 里加
`ADMIN_USER`、`ADMIN_APP_PASSWORD`、`SITE_URL` 三个 secret（没有则用默认值）。

发布签名：在 workflow 里补 `signingConfig` 或使用 `r0adkll/sign-android-release` action。
