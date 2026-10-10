package com.zhujitown.app.data

import android.content.Context
import java.io.File

/** 文章正文离线缓存（收藏后可离线阅读） */
object Cache {

    private fun dir(context: Context): File =
        File(context.filesDir, "posts").apply { if (!exists()) mkdirs() }

    private fun file(context: Context, id: Int): File = File(dir(context), "$id.json")

    fun save(context: Context, post: Post) {
        runCatching {
            file(context, post.id).writeText(ApiClient.gson().toJson(post))
        }
    }

    fun saveAll(context: Context, posts: List<Post>) {
        posts.forEach { save(context, it) }
    }

    fun load(context: Context, id: Int): Post? = runCatching {
        val f = file(context, id)
        if (!f.exists()) return null
        ApiClient.gson().fromJson(f.readText(), Post::class.java)
    }.getOrNull()

    fun loadAll(context: Context, ids: Collection<Int>): List<Post> =
        ids.mapNotNull { load(context, it) }

    /** 是否已缓存该文章正文（离线可读） */
    fun has(context: Context, id: Int): Boolean = file(context, id).exists()

    /** 已缓存正文的文章数 */
    fun cachedCount(context: Context): Int =
        runCatching { dir(context).listFiles()?.count { it.isFile && it.extension == "json" } ?: 0 }
            .getOrDefault(0)

    /** 删除单篇离线正文 */
    fun remove(context: Context, id: Int) {
        runCatching { file(context, id).delete() }
    }

    fun clear(context: Context) {
        runCatching { dir(context).deleteRecursively() }
    }

    fun size(context: Context): Long =
        runCatching { dir(context).walkTopDown().filter { it.isFile }.map { it.length() }.sum() }
            .getOrDefault(0L)
}
