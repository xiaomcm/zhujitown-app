package com.zhujitown.app.util

import org.jsoup.Jsoup
import org.jsoup.safety.Safelist
import java.text.SimpleDateFormat
import java.util.Locale

object Html {

    /** 解码 WP 标题里的 HTML 实体（&#8217; &amp; …） */
    fun entities(raw: String): String = runCatching {
        android.text.Html.fromHtml(raw, android.text.Html.FROM_HTML_MODE_LEGACY).toString()
    }.getOrDefault(raw)

    /** 富文本转纯文本（列表摘要 / 分享文案） */
    fun plain(raw: String, limit: Int = 120): String {
        val text = Jsoup.clean(raw, Safelist.none())
            .replace("\u00a0", " ")
            .replace(Regex("\\s+"), " ")
            .trim()
        return if (limit > 0 && text.length > limit) text.take(limit) + "…" else text
    }

    /** 文章日期 2026-10-08T16:03:08 -> 2026-10-08 */
    fun dateOf(iso: String): String {
        if (iso.isBlank()) return ""
        return runCatching {
            val d = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.CHINA).parse(iso)
            SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(d!!)
        }.getOrElse { iso.take(10) }
    }

    /** 相对时间：刚刚 / N 分钟前 / N 小时前 / N 天前 / yyyy-MM-dd（入参为毫秒时间戳） */
    fun relative(ts: Long): String {
        if (ts <= 0L) return ""
        val diff = System.currentTimeMillis() - ts
        val min = 60_000L
        val hour = 60 * min
        val day = 24 * hour
        return when {
            diff < min -> "刚刚"
            diff < hour -> "${diff / min} 分钟前"
            diff < day -> "${diff / hour} 小时前"
            diff < 30 * day -> "${diff / day} 天前"
            else -> SimpleDateFormat("yyyy-MM-dd", Locale.CHINA).format(java.util.Date(ts))
        }
    }
}
