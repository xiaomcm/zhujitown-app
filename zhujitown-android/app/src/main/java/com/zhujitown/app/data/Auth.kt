package com.zhujitown.app.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Credentials
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import retrofit2.HttpException
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.Field
import retrofit2.http.FormUrlEncoded
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Query
import java.io.IOException
import java.util.concurrent.TimeUnit

/** 可用的登录后端 */
enum class AuthBackend(val id: String, val label: String) {
    /**
     * dux 主题没有自研用户系统，它的登录/注册就是 WordPress 原生那套：
     * wp-login.php 登录 → wordpress_logged_in_ Cookie；wp/v2/users 建号。
     * App 走同一条路径，行为和网站完全一致，不需要任何插件。
     */
    DUX("dux", "站点账号（dux 原生）"),
    PLUGIN("plugin", "ZhuJiTown Auth 插件"),
    APP_PASSWORD("apppass", "WordPress 应用密码"),
    JWT_PLUGIN("jwt", "JWT Authentication 插件")
}

data class Session(
    val token: String = "",
    val userId: Int = 0,
    val username: String = "",
    val displayName: String = "",
    val email: String = "",
    val avatarUrl: String = "",
    val roles: String = "",
    val canManage: Boolean = false,
    val backend: String = "",
    val expireAt: Long = 0L,
    val basicUser: String = "",
    val basicPass: String = "",
    /** dux / WordPress 原生登录的会话 Cookie */
    val cookie: String = ""
) {
    val name: String get() = displayName.ifBlank { username }
    val expired: Boolean get() = expireAt > 0 && System.currentTimeMillis() > expireAt
}

// ----------------------------- 接口数据模型 -----------------------------

data class PingBody(
    val ok: Boolean? = null,
    val plugin: String? = null,
    val version: String? = null,
    val ttl: Long? = null,
    val registration_open: Boolean? = null,
    val min_password_length: Int? = null
)

data class AuthUserBody(
    val id: Int = 0,
    val username: String? = null,
    val display_name: String? = null,
    val email: String? = null,
    val roles: List<String>? = null,
    val can_manage: Boolean? = null,
    val avatar: Map<String, String>? = null
)

data class AuthTokenBody(
    val token: String? = null,
    val expire_at: String? = null,
    val user: AuthUserBody? = null
)

data class ApiErrorBody(
    val code: String? = null,
    val message: String? = null
)

/** WordPress 原生 /wp/v2/users/me 返回（应用密码模式用） */
data class WpUserBody(
    val id: Int = 0,
    val username: String? = null,
    val name: String? = null,
    val email: String? = null,
    val slug: String? = null,
    val roles: List<String>? = null,
    val capabilities: Map<String, Boolean>? = null,
    val avatar_urls: Map<String, String>? = null
)

/** WordPress 原生注册（公开注册开启时可用），dux 建号走的也是这条路 */
data class WpRegisterBody(
    val username: String,
    val email: String,
    val password: String
)

data class JwtTokenBody(
    val token: String? = null,
    val user_email: String? = null,
    val user_nicename: String? = null,
    val user_display_name: String? = null
)

// ----------------------------- Retrofit 接口 -----------------------------

interface AuthService {

    @GET("zhujitown/v1/ping")
    suspend fun ping(): PingBody

    @POST("zhujitown/v1/login")
    @FormUrlEncoded
    suspend fun login(
        @Field("username") username: String,
        @Field("password") password: String,
        @Field("device_id") device: String = ""
    ): AuthTokenBody

    @POST("zhujitown/v1/register")
    @FormUrlEncoded
    suspend fun register(
        @Field("username") username: String,
        @Field("email") email: String,
        @Field("password") password: String,
        @Field("device_id") device: String = ""
    ): AuthTokenBody

    @GET("zhujitown/v1/me")
    suspend fun me(@Header("Authorization") auth: String): AuthUserBody

    @POST("zhujitown/v1/logout")
    suspend fun logout(@Header("Authorization") auth: String): ResponseBody

    @POST("zhujitown/v1/lost-password")
    @FormUrlEncoded
    suspend fun lostPassword(@Field("user_login") login: String): ResponseBody

