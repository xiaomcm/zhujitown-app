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
    val basicPass: String = ""
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

    suspend fun login(username: String, password: String): Result<Session> =
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

    suspend fun register(username: String, email: String, password: String): Result<Session> =
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
                if (s.backend == AuthBackend.PLUGIN.id) {
                    api.pluginComment("Bearer ${s.token}", postId, content.trim(), parent)
                } else {
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
