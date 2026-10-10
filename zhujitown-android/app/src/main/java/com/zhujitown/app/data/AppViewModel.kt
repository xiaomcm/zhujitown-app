package com.zhujitown.app.data

import android.app.Application
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import retrofit2.HttpException
import java.io.IOException

enum class FeedMode { LATEST, CATEGORY, SEARCH, DRAFTS }

class AppViewModel(private val app: Application) : AndroidViewModel(app) {

    val prefs = Prefs(app)
    private val api get() = ApiClient.get(app)
    private val pageSize = 20

    /** 阅读历史（最近浏览，倒序） */
    var history by mutableStateOf<List<HistoryEntry>>(History.all(app))
        private set

    var categories by mutableStateOf<List<Category>>(emptyList())
        private set

    var posts by mutableStateOf<List<Post>>(emptyList())
        private set

    var loading by mutableStateOf(false)      // 加载更多
        private set
    var refreshing by mutableStateOf(false)   // 首屏 / 手动刷新
        private set
    var error by mutableStateOf<String?>(null)
        private set
    var endReached by mutableStateOf(false)
        private set

    var mode by mutableStateOf(FeedMode.LATEST)
        private set
    var activeCategory by mutableStateOf<Category?>(null)
        private set
    var query by mutableStateOf("")
        private set

    // ---- 阅读偏好（写入时同步落盘，UI 立即生效）----
    var themeMode by mutableStateOf(prefs.themeMode)
        private set
    var fontScale by mutableStateOf(prefs.fontScale)
        private set
    var blockImages by mutableStateOf(prefs.blockImages)
        private set

    fun applyThemeMode(v: Int) {
        themeMode = v
        prefs.themeMode = v
    }

    fun applyFontScale(v: Float) {
        fontScale = v.coerceIn(0.85f, 1.35f)
        prefs.fontScale = fontScale
    }

    fun applyBlockImages(v: Boolean) {
        blockImages = v
        prefs.blockImages = v
    }

    var siteUrl by mutableStateOf(prefs.siteUrl)
        private set

    // ---- 账号（用户在 App 内登录，工程不再内置任何管理员凭据）----
    private val authRepo = AuthRepository(app)

    var session by mutableStateOf<Session?>(prefs.session)
        private set
    var authBusy by mutableStateOf(false)
        private set
    var authError by mutableStateOf<String?>(null)
        private set
    var authNotice by mutableStateOf<String?>(null)
        private set
    /** 站点是否装了 ZhuJiTown Auth 插件（决定能不能用 App 内注册） */
    var pluginReady by mutableStateOf(false)
        private set
    var registrationOpen by mutableStateOf(false)
        private set

    /** 当前登录用户是否具备编辑以上权限（可看草稿） */
    val canManage: Boolean get() = session?.canManage == true

    fun clearAuthMessage() {
        authError = null
        authNotice = null
    }

    fun saveSite(url: String) {
        val v = url.trim().trimEnd('/')
        prefs.siteUrl = v
        siteUrl = v
        ApiClient.invalidate()
        AuthClient.invalidate()
        probeAuth()
        refresh()
    }

    /** 启动或换站点时探测认证后端，并校验已有会话 */
    fun probeAuth() {
        viewModelScope.launch {
            pluginReady = authRepo.pluginAvailable()
            registrationOpen = pluginReady && authRepo.registrationOpen()
            val s = prefs.session
            if (s != null) {
                val refreshed = authRepo.validate()
                if (refreshed == null) {
                    prefs.clearSession()
                    session = null
                } else {
                    prefs.saveSession(refreshed)
                    session = refreshed
                }
            }
        }
    }

    fun login(user: String, pass: String) {
        if (user.isBlank() || pass.isBlank()) {
            authError = "请填写用户名和密码"
            return
        }
        authBusy = true
        authError = null
        authNotice = null
        viewModelScope.launch {
            authRepo.login(user, pass)
                .onSuccess { s ->
                    prefs.saveSession(s)
                    session = s
                    ApiClient.invalidate()
                    authNotice = "登录成功，欢迎回来 ${s.name}"
                }
                .onFailure { authError = readableAuthError(it, "登录") }
            authBusy = false
        }
    }

    fun register(user: String, email: String, pass: String) {
        when {
            user.trim().length < 3 -> authError = "用户名至少 3 个字符"
            !email.contains("@") -> authError = "邮箱格式不正确"
            pass.length < 6 -> authError = "密码至少 6 位"
            else -> {
                authBusy = true
                authError = null
                authNotice = null
                viewModelScope.launch {
                    authRepo.register(user, email, pass)
                        .onSuccess { s ->
                            prefs.saveSession(s)
                            session = s
                            ApiClient.invalidate()
                            authNotice = "注册成功，已自动登录"
                        }
                        .onFailure { authError = readableAuthError(it, "注册") }
                    authBusy = false
                }
            }
        }
    }

    fun lostPassword(login: String) {
        if (login.isBlank()) {
            authError = "请填写用户名或邮箱"
            return
        }
        authBusy = true
        authError = null
        viewModelScope.launch {
            authRepo.lostPassword(login)
                .onSuccess { authNotice = "重置邮件已发送，请到邮箱查收" }
                .onFailure { authError = readableAuthError(it, "找回密码") }
            authBusy = false
        }
    }