    /**
     * 发表评论（自建插件路径专用）。
     * WP 原生 /wp/v2/comments 不认我们的 HMAC 令牌，所以由插件代发：
     * 服务端校验令牌 → 取出用户 → wp_new_comment() 以该用户身份创建。
     */
    @POST("zhujitown/v1/comment")
    @FormUrlEncoded
    suspend fun pluginComment(
        @Header("Authorization") auth: String,
        @Field("post") post: Int,
        @Field("content") content: String,
        @Field("parent") parent: Int = 0
    ): Comment

    // 兼容常见的 JWT Authentication for WP REST API 插件
    @POST("jwt-auth/v1/token")
    @FormUrlEncoded
    suspend fun jwtToken(
        @Field("username") username: String,
        @Field("password") password: String
    ): JwtTokenBody

    @GET("jwt-auth/v1/token")
    suspend fun jwtProbe(): Response<ResponseBody>

    // WordPress 自带：Application Passwords + Basic Auth
    // context=edit 才能拿到 roles / capabilities，用来判断是否能看草稿
    @GET("wp/v2/users/me")
    suspend fun wpMe(
        @Header("Authorization") auth: String,
        @Query("context") context: String = "edit"
    ): Response<WpUserBody>

    /** dux 原生登录后的会话校验与用户信息：改用 Cookie 而不是 Authorization */
    @GET("wp/v2/users/me")
    suspend fun wpMeCookie(
        @Header("Cookie") cookie: String,
        @Query("context") context: String = "edit"
    ): Response<WpUserBody>

    /** WordPress 原生注册：公开注册开启时无需登录即可创建订阅者账号 */
    @POST("wp/v2/users")
    suspend fun wpRegister(
        @Body body: WpRegisterBody
    ): Response<WpUserBody>
}

// ----------------------------- 客户端构造 -----------------------------

object AuthClient {

    @Volatile
    private var service: AuthService? = null
    @Volatile
    private var currentKey = ""

    private val gson = ApiClient.gson()

    fun endpointBase(siteUrl: String): String = "${siteUrl.trim().trimEnd('/')}/wp-json/"

    fun invalidate() {
        service = null
        currentKey = ""
    }

    fun get(context: Context): AuthService {
        val prefs = Prefs(context)
        val base = endpointBase(prefs.siteUrl)
        service?.let { if (base == currentKey) return it }

        val client = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .build()

        val s = Retrofit.Builder()
            .baseUrl(base)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create(gson))
            .build()
            .create(AuthService::class.java)

        synchronized(this) {
            service = s
            currentKey = base
        }
        return s
    }
}

// ----------------------------- dux / WordPress 原生端点 -----------------------------
// dux 主题没有自研用户系统：它的登录就是 wp-login.php，评论就是 wp-comments-post.php。
// 这里直接打这两个原生端点，App 的行为与网站完全一致，不依赖任何插件。

interface WpNativeService {

    /**
     * 登录。成功时返回 302，登录态挂在 Set-Cookie: wordpress_logged_in_xxx 上。
     * 注意：客户端必须关掉自动跟随重定向，否则这个 Set-Cookie 会被丢掉。
     */
    @FormUrlEncoded
    @POST("wp-login.php")
    suspend fun login(
        @Field("log") user: String,
        @Field("pwd") pass: String,
        @Field("rememberme") remember: String,
        @Field("wp-submit") submit: String,
        @Field("redirect_to") redirect: String
    ): Response<ResponseBody>

    /**
     * 发表评论 / 楼中楼回复。WordPress 原生评论端点，dux 前端也是走它。
     * 靠 Cookie 维持身份，不需要 REST 的 X-WP-Nonce。成功时返回 302。
     */
    @FormUrlEncoded
    @POST("wp-comments-post.php")
    suspend fun postComment(
        @Header("Cookie") cookie: String,
        @Field("comment_post_ID") postId: Int,
        @Field("comment") content: String,
        @Field("comment_parent") parent: Int,
        @Field("submit") submit: String
    ): Response<ResponseBody>
}

object WpNativeClient {

    @Volatile
    private var service: WpNativeService? = null
    @Volatile
    private var currentKey = ""

    fun invalidate() {
        service = null
        currentKey = ""
    }

