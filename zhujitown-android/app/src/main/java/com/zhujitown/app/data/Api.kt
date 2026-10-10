package com.zhujitown.app.data

import android.content.Context
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonDeserializer
import com.google.gson.JsonPrimitive
import okhttp3.Credentials
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.POST
import retrofit2.http.Path
import retrofit2.http.Query
import java.io.IOException
import java.util.concurrent.TimeUnit

interface WpService {

    @GET("posts")
    suspend fun listPosts(
        @Query("page") page: Int,
        @Query("per_page") perPage: Int,
        @Query("categories") categories: Int?,
        @Query("search") search: String?,
        @Query("status") status: String? = null,
        @Query("orderby") orderBy: String = "date",
        @Query("order") order: String = "desc",
        @Query("_embed") embed: Boolean = true
    ): retrofit2.Response<List<Post>>

    @GET("posts/{id}")
    suspend fun getPost(
        @Path("id") id: Int,
        @Query("_embed") embed: Boolean = true
    ): Post

    @GET("categories")
    suspend fun categories(
        @Query("per_page") perPage: Int = 100,
        @Query("orderby") orderBy: String = "count",
        @Query("order") order: String = "desc",
        @Query("hide_empty") hideEmpty: Boolean = true
    ): List<Category>

    /** 同分类相关阅读 */
    @GET("posts")
    suspend fun related(
        @Query("categories") categories: Int?,
        @Query("exclude") exclude: Int?,
        @Query("per_page") perPage: Int = 6,
        @Query("_embed") embed: Boolean = true
    ): List<Post>

    /** 上一篇：before=当前日期；下一篇：after=当前日期 */
    @GET("posts")
    suspend fun neighbors(
        @Query("before") before: String?,
        @Query("after") after: String?,
        @Query("per_page") perPage: Int = 1,
        @Query("orderby") orderBy: String = "date",
        @Query("order") order: String = "asc",
        @Query("_embed") embed: Boolean = false
    ): List<Post>

    @GET("comments")
    suspend fun comments(
        @Query("post") postId: Int,
        @Query("per_page") perPage: Int = 20,
        @Query("orderby") orderBy: String = "date",
        @Query("order") order: String = "asc",
        @Query("status") status: String = "approve"
    ): List<Comment>

    /** 个人中心：我的文章（按作者） */
    @GET("posts")
    suspend fun postsByAuthor(
        @Query("author") author: Int,
        @Query("page") page: Int,
        @Query("per_page") perPage: Int,
        @Query("_embed") embed: Boolean = true
    ): retrofit2.Response<List<Post>>

    /** 个人中心：我的评论（按作者，需登录态 Authorization） */
    @GET("comments")
    suspend fun commentsByAuthor(
        @Query("author") author: Int,
        @Query("page") page: Int,
        @Query("per_page") perPage: Int,
        @Query("orderby") orderBy: String = "date",
        @Query("order") order: String = "desc",
        @Query("status") status: String = "approve"
    ): retrofit2.Response<List<Comment>>

    /**
     * 发表评论。站点若开启「必须登录才能评论」，需要带 Authorization：
     *  - 应用密码登录 → Basic（由 ApiClient 统一注入）
     *  - JWT 插件登录 → Bearer
     * 自建插件令牌 WP 不认，那条路径改走 AuthService.pluginComment()
     */
    @POST("comments")
    suspend fun postComment(@Body body: NewComment): Comment

    @GET("posts")
    suspend fun bySlug(
        @Query("slug") slug: String,
        @Query("_embed") embed: Boolean = true,
        @Query("per_page") perPage: Int = 1
    ): List<Post>

    @GET("media/{id}")
    suspend fun media(
        @Path("id") id: Int
    ): Media
}

/** 站点响应偶发 502 / 超时，做有限重试 */
class RetryInterceptor(private val times: Int = 3) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        var lastErr: IOException? = null
        repeat(times) { attempt ->
            try {
                return chain.proceed(chain.request())
            } catch (e: IOException) {
                lastErr = e
                if (attempt < times - 1) {
                    try {
                        Thread.sleep(800L * (attempt + 1))
                    } catch (_: InterruptedException) {
                    }
                }
            }
        }
        throw lastErr ?: IOException("network failed")
    }
}

object ApiClient {

    @Volatile
    private var service: WpService? = null

    @Volatile
    private var currentKey: String = ""

    fun gson(): Gson = GsonBuilder()
        .registerTypeAdapter(
            Rendered::class.java,
            JsonDeserializer { json, _, _ ->
                when {
                    json == null || json.isJsonNull -> Rendered()
                    json.isJsonPrimitive -> Rendered(rendered = (json as JsonPrimitive).asString)
                    json.isJsonObject -> {
                        val o = json.asJsonObject
                        Rendered(
                            rendered = o.get("rendered")?.asString ?: "",
                            protected = o.get("protected")?.asBoolean ?: false
                        )
                    }
                    else -> Rendered()
                }
            }
        )
        .create()

    fun baseUrl(siteUrl: String): String {
        val s = siteUrl.trim().trimEnd('/')
        return "$s/wp-json/wp/v2/"
    }

    fun invalidate() {
        service = null
        currentKey = ""
    }

    fun get(context: Context): WpService {
        val prefs = Prefs(context)
        val session = prefs.session
        val authHeader: String? = when (session?.backend) {
            AuthBackend.PLUGIN.id, AuthBackend.JWT_PLUGIN.id ->
                session.token.takeIf { it.isNotBlank() }?.let { "Bearer $it" }
            AuthBackend.APP_PASSWORD.id ->
                if (session.basicUser.isNotBlank() && session.basicPass.isNotBlank())
                    Credentials.basic(session.basicUser, session.basicPass) else null
            else -> null
        }
        // dux 原生登录：用 wordpress_logged_in_ Cookie 维持身份（读接口不需要 nonce）
        val cookieHeader: String? =
            if (session != null && session.backend == AuthBackend.DUX.id)
                session.cookie.takeIf { it.isNotBlank() } else null
        val key = baseUrl(prefs.siteUrl) + "|" + (authHeader ?: "anon") + "|" + (cookieHeader ?: "-")
        service?.let { if (key == currentKey) return it }

        val builder = OkHttpClient.Builder()
            .connectTimeout(20, TimeUnit.SECONDS)
            .readTimeout(60, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)
            .addInterceptor(RetryInterceptor(3))
            .addInterceptor { chain ->
                val req = chain.request().newBuilder()
                    .header("User-Agent", "ZhujitownAndroid/1.0 (+https://www.zhujitown.com)")
                    .header("Accept", "application/json")
                    .apply {
                        authHeader?.let { header("Authorization", it) }
                        cookieHeader?.let { header("Cookie", it) }
                    }
                    .build()
                chain.proceed(req)
            }

        val s = Retrofit.Builder()
            .baseUrl(baseUrl(prefs.siteUrl))
            .client(builder.build())
            .addConverterFactory(GsonConverterFactory.create(gson()))
            .build()
            .create(WpService::class.java)

        synchronized(this) {
            service = s
            currentKey = key
        }
        return s
    }
}
