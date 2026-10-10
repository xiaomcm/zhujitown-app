package com.zhujitown.app.data

import android.content.Context
import com.google.gson.reflect.TypeToken
import com.zhujitown.app.util.Html
import java.io.File

/** 一条阅读记录 */
data class HistoryEntry(
    val id: Int = 0,
    val title: String = "",
    val cover: String = "",
    val postDate: String = "",
    /** 最近一次阅读的时间戳（毫秒） */
    val at: Long = 0L,
    /** 阅读进度 0~1 */
    val progress: Float = 0f
) {
    /** 是否读到接近结尾（不再提示续读） */
    val finished: Boolean get() = progress >= 0.98f
}

/**
 * 阅读历史：存本地 history.json，按最近阅读倒序，最多保留 MAX 条。
 * 只存展示所需的少量字段（标题/封面/进度），正文仍走 Cache。
 */
object History {

    private const val MAX = 200

    private fun file(context: Context): File = File(context.filesDir, "history.json")

    private fun type() = object : TypeToken<MutableList<HistoryEntry>>() {}.type

    fun all(context: Context): List<HistoryEntry> = runCatching {
        val f = file(context)
        if (!f.exists()) return emptyList()
        val list: MutableList<HistoryEntry> =
            ApiClient.gson().fromJson(f.readText(), type()) ?: mutableListOf()
        list.filter { it.id > 0 }.sortedByDescending { it.at }
    }.getOrDefault(emptyList())

    /** 写入/更新一条记录；同 id 覆盖并刷新时间 */
    fun record(context: Context, post: Post, progress: Float = 0f) {
        runCatching {
            val list = all(context).toMutableList()
            val idx = list.indexOfFirst { it.id == post.id }
            val entry = HistoryEntry(
                id = post.id,
                title = Html.entities(post.title.rendered),
                cover = post.coverUrl().orEmpty(),
                postDate = post.date,
                at = System.currentTimeMillis(),
                progress = if (idx >= 0) maxOf(list[idx].progress, progress) else progress
            )
            if (idx >= 0) list[idx] = entry else list.add(0, entry)
            persist(context, list)
        }
    }

    /** 只更新进度（滚动时高频调用，做节流：进度回退不覆盖） */
    fun progress(context: Context, id: Int, progress: Float) {
        runCatching {
            val list = all(context).toMutableList()
            val idx = list.indexOfFirst { it.id == id }
            if (idx < 0) return
            val old = list[idx]
            if (progress <= old.progress) return
            list[idx] = old.copy(progress = progress, at = System.currentTimeMillis())
            persist(context, list)
        }
    }

    fun remove(context: Context, id: Int) {
        runCatching {
            persist(context, all(context).filter { it.id != id }.toMutableList())
        }
    }

    fun clear(context: Context) {
        runCatching { persist(context, mutableListOf()) }
    }

    fun count(context: Context): Int = all(context).size

    /** 该文章是否已缓存正文（决定历史列表能否离线打开） */
    fun offlineReady(context: Context, id: Int): Boolean = Cache.has(context, id)

    private fun persist(context: Context, list: MutableList<HistoryEntry>) {
        val trimmed = list.sortedByDescending { it.at }.take(MAX).toMutableList()
        file(context).writeText(ApiClient.gson().toJson(trimmed))
    }
}
