# 主机镇 iOS App

`https://www.zhujitown.com` 的原生 iOS 客户端（WordPress REST API 驱动），
**Swift 5 + SwiftUI 编写，零第三方依赖**，打开 `ZhuJiTown.xcodeproj` 即可编译。

对应的 Android 版本在同目录的 `../zhujitown-android/`。

---

## 一句话说明：IPA 怎么来

> iOS App **只能在 macOS + Xcode 上编译**，Windows 上编译不了 IPA，这是 Apple 的工具链限制，绕不过去。

项目里已经配好了完整的构建链路，挑一条走：

| 方式 | 环境要求 | 命令 | 产物 |
|---|---|---|---|
| **Mac 本地直接编译**（最快） | 一台 Mac + Xcode 15+ | `bash scripts/build_unsigned_ipa.sh` | 未签名 IPA，用 AltStore / Sideloadly / 巨魔装到手机 |
| **自己的证书签名** | Mac + Apple 开发者账号 | `bash scripts/build_signed_ipa.sh development` | 真签名 IPA，可直接分发给已注册设备 |
| **GitHub Actions 云编译**（推荐，无需 Mac） | 推到 GitHub 仓库 | Actions → `构建 iOS IPA` → Run workflow | workflow 里下载 IPA 产物 |

三种方式我都写好了脚本，Mac 被国内政策限制的部分不用你处理。

---

## 功能对照（与 Android 版一致 + iOS 原生特性）

| 模块 | 说明 |
|---|---|
| 首页 | 头条大图卡 + 文章流，横向分类筛选条（带文章数），下拉刷新，滚动到底自动续页 |
| 搜索 | 导航栏搜索框，输入防抖 0.45s，`?search=` 全文检索（商家名 / 机型都能搜） |
| 分类 | 网格分类页 + 各分类文章流；管理员模式下额外有「草稿箱」入口 |
| 详情 | **纯原生渲染**，无 WebView：目录导航、阅读进度条、相关阅读、上一篇 / 下一篇、评论列表 |
| 正文渲染 | HTML 解析成数据块后逐块画原生控件：标题带色条、原生表格、原生图片查看器、引用卡、代码块 |
| 站内链接 | `/3149.html`、`?p=1234` 这类站内链接直接在 App 内 push 打开，不跳出 |
| 站外链接 | aff 推广外链走 `SFSafariViewController`（保 Cookie、能返回 App），不影响转化 |
| 收藏 | 本地收藏 + 正文离线缓存，断网可读；左滑删除；收藏内二次搜索 |
| 图片查看器 | 双击放大、双指缩放、下滑关闭、多图左右翻页 |
| 设置 | 站点地址、管理员凭据（草稿箱）、正文字号实时预览、图片加载策略（始终 / 仅 Wi-Fi / 无图）、深浅色、缓存管理 |
| Deep Link | Safari 输入 `zhujitown://post/3149` 直接唤起 App 打开该文章 |

## 为什么不是网页壳

全工程 `grep -r "WebKit\|WKWebView\|UIViewRepresentable.*UIWebView"` 结果为 **0**。
正文处理链路是：`REST API 取 HTML` → `MiniHTML 解析成 DOM` → `ArticleParser 拆成 Block` → `SwiftUI 原生控件渲染`。

其中：

- **表格**是真实单元格（保留站点 `td` 的居中设置、可横滑、单元格内链接可点）
- **行内样式**支持加粗 / 斜体 / `<u>` 下划线 / 链接（富文本走 `UITextView`，支持选中复制）
- **图片**按真实宽高比撑开，不是固定占位比例

## 目录结构

```
zhujitown-ios/
├── ZhuJiTown.xcodeproj/          # Xcode 工程（双击打开）
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/ZhuJiTown.xcscheme
├── ZhuJiTown/
│   ├── Info.plist                # URL Scheme / ATS / 启动屏
│   ├── Resources/Assets.xcassets # AppIcon（脚本自动生成的多尺寸渐变图标）
│   ├── App/ZhuJiTownApp.swift    # @main 入口
│   ├── Model/Models.swift        # Post / Category / Comment / Media…
│   ├── Network/
│   │   ├── AppConfig.swift       # 站点地址与凭据
│   │   ├── Prefs.swift           # 偏好设置 + 离线缓存
│   │   └── WPClient.swift        # REST 客户端（重试 / Basic Auth / 分页）
│   ├── Parser/
│   │   ├── MiniHTML.swift        # 轻量 HTML DOM（自研，无外部依赖）
│   │   └── ArticleParser.swift   # HTML → 渲染块
│   ├── ViewModel/                # AppModel（收藏/分类）、FeedModel（分页流）
│   └── UI/                       # 全部 SwiftUI 页面与组件
├── scripts/
│   ├── make_xcodeproj.py         # 增删 Swift 文件后可重新生成工程
│   ├── build_unsigned_ipa.sh     # 免证书 IPA
│   └── build_signed_ipa.sh       # 证书签名 IPA
├── ExportOptions-*.plist         # development / adhoc / appstore 导出配置
└── .github/workflows/ios.yml     # macOS 云编译
```

