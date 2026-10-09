# ZhuJiTown Auth（主机镇 App 登录注册插件）

给主机镇 iOS / Android App 提供**账号登录与注册**接口。

- WordPress 自带认证 API，无第三方依赖（`wp_authenticate` / `wp_insert_user` / `wp_update_user` / `retrieve_password`）
- 不建数据库表、不改用户表结构、不动主题
- 令牌为 HMAC-SHA256 自签名（密钥取自站点 `AUTH_SALT`），无状态、可过期

## 一、安装（二选一）

### 方式 A：上传插件（推荐）

1. 下载 `zhujitown-auth.zip`
2. WordPress 后台 → **插件 → 安装插件 → 上传插件** → 选择 zip → 安装
3. 点击**启用**

### 方式 B：手动 FTP/SFTP

把 `zhujitown-auth` 整个目录上传到 `wp-content/plugins/`，再进后台启用。

### 方式 C：不装插件（临时）

把下面这行加到主题 `functions.php` 末尾也行，但升级主题会丢：

```php
require_once WP_CONTENT_DIR . '/plugins/zhujitown-auth/zhujitown-auth.php';
```

## 二、开启注册（可选）

默认 WordPress 是**关闭开放注册**的。要允许 App 内注册：

后台 → **设置 → 常规** → 勾选 **任何人都可以注册** → 保存

新注册用户默认角色为 `subscriber`（订阅者），权限最小，安全。

> 不勾选也能用：App 登录页会自动隐藏「注册」按钮，只保留登录。

## 三、新增的接口

命名空间：`zhujitown/v1`，完整地址形如 `https://www.zhujitown.com/wp-json/zhujitown/v1/login`

| 方法 | 路径 | 说明 | 参数 |
|---|---|---|---|
| GET/POST | `/ping` | 探测插件是否启用 | — |
| POST | `/login` | 登录 | `username`（用户名或邮箱）、`password` |
| POST | `/register` | 注册 | `username`、`email`、`password` |
| POST | `/refresh` | 令牌续期 | Bearer token |
| GET | `/me` | 当前用户信息 | Bearer token |
| POST | `/logout` | 注销 | Bearer token |
| POST | `/lost-password` | 找回密码（发邮件） | `user_login` |
| POST | `/profile` | 改昵称/邮箱/密码 | `display_name`、`email`、`new_password` + `current_password` |

### 登录成功返回

```json
{
  "token": "eyJ1aWQiOjEs...  .5Z3kQ8...",
  "expire_at": "2026-11-09T06:00:00+00:00",
  "user": {
    "id": 1,
    "username": "admin",
    "display_name": "主机镇",
    "email": "a@b.com",
    "roles": ["administrator"],
    "can_manage": true,
    "avatar": { "24": "...", "48": "...", "96": "..." }
  }
}
```

后续请求带上：`Authorization: Bearer <token>`

App 里「草稿箱」只对 `can_manage = true`（可编辑文章的角色：管理员/编辑/作者）开放。

## 四、安全设计

| 项目 | 做法 |
|---|---|
| 密码 | 走 WordPress 自带校验（`wp_authenticate`），**不接触明文存储** |
| 令牌 | HMAC-SHA256 签名，密钥派生自 `AUTH_SALT`，站点外无法伪造 |
| 有效期 | 30 天，到期 App 需重新登录 |
| 防爆破 | 同 IP 登录 5 分钟内最多 10 次失败，超出返回 429 |
| 注册 | 受站点 `users_can_register` 开关控制；注册成功后走 WP 自带通知邮件 |
| CORS | 只对 REST 响应头做放行，不开放任意来源写权限 |

> 令牌是**无状态**的，服务端不记录已签发令牌，因此无法单点吊销。
> 需要强制下线时，把 `wp-config.php` 里的 `AUTH_SALT` 改一个值，全站令牌立即失效。

## 五、卸载

后台停用并删除插件即可，**不留任何数据**。

> 如果你之前在 App 里用了「管理员应用密码」那套旧方案，删除插件不影响它——那是 WordPress 核心自带的 Application Passwords，与本插件无关。