    fun logout() {
        viewModelScope.launch {
            authRepo.logout()
            session = null
            ApiClient.invalidate()
            authNotice = null
        }
    }

    private var page = 1
    private var job: Job? = null

    init {
        loadCategories()
        probeAuth()
        refresh()
    }

    fun loadCategories(force: Boolean = false) {
        if (categories.isNotEmpty() && !force) return
        viewModelScope.launch {
            runCatching { withContext(Dispatchers.IO) { api.categories() } }
                .onSuccess { categories = it.filter { c -> c.count > 0 && c.id != 1 } }
                .onFailure { /* 分类失败不影响正文列表 */ }
        }
    }

    fun refresh(
        m: FeedMode = mode,
        cat: Category? = activeCategory,
        q: String = query
    ) {
        mode = m
        activeCategory = cat
        query = q
        page = 1
        posts = emptyList()
        endReached = false
        error = null
        if (m == FeedMode.SEARCH && q.isBlank()) {
            refreshing = false
            return
        }
        refreshing = true
        job?.cancel()
        job = viewModelScope.launch {
            fetch(1)
            refreshing = false
        }
    }

    fun loadMore() {
        if (loading || refreshing || endReached) return
        if (mode == FeedMode.SEARCH && query.isBlank()) return
        loading = true
        viewModelScope.launch {
            fetch(page + 1)
            loading = false
        }
    }

    private suspend fun fetch(targetPage: Int) {
        val result = runCatching {
            withContext(Dispatchers.IO) {
                api.listPosts(
                    page = targetPage,
                    perPage = pageSize,
                    categories = if (mode == FeedMode.CATEGORY) activeCategory?.id else null,
                    search = if (mode == FeedMode.SEARCH) query.takeIf { it.isNotBlank() } else null,
                    status = if (mode == FeedMode.DRAFTS) "draft" else null
                )
            }
        }
        result.onSuccess { resp ->
            val totalPages = resp.headers()["X-WP-TotalPages"]?.toIntOrNull() ?: Int.MAX_VALUE
            val list = resp.body().orEmpty()
            page = targetPage
            posts = if (targetPage == 1) list else posts + list
            endReached = list.size < pageSize || targetPage >= totalPages
            error = null
            withContext(Dispatchers.IO) { Cache.saveAll(app, list) }
        }.onFailure { e ->
            error = messageOf(e)
        }
    }

    suspend fun fetchPost(id: Int): Post = withContext(Dispatchers.IO) {
        api.getPost(id).also { Cache.save(app, it) }
    }

    suspend fun postBySlug(slug: String): Post? = runCatching {
        withContext(Dispatchers.IO) { api.bySlug(slug).firstOrNull() }
    }.getOrNull()

    /** 同分类相关阅读 */
    suspend fun related(post: Post): List<Post> = runCatching {
        withContext(Dispatchers.IO) {
            api.related(
                categories = post.categories.firstOrNull(),
                exclude = post.id,
                perPage = 6
            )
        }
    }.getOrDefault(emptyList())

    /** 上一篇 */
    suspend fun previous(post: Post): Post? = runCatching {
        withContext(Dispatchers.IO) { api.neighbors(before = post.date, after = null).firstOrNull() }
    }.getOrNull()

    /** 下一篇 */
    suspend fun next(post: Post): Post? = runCatching {
        withContext(Dispatchers.IO) { api.neighbors(before = null, after = post.date).firstOrNull() }
    }.getOrNull()

    suspend fun comments(postId: Int): List<Comment> = runCatching {
        withContext(Dispatchers.IO) { api.comments(postId) }
    }.getOrDefault(emptyList())

    fun favoritePosts(): List<Post> = Cache.loadAll(app, prefs.favorites)

    // ---------------------------- 阅读历史 ----------------------------

    fun refreshHistory() {
        history = History.all(app)
    }

    fun recordHistory(post: Post, progress: Float = 0f) {
        History.record(app, post, progress)
        refreshHistory()
    }

    fun updateProgress(id: Int, progress: Float) {
        History.progress(app, id, progress)
    }

    fun removeHistory(id: Int) {
        History.remove(app, id)
        refreshHistory()
    }

    fun clearHistory() {
        History.clear(app)
        history = emptyList()
    }

    // ---------------------------- 个人中心 ----------------------------

    var myPosts by mutableStateOf<List<Post>>(emptyList())
        private set
    var myPostsTotal by mutableStateOf(0)
        private set
    var myComments by mutableStateOf<List<Comment>>(emptyList())
        private set
    var myCommentsTotal by mutableStateOf(0)
        private set
    var myLoading by mutableStateOf(false)
        private set
    var myLoadingMore by mutableStateOf(false)
        private set
    private var myPage = 1

    /** 收藏数（本地） */
    val favoritesCount: Int get() = prefs.favorites.size