    fun get(context: Context): WpNativeService {
        val base = "${Prefs(context).siteUrl.trim().trimEnd('/')}/"
        service?.let { if (base == currentKey) return it }

        val client = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(45, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            // 关键：wp-login.php 的 Set-Cookie 挂在 302 上，跟随重定向会丢掉
            .followRedirects(false)
            .followSslRedirects(false)
            .retryOnConnectionFailure(true)
            .build()

        val s = Retrofit.Builder()
            .baseUrl(base)
            .client(client)
            .addConverterFactory(GsonConverterFactory.create(ApiClient.gson()))
            .build()
            .create(WpNativeService::class.java)

        synchronized(this) {
            service = s
            currentKey = base
        }
        return s
    }
}

// ----------------------------- 认证仓库 -----------------------------

class AuthRepository(private val context: Context) {

    private val prefs get() = Prefs(context)
    private val api get() = AuthClient.get(context)

    /** 站点是否装有 ZhuJiTown Auth 插件 */
    suspend fun pluginAvailable(): Boolean = runCatching {
        withContext(Dispatchers.IO) {
            val r = api.ping()
            r.ok == true || r.plugin == "zhujitown-auth"
        }
    }.getOrDefault(false)

    /** 注册是否开放（未装插件也返回 true，由服务端最终判定） */
    suspend fun registrationOpen(): Boolean = runCatching {
        withContext(Dispatchers.IO) { api.ping() }.registration_open ?: true
    }.getOrDefault(true)

    /**
     * dux / WordPress 原生登录：POST wp-login.php 拿到 wordpress_logged_in_ Cookie。
     * 与 dux 网站上的登录完全同构：不需要任何插件，也不需要用户去生成应用密码。
     */
    suspend fun duxLogin(username: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            runCatching {
                val site = prefs.siteUrl.trim().trimEnd('/')
                val resp = WpNativeClient.get(context).login(
                    user = username.trim(),
                    pass = password,
                    remember = "forever",
                    submit = "登录",
                    redirect = "$site/wp-admin/"
                )
                val cookie = resp.headers().values("Set-Cookie")
                    .map { it.substringBefore(";") }
                    .filter { kv ->
                        val n = kv.substringBefore("=")
                        n.startsWith("wordpress_logged_in_") || n.startsWith("wordpress_sec_")
                    }
                    .joinToString("; ")
                // 账号密码错误时 wp-login.php 返回 200 + 登录表单，不会有 logged_in Cookie
                if (cookie.isBlank()) throw IOException("用户名或密码不正确")

                // 用 Cookie 校验登录态，同时取回用户资料。
                // context=edit 才能拿到 roles/capabilities，但订阅者可能没权限，失败就退回默认 context，
                // 保证普通账号也能登录（只是拿不到草稿箱权限判断）。
                val me = api.wpMeCookie(cookie)
                val u: WpUserBody = if (me.isSuccessful) {
                    me.body() ?: throw IOException("无法获取用户信息")
                } else {
                    val view = api.wpMeCookie(cookie, "view")
                    if (!view.isSuccessful) throw IOException("登录状态校验失败（${me.code()}）")
                    view.body() ?: throw IOException("无法获取用户信息")
                }
                Session(
                    userId = u.id,
                    username = u.username ?: username,
                    displayName = u.name ?: "",
                    email = u.email ?: "",
                    avatarUrl = u.avatar_urls?.get("96") ?: "",
                    roles = u.roles?.joinToString(",") ?: "",
                    canManage = u.capabilities?.get("edit_posts") == true ||
                        u.roles?.contains("administrator") == true,
                    backend = AuthBackend.DUX.id,
                    cookie = cookie
                )
            }
        }

    /** dux / WordPress 原生注册：先用 wp/v2/users 建号，再走原生登录拿 Cookie */
    suspend fun duxRegister(username: String, email: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            runCatching {
                val resp = api.wpRegister(WpRegisterBody(username.trim(), email.trim(), password))
                if (!resp.isSuccessful) {
                    throw IOException(
                        when (resp.code()) {
                            403 -> "站点未开放注册，需要管理员开启"
                            400 -> "注册信息不合法：用户名或邮箱可能已被占用，或密码强度不足"
                            else -> "注册失败（${resp.code()}）"
                        }
                    )
                }
                duxLogin(username, password).getOrThrow()
            }
        }

