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
import retrofit2.http.GET
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
        val key = baseUrl(prefs.siteUrl) + "|" + (authHeader ?: "anon")
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
                    .apply { authHeader?.let { header("Authorization", it) } }
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