    /** 进入个人中心时拉取「我的文章 / 我的评论」统计与首页 */
    fun loadMyContent() {
        val s = session ?: return
        if (s.userId <= 0) return
        myLoading = true
        viewModelScope.launch {
            runCatching {
                val postsResp = withContext(Dispatchers.IO) {
                    api.postsByAuthor(author = s.userId, page = 1, perPage = 20)
                }
                myPosts = postsResp.body().orEmpty()
                myPostsTotal = postsResp.headers()["X-WP-Total"]?.toIntOrNull() ?: myPosts.size
                myPage = 1
                val cResp = withContext(Dispatchers.IO) {
                    api.commentsByAuthor(author = s.userId, page = 1, perPage = 20)
                }
                myComments = cResp.body().orEmpty()
                myCommentsTotal = cResp.headers()["X-WP-Total"]?.toIntOrNull() ?: myComments.size
                withContext(Dispatchers.IO) { Cache.saveAll(app, myPosts) }
            }
            myLoading = false
        }
    }

    /** 我的文章翻页 */
    fun loadMoreMyPosts() {
        val s = session ?: return
        if (myLoadingMore || myPosts.size >= myPostsTotal) return
        myLoadingMore = true
        viewModelScope.launch {
            val next = myPage + 1
            runCatching {
                val resp = withContext(Dispatchers.IO) {
                    api.postsByAuthor(author = s.userId, page = next, perPage = 20)
                }
                val list = resp.body().orEmpty()
                myPosts = myPosts + list
                myPage = next
                withContext(Dispatchers.IO) { Cache.saveAll(app, list) }
            }
            myLoadingMore = false
        }
    }

    /** 草稿箱（仅可管理内容的账号可见） */
    var draftPosts by mutableStateOf<List<Post>>(emptyList())
        private set
    var draftLoading by mutableStateOf(false)
        private set

    fun loadDrafts() {
        if (!canManage) return
        draftLoading = true
        viewModelScope.launch {
            runCatching {
                val resp = withContext(Dispatchers.IO) {
                    api.listPosts(
                        page = 1,
                        perPage = 20,
                        categories = null,
                        search = null,
                        status = "draft"
                    )
                }
                draftPosts = resp.body().orEmpty()
                withContext(Dispatchers.IO) { Cache.saveAll(app, draftPosts) }
            }
            draftLoading = false
        }
    }

    /** 文章是否已缓存正文（离线可读） */
    fun offlineReady(id: Int): Boolean = Cache.has(app, id)

    // ---------------------------- 离线正文 ----------------------------

    /** 已缓存正文的文章数 */
    fun offlineCount(): Int = Cache.cachedCount(app)

    /** 离线占用字节数 */
    fun offlineBytes(): Long = Cache.size(app)

    /**
     * 收藏但还没缓存正文的文章，补齐正文，保证断网可在收藏页里读。
     * 返回成功补齐的条数。
     */
    suspend fun syncOffline(ids: Collection<Int>): Int = withContext(Dispatchers.IO) {
        val missing = ids.filter { !Cache.has(app, it) }
        if (missing.isEmpty()) return@withContext 0
        var ok = 0
        missing.forEach { id ->
            runCatching { api.getPost(id) }
                .onSuccess { Cache.save(app, it); ok++ }
        }
        ok
    }

    // ---------------------------- 评论 ----------------------------

    /** 发表评论 / 回复。未登录时返回失败，由 UI 引导登录 */
    suspend fun submitComment(postId: Int, content: String, parent: Int = 0): Result<Comment> =
        authRepo.postComment(postId, content, parent)

    /** 把登录/注册类错误翻译成人话 */
    private fun readableAuthError(e: Throwable, action: String): String {
        val raw = (e as? HttpException)?.let { he ->
            runCatching {
                he.response()?.errorBody()?.string()?.let { body ->
                    val m = Regex("\"message\"\\s*:\\s*\"([^\"]+)\"").find(body)
                    m?.groupValues?.get(1)
                }
            }.getOrNull()
        }
        if (!raw.isNullOrBlank()) return "${action}失败：$raw"
        return when (e) {
            is IOException -> "${action}失败：连接不到服务器，请检查网络或站点地址"
            is HttpException -> when (e.code()) {
                401 -> "${action}失败：用户名或密码不正确"
                403 -> "${action}失败：服务器拒绝了请求（403），站点可能未开放注册"
                404 -> "${action}失败：接口不存在（404），请确认站点已启用 ZhuJiTown Auth 插件"
                409 -> "${action}失败：用户名或邮箱已被占用"
                429 -> "尝试过于频繁，请稍后再试"
                else -> "${action}失败：服务器返回 ${e.code()}"
            }
            else -> "${action}失败：${e.message ?: "未知错误"}"
        }
    }

    fun messageOf(e: Throwable): String = when (e) {
        is IOException -> "网络连接失败，请检查网络后下拉重试"
        is HttpException -> when (e.code()) {
            401 -> "草稿需要登录账号查看，请先登录有编辑权限的账号"
            403 -> "服务器拒绝访问（403），可能是缓存插件拦截 /wp-json/"
            404 -> "接口不存在（404），请检查站点地址是否填写正确"
            else -> "服务器返回 ${e.code()}"
        }
        else -> e.message ?: "加载失败"
    }
}