    /** 登录总入口：优先 dux 原生登录，失败再走原来的插件 / 应用密码降级链 */
    suspend fun login(username: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            val dux = duxLogin(username, password)
            if (dux.isSuccess) return@withContext dux
            legacyLogin(username, password)
        }

    /** 注册总入口：优先 dux 原生注册，失败再回退到自建插件 */
    suspend fun register(username: String, email: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            val dux = duxRegister(username, email, password)
            if (dux.isSuccess) return@withContext dux
            legacyRegister(username, email, password)
        }

    /** 原降级链：自建插件 → JWT 插件 → 应用密码 */
    private suspend fun legacyLogin(username: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            runCatching {
                if (pluginAvailable()) {
                    val r = api.login(username.trim(), password)
                    val t = r.token
                    if (t.isNullOrBlank()) throw IOException("服务器未返回令牌")
                    val u = r.user
                    Session(
                        token = t,
                        userId = u?.id ?: 0,
                        username = u?.username ?: username,
                        displayName = u?.display_name ?: "",
                        email = u?.email ?: "",
                        avatarUrl = u?.avatar?.get("96") ?: "",
                        roles = u?.roles?.joinToString(",") ?: "",
                        canManage = u?.can_manage == true,
                        backend = AuthBackend.PLUGIN.id,
                        expireAt = parseExpire(r.expire_at)
                    )
                } else if (jwtAvailable()) {
                    val r = api.jwtToken(username.trim(), password)
                    val t = r.token
                    if (t.isNullOrBlank()) throw IOException("服务器未返回令牌")
                    Session(
                        token = t,
                        userId = 0,
                        username = r.user_nicename ?: username,
                        displayName = r.user_display_name ?: username,
                        email = r.user_email ?: "",
                        backend = AuthBackend.JWT_PLUGIN.id,
                        expireAt = 0L
                    )
                } else {
                    // 兜底：WordPress 自带的 Application Passwords（Basic Auth）
                    val basic = Credentials.basic(username.trim(), password.replace(" ", ""))
                    val resp = api.wpMe(basic)
                    if (!resp.isSuccessful) {
                        throw IOException("应用密码校验失败（${resp.code()}），请确认用户名与应用密码是否正确")
                    }
                    val u = resp.body() ?: throw IOException("无法获取用户信息")
                    Session(
                        token = "",
                        userId = u.id,
                        username = u.username ?: username,
                        displayName = u.name ?: "",
                        email = u.email ?: "",
                        avatarUrl = u.avatar_urls?.get("96") ?: "",
                        roles = u.roles?.joinToString(",") ?: "",
                        canManage = u.capabilities?.get("edit_posts") == true ||
                            u.roles?.contains("administrator") == true,
                        backend = AuthBackend.APP_PASSWORD.id,
                        expireAt = 0L,
                        basicUser = username.trim(),
                        basicPass = password.replace(" ", "")
                    )
                }
            }
        }

    /** 原注册路径：依赖 ZhuJiTown Auth 插件 */
    private suspend fun legacyRegister(username: String, email: String, password: String): Result<Session> =
        withContext(Dispatchers.IO) {
            runCatching {
                if (!pluginAvailable()) {
                    throw IOException("站点尚未启用 ZhuJiTown Auth 插件，暂不支持在 App 内注册")
                }
                val r = api.register(username.trim(), email.trim(), password)
                val t = r.token
                if (t.isNullOrBlank()) throw IOException("注册成功，但服务器未返回令牌，请直接登录")
                val u = r.user
                Session(
                    token = t,
                    userId = u?.id ?: 0,
                    username = u?.username ?: username,
                    displayName = u?.display_name ?: username,
                    email = u?.email ?: email,
                    avatarUrl = u?.avatar?.get("96") ?: "",
                    roles = u?.roles?.joinToString(",") ?: "",
                    canManage = u?.can_manage == true,
                    backend = AuthBackend.PLUGIN.id,
                    expireAt = parseExpire(r.expire_at)
                )
            }
        }

    suspend fun lostPassword(login: String): Result<Unit> = withContext(Dispatchers.IO) {
        runCatching { api.lostPassword(login.trim()) }.map { Unit }
    }

