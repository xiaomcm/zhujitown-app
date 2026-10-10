package com.zhujitown.app.data

import android.content.Context
import com.zhujitown.app.BuildConfig

class Prefs(context: Context) {

    private val sp = context.getSharedPreferences("zhujitown_prefs", Context.MODE_PRIVATE)

    var siteUrl: String
        get() = sp.getString(KEY_SITE, null)?.takeIf { it.isNotBlank() }
            ?: BuildConfig.DEFAULT_SITE_URL
        set(value) {
            sp.edit().putString(KEY_SITE, value.trim().trimEnd('/')).apply()
            ApiClient.invalidate()
        }

    // ---------------- 登录会话（用户自己在 App 内登录，不再内置任何管理员凭据）----------------

    /** 访问令牌：插件签发，或应用密码模式下的占位 */
    var token: String
        get() = sp.getString(KEY_TOKEN, null).orEmpty()
        set(value) {
            sp.edit().putString(KEY_TOKEN, value).apply()
            ApiClient.invalidate()
        }

    var uid: Int
        get() = sp.getInt(KEY_UID, 0)
        set(value) = sp.edit().putInt(KEY_UID, value).apply()

    var username: String
        get() = sp.getString(KEY_USERNAME, null).orEmpty()
        set(value) = sp.edit().putString(KEY_USERNAME, value).apply()

    var displayName: String
        get() = sp.getString(KEY_DISPLAY, null).orEmpty()
        set(value) = sp.edit().putString(KEY_DISPLAY, value).apply()

    var email: String
        get() = sp.getString(KEY_EMAIL, null).orEmpty()
        set(value) = sp.edit().putString(KEY_EMAIL, value).apply()

    var avatarUrl: String
        get() = sp.getString(KEY_AVATAR, null).orEmpty()
        set(value) = sp.edit().putString(KEY_AVATAR, value).apply()

    var roles: String
        get() = sp.getString(KEY_ROLES, null).orEmpty()
        set(value) = sp.edit().putString(KEY_ROLES, value).apply()

    /** 是否具备查看草稿的权限（管理员 / 编辑 / 作者） */
    var canManage: Boolean
        get() = sp.getBoolean(KEY_CAN_MANAGE, false)
        set(value) = sp.edit().putBoolean(KEY_CAN_MANAGE, value).apply()

    /** 令牌过期时间戳（毫秒），0 表示未知 */
    var expireAt: Long
        get() = sp.getLong(KEY_EXPIRE, 0L)
        set(value) = sp.edit().putLong(KEY_EXPIRE, value).apply()

    /** 登录后端：plugin（ZhuJiTown Auth 插件）/ apppass（WordPress 应用密码） */
    var authBackend: String
        get() = sp.getString(KEY_BACKEND, null).orEmpty()
        set(value) {
            sp.edit().putString(KEY_BACKEND, value).apply()
            ApiClient.invalidate()
        }

    /** 应用密码模式下需要长期保存的用户名，用于 Basic Auth */
    var basicUser: String
        get() = sp.getString(KEY_BASIC_USER, null).orEmpty()
        set(value) {
            sp.edit().putString(KEY_BASIC_USER, value).apply()
            ApiClient.invalidate()
        }

    /** 应用密码模式下的应用密码 */
    var basicPass: String
        get() = sp.getString(KEY_BASIC_PASS, null).orEmpty()
        set(value) {
            sp.edit().putString(KEY_BASIC_PASS, value).apply()
            ApiClient.invalidate()
        }

    /** dux / WordPress 原生登录的会话 Cookie（wordpress_logged_in_xxx） */
    var cookie: String
        get() = sp.getString(KEY_COOKIE, null).orEmpty()
        set(value) {
            sp.edit().putString(KEY_COOKIE, value).apply()
            ApiClient.invalidate()
        }

    val session: Session?
        get() {
            val b = authBackend
            if (b.isBlank()) return null
            val t = token
            if (b == AuthBackend.PLUGIN.id && t.isBlank()) return null
            // dux 原生登录没有令牌，靠 Cookie 维持会话
            if (b == AuthBackend.DUX.id && cookie.isBlank()) return null
            return Session(
                token = t,
                userId = uid,
                username = username,
                displayName = displayName,
                email = email,
                avatarUrl = avatarUrl,
                roles = roles,
                canManage = canManage,
                backend = b,
                expireAt = expireAt,
                // 应用密码模式下必须回填，否则重启后 Basic Auth 头会丢失（草稿箱/评论失效）
                basicUser = basicUser,
                basicPass = basicPass,
                cookie = cookie
            )
        }