## 构建参数

| 项 | 值 |
|---|---|
| 最低系统 | iOS 16.0 |
| Swift 版本 | 5.0（Xcode 15 默认 5.9） |
| Bundle ID | `com.zhujitown.app` |
| 设备 | iPhone / iPad（Universal） |
| 依赖 | 无（不引第三方库，不放 SPM/CocoaPods） |
| 代码签名 | Automatic（Xcode 登录 Apple ID 即可跑真机） |

## 详细构建步骤

### 1) Mac 本地（未签名 IPA）

```bash
git clone <你的仓库> && cd zhujitown-ios
bash scripts/build_unsigned_ipa.sh
```

产物：`outputs/ZhuJiTown-v1.0.0-unsigned.ipa`

安装方式：

- **AltStore / SideStore**：打开 App → My Apps → `+` → 选 ipa（会用你的 Apple ID 免费签名，7 天有效期，AltServer 可自动续）
- **Sideloadly**：连手机 → 选 ipa → Start
- **巨魔 / TrollStore**（iOS 14~16.6.1）：直接装，永不过期
- **越狱**：Filza / AppSync 直接安装

### 2) Mac 本地（有开发者账号）

```bash
export TEAM_ID=你的TeamID     # 可选，不填用 Xcode 里的自动签名
bash scripts/build_signed_ipa.sh development   # 或 adhoc / appstore
```

`development` 给已注册 UDID 的设备用；`adhoc` 批量分发；`appstore` 上架 TestFlight / App Store。

### 3) GitHub Actions（没有 Mac 也能出 IPA）

把整个 `zhujitown-ios/` 推到 GitHub 仓库 → Actions → **构建 iOS IPA** → Run workflow → 选 `unsigned` → 跑完在 Artifacts 里下载 IPA。

想出签名包需要额外配 4 个 Secrets：

| Secret | 内容 |
|---|---|
| `IOS_SIGNING_CERT_P12` | 开发者证书 `.p12` 的 base64（`base64 -i cert.p12`） |
| `IOS_SIGNING_CERT_PASSWORD` | 证书导出密码 |
| `IOS_PROVISIONING_PROFILE` | 描述文件 `.mobileprovision` 的 base64 |
| `IOS_TEAM_ID` | 开发者团队 ID |

## 改代码后重新生成工程

如果新增 / 删除了 Swift 文件：

```bash
python3 scripts/make_xcodeproj.py
```

脚本会重新扫描 `ZhuJiTown/` 下的源码目录，重建 `project.pbxproj`、AppIcon 与 Info.plist。

## 账号登录 / 注册（对齐安卓）

工程内**没有任何内置凭据**。App 支持三条路径，`AuthClient` 启动时自动探测：

| 优先级 | 后端 | 条件 | 能力 |
|---|---|---|---|
| 1 | ZhuJiTown Auth 插件 | `/wp-json/zhujitown/v1/ping` 返回 200 | 登录 + 注册 + 找回密码 |
| 2 | JWT Authentication 插件 | `/wp-json/jwt-auth/v1/token` 存在 | 登录 |
| 3 | WordPress 应用密码 | 无需插件 | 登录（拿 `users/me?context=edit` 判定权限） |

入口：「我的」→ 账号 → `AccountView`（登录 / 注册 / 找回密码 / 退出）。
会话存 UserDefaults（`PrefKey.session`），随 App 重装清除。

服务端插件在 `../zhujitown-auth/` 目录，装上才能用 App 内注册。

## 安全提示

- 令牌落在本机 UserDefaults，**不进版本库、不随包分发**
- 服务端令牌由站点 `AUTH_SALT` 派生的 HMAC 密钥签名，站点外无法伪造；改一次 `AUTH_SALT` 即可全员下线
- 登录接口有 IP 级限流（5 分钟 10 次）

## 已知限制

- Universal Link（`https://www.zhujitown.com/xxx.html` 直接唤起 App）需要在站点根目录放 `apple-app-site-association` 文件，并且不能用 `/#` 重定向；目前走自定义 Scheme `zhujitown://post/<id>` 兜底。如果你确认已通管局 ICP 备案并且域名已加到 Apple 的 Associated Domains，我再补 Universal Link 部分。
- 评论只能读不能发：WordPress 匿名发评论通常需要站点开启 REST 写入权限且要做防垃圾的手段，需要时我再补一个原生评论框。
- AppIcon 是脚本生成的纯色渐变图，上架前建议换成带「主机镇」字样的正式图标。