    /**
     * 发表评论 / 回复。按登录后端选路：
     *  - 自建插件 → zhujitown/v1/comment（服务端代发）
     *  - 应用密码 / JWT → WP 原生 /wp/v2/comments（ApiClient 已注入 Authorization）
     */
    suspend fun postComment(postId: Int, content: String, parent: Int = 0): Result<Comment> =
        withContext(Dispatchers.IO) {
            val s = prefs.session
                ?: return@withContext Result.failure(IOException("请先登录后再评论"))
            runCatching {
                when (s.backend) {
                    // dux 原生：走 WordPress 自己的评论端点，靠 Cookie 身份，不需要 REST nonce
                    AuthBackend.DUX.id -> {
                        val resp = WpNativeClient.get(context).postComment(
                            cookie = s.cookie,
                            postId = postId,
                            content = content.trim(),
                            parent = parent,
                            submit = "发表评论"
                        )
                        // 成功时 WP 会 302 回文章页并带上 #comment-xxx
                        if (resp.code() != 302) {
                            throw IOException("评论未提交成功（${resp.code()}）：可能被判定为重复内容，或站点开启了审核")
                        }
                        Comment(
                            post = postId,
                            parent = parent,
                            author_name = s.name,
                            content = Rendered(rendered = content.trim()),
                            status = if (s.canManage) "approved" else "hold"
                        )
                    }
                    AuthBackend.PLUGIN.id ->
                        api.pluginComment("Bearer ${s.token}", postId, content.trim(), parent)
                    else ->
                        ApiClient.get(context).postComment(NewComment(postId, content.trim(), parent))
                }
            }
        }

    /** 校验已有会话是否仍然有效，过期返回 null */
    suspend fun validate(): Session? {
        val s = prefs.session ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                when (s.backend) {
                    AuthBackend.DUX.id -> {
                        if (s.cookie.isBlank()) throw IOException("登录已失效，请重新登录")
                        val resp = api.wpMeCookie(s.cookie)
                        if (!resp.isSuccessful) throw IOException("登录已失效，请重新登录")
                        val u = resp.body()
                        s.copy(
                            userId = u?.id ?: s.userId,
                            displayName = u?.name ?: s.displayName,
                            email = u?.email ?: s.email,
                            avatarUrl = u?.avatar_urls?.get("96") ?: s.avatarUrl,
                            roles = u?.roles?.joinToString(",") ?: s.roles,
                            canManage = u?.capabilities?.get("edit_posts") == true ||
                                u?.roles?.contains("administrator") == true
                        )
                    }
                    AuthBackend.PLUGIN.id -> {
                        if (s.expired) {
                            api.logout("Bearer ${s.token}")
                            throw IOException("登录已过期")
                        }
                        val u = api.me("Bearer ${s.token}")
                        s.copy(
                            userId = u.id,
                            username = u.username ?: s.username,
                            displayName = u.display_name ?: s.displayName,
                            email = u.email ?: s.email,
                            avatarUrl = u.avatar?.get("96") ?: s.avatarUrl,
                            roles = u.roles?.joinToString(",") ?: s.roles,
                            canManage = u.can_manage == true
                        )
                    }
                    AuthBackend.APP_PASSWORD.id -> {
                        val resp = api.wpMe(Credentials.basic(s.basicUser, s.basicPass))
                        if (!resp.isSuccessful) throw IOException("应用密码已失效")
                        val u = resp.body()
                        s.copy(
                            userId = u?.id ?: s.userId,
                            canManage = u?.capabilities?.get("edit_posts") == true ||
                                u?.roles?.contains("administrator") == true
                        )
                    }
                    else -> s
                }
            }.getOrNull()
        }
    }

    suspend fun logout() {
        val s = prefs.session
        if (s != null && s.backend == AuthBackend.PLUGIN.id && s.token.isNotBlank()) {
            runCatching { withContext(Dispatchers.IO) { api.logout("Bearer ${s.token}") } }
        }
        prefs.clearSession()
        ApiClient.invalidate()
        AuthClient.invalidate()
        WpNativeClient.invalidate()
    }

    private suspend fun jwtAvailable(): Boolean = runCatching {
        withContext(Dispatchers.IO) { api.jwtProbe() }.code() != 404
    }.getOrDefault(false)

    private fun parseExpire(iso: String?): Long {
        if (iso.isNullOrBlank()) return 0L
        return runCatching {
            java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
                .parse(iso)?.time ?: 0L
        }.getOrDefault(0L)
    }
}