    fun saveSession(s: Session) {
        sp.edit().apply {
            putString(KEY_TOKEN, s.token)
            putInt(KEY_UID, s.userId)
            putString(KEY_USERNAME, s.username)
            putString(KEY_DISPLAY, s.displayName)
            putString(KEY_EMAIL, s.email)
            putString(KEY_AVATAR, s.avatarUrl)
            putString(KEY_ROLES, s.roles)
            putBoolean(KEY_CAN_MANAGE, s.canManage)
            putLong(KEY_EXPIRE, s.expireAt)
            putString(KEY_BACKEND, s.backend)
            if (s.backend == AuthBackend.APP_PASSWORD.id) {
                putString(KEY_BASIC_USER, s.basicUser)
                putString(KEY_BASIC_PASS, s.basicPass)
            } else {
                putString(KEY_BASIC_USER, "")
                putString(KEY_BASIC_PASS, "")
            }
            putString(KEY_COOKIE, if (s.backend == AuthBackend.DUX.id) s.cookie else "")
        }.apply()
        ApiClient.invalidate()
    }

    fun clearSession() {
        sp.edit().apply {
            putString(KEY_TOKEN, "")
            putInt(KEY_UID, 0)
            putString(KEY_USERNAME, "")
            putString(KEY_DISPLAY, "")
            putString(KEY_EMAIL, "")
            putString(KEY_AVATAR, "")
            putString(KEY_ROLES, "")
            putBoolean(KEY_CAN_MANAGE, false)
            putLong(KEY_EXPIRE, 0L)
            putString(KEY_BACKEND, "")
            putString(KEY_BASIC_USER, "")
            putString(KEY_BASIC_PASS, "")
            putString(KEY_COOKIE, "")
        }.apply()
        ApiClient.invalidate()
    }

    /** 0=跟随系统 1=浅色 2=深色 */
    var themeMode: Int
        get() = sp.getInt(KEY_THEME, 0)
        set(value) = sp.edit().putInt(KEY_THEME, value).apply()

    /** 正文字号缩放 0.85 ~ 1.35 */
    var fontScale: Float
        get() = sp.getFloat(KEY_FONT, 1.0f)
        set(value) = sp.edit().putFloat(KEY_FONT, value).apply()

    /** 无图模式（省流量） */
    var blockImages: Boolean
        get() = sp.getBoolean(KEY_NOIMG, false)
        set(value) = sp.edit().putBoolean(KEY_NOIMG, value).apply()

    val favorites: Set<Int>
        get() = (sp.getStringSet(KEY_FAVS, emptySet()) ?: emptySet())
            .mapNotNull { it.toIntOrNull() }.toSet()

    fun isFav(id: Int): Boolean = favorites.contains(id)

    fun toggleFav(id: Int): Boolean {
        val set = favorites.toMutableSet()
        val now: Boolean
        if (set.contains(id)) {
            set.remove(id)
            now = false
        } else {
            set.add(id)
            now = true
        }
        sp.edit().putStringSet(KEY_FAVS, set.map { it.toString() }.toSet()).apply()
        return now
    }

    fun clearCache(context: Context) {
        Cache.clear(context)
    }

    companion object {
        private const val KEY_SITE = "site_url"
        private const val KEY_THEME = "theme_mode"
        private const val KEY_FONT = "font_scale"
        private const val KEY_NOIMG = "block_images"
        private const val KEY_FAVS = "favorites"

        private const val KEY_TOKEN = "auth_token"
        private const val KEY_UID = "auth_uid"
        private const val KEY_USERNAME = "auth_username"
        private const val KEY_DISPLAY = "auth_display"
        private const val KEY_EMAIL = "auth_email"
        private const val KEY_AVATAR = "auth_avatar"
        private const val KEY_ROLES = "auth_roles"
        private const val KEY_CAN_MANAGE = "auth_can_manage"
        private const val KEY_EXPIRE = "auth_expire"
        private const val KEY_BACKEND = "auth_backend"
        private const val KEY_BASIC_USER = "auth_basic_user"
        private const val KEY_BASIC_PASS = "auth_basic_pass"
        private const val KEY_COOKIE = "auth_cookie"
    }
}
