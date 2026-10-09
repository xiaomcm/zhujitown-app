package com.zhujitown.app.data

import com.google.gson.annotations.SerializedName

/** WordPress 富文本字段：title / content / excerpt 都是 { rendered, protected } */
data class Rendered(
    val rendered: String = "",
    val protected: Boolean = false
)

data class Post(
    val id: Int = 0,
    val date: String = "",
    val modified: String = "",
    val slug: String = "",
    val link: String = "",
    val status: String = "publish",
    val title: Rendered = Rendered(),
    val content: Rendered = Rendered(),
    val excerpt: Rendered = Rendered(),
    val featured_media: Int = 0,
    val categories: List<Int> = emptyList(),
    val tags: List<Int> = emptyList(),
    @SerializedName("_embedded")
    val embedded: Embedded? = null
)

data class Embedded(
    @SerializedName("wp:featuredmedia") val media: List<Media>? = null,
    @SerializedName("wp:term") val terms: List<List<Term>?>? = null,
    @SerializedName("author") val author: List<Author>? = null
)

data class Media(
    val id: Int = 0,
    val source_url: String = "",
    val alt_text: String = "",
    val media_details: MediaDetails? = null
)

data class MediaDetails(
    val width: Int = 0,
    val height: Int = 0,
    val sizes: Map<String, MediaSize>? = null
)

data class MediaSize(
    val source_url: String = "",
    val width: Int = 0,
    val height: Int = 0
)

data class Term(
    val id: Int = 0,
    val name: String = "",
    val slug: String = "",
    val taxonomy: String = "",
    val count: Int = 0
)

data class Author(
    val id: Int = 0,
    val name: String = "",
    val slug: String = "",
    val avatar_urls: Map<String, String>? = null
)

data class Comment(
    val id: Int = 0,
    val post: Int = 0,
    val author_name: String = "",
    val date: String = "",
    val link: String = "",
    val content: Rendered = Rendered(),
    val author_avatar_urls: Map<String, String>? = null
)

data class Category(
    val id: Int = 0,
    val name: String = "",
    val slug: String = "",
    val description: String = "",
    val parent: Int = 0,
    val count: Int = 0
)

/** 封面图：优先取中等尺寸，失败回退原图 */
fun Post.coverUrl(): String? {
    val m = embedded?.media?.firstOrNull() ?: return null
    val sizes = m.media_details?.sizes
    val pick = sizes?.get("medium_large")
        ?: sizes?.get("medium")
        ?: sizes?.get("thumbnail")
    return pick?.source_url?.takeIf { it.isNotBlank() }
        ?: m.source_url.takeIf { it.isNotBlank() }
}

/** 分类名（wp:term 第一组是 category） */
fun Post.categoryNames(): List<String> {
    val group = embedded?.terms?.firstOrNull() ?: return emptyList()
    return group.orEmpty().map { it.name }.filter { it.isNotBlank() }
}

fun Post.tagNames(): List<String> {
    val group = embedded?.terms?.getOrNull(1) ?: return emptyList()
    return group.orEmpty().map { it.name }.filter { it.isNotBlank() }
}

fun Post.authorName(): String = embedded?.author?.firstOrNull()?.name.orEmpty()
