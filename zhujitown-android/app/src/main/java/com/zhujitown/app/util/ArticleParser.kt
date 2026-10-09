package com.zhujitown.app.util

import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import org.jsoup.nodes.Node
import org.jsoup.nodes.TextNode

/** 正文行内片段：普通文字 / 链接 */
sealed class Inline {
    data class Text(
        val value: String,
        val bold: Boolean = false,
        val underline: Boolean = false
    ) : Inline()

    data class Link(
        val text: String,
        val url: String,
        val bold: Boolean = false,
        val underline: Boolean = false
    ) : Inline()
}

/** 正文块：全部用原生 Compose 组件渲染，不走 WebView */
sealed class Block {

    data class Heading(
        val level: Int,
        val text: String,
        val anchor: String
    ) : Block()

    data class Paragraph(
        val spans: List<Inline>,
        val center: Boolean = false
    ) : Block()

    data class Image(
        val url: String,
        val alt: String,
        val caption: String? = null
    ) : Block()

    data class Cell(val spans: List<Inline>, val center: Boolean)

    data class Table(
        val header: List<Cell>?,
        val rows: List<List<Cell>>
    ) : Block()

    data class ListBlock(
        val ordered: Boolean,
        val items: List<List<Inline>>
    ) : Block()

    data class Quote(val spans: List<Inline>) : Block()

    data class Code(val text: String) : Block()

    object Divider : Block()
}

object ArticleParser {

    fun parse(html: String, baseUrl: String, blockImages: Boolean): List<Block> {
        if (html.isBlank()) return emptyList()
        val doc = Jsoup.parseBodyFragment(html, baseUrl)
        val body = doc.body()
        body.select("script, style, noscript, iframe").remove()
        val out = mutableListOf<Block>()
        walk(body, out, blockImages, 0)
        return out
    }

    private fun walk(el: Element, out: MutableList<Block>, blockImages: Boolean, depth: Int) {
        if (depth > 6) return
        for (child in el.children()) {
            when (child.tagName()) {
                "h1", "h2", "h3", "h4", "h5", "h6" -> {
                    val text = child.text().trim()
                    if (text.isNotBlank()) {
                        out.add(
                            Block.Heading(
                                level = child.tagName().removePrefix("h").toIntOrNull() ?: 2,
                                text = text,
                                anchor = child.id().ifBlank { "h-${out.size}" }
                            )
                        )
                    }
                }
                "p" -> paragraph(child, out, blockImages)
                "figure" -> {
                    val img = child.selectFirst("img")
                    if (img != null && !blockImages) {
                        val cap = child.selectFirst("figcaption")?.text()?.trim()
                        addImage(img, cap, out)
                    }
                }
                "img" -> if (!blockImages) addImage(child, null, out)
                "table" -> out.add(parseTable(child))
                "ul", "ol" -> {
                    val items = child.children().map { li -> inlines(li) }
                        .filter { it.isNotEmpty() }
                    if (items.isNotEmpty()) {
                        out.add(Block.ListBlock(ordered = child.tagName() == "ol", items = items))
                    }
                }
                "blockquote" -> {
                    val spans = if (child.select("p").isNotEmpty()) {
                        child.select("p").flatMap { inlines(it) }
                    } else {
                        inlines(child)
                    }
                    if (spans.isNotEmpty()) out.add(Block.Quote(spans))
                }
                "pre" -> {
                    val code = child.text()
                    if (code.isNotBlank()) out.add(Block.Code(code))
                }
                "hr" -> out.add(Block.Divider)
                else -> walk(child, out, blockImages, depth + 1)
            }
        }
    }

    private fun paragraph(p: Element, out: MutableList<Block>, blockImages: Boolean) {
        val imgs = p.select("img")
        if (imgs.isNotEmpty() && !blockImages) {
            imgs.forEach { addImage(it, null, out) }
        }
        val spans = inlines(p)
        if (spans.isNotEmpty()) {
            val center = p.attr("style").contains("center") || p.className().contains("center")
            out.add(Block.Paragraph(spans, center))
        }
    }

    private fun addImage(img: Element, caption: String?, out: MutableList<Block>) {
        val url = img.attr("abs:src").ifBlank { img.absUrl("src") }
            .ifBlank { img.attr("data-src") }
            .ifBlank { img.attr("data-original") }
            .ifBlank { img.attr("src") }
        if (url.isBlank()) return
        val alt = img.attr("alt").ifBlank { caption ?: "" }
        out.add(Block.Image(url, alt, caption?.takeIf { it.isNotBlank() }))
    }

    private fun parseTable(table: Element): Block.Table {
        val header = mutableListOf<Block.Cell>()
        val rows = mutableListOf<List<Block.Cell>>()
        table.select("tr").forEach { tr ->
            val cells = tr.select("th, td").map { cell ->
                val center = cell.attr("style").contains("center") ||
                    cell.attr("align").equals("center", true) ||
                    cell.className().contains("center")
                Block.Cell(inlines(cell), center)
            }
            if (cells.isEmpty()) return@forEach
            val isHeaderRow = tr.select("th").isNotEmpty()
            if (isHeaderRow && rows.isEmpty()) {
                header.addAll(cells)
            } else {
                rows.add(cells)
            }
        }
        // 无 th 时把首行当表头
        if (header.isEmpty() && rows.isNotEmpty()) {
            header.addAll(rows.removeAt(0))
        }
        return Block.Table(
            header = header.takeIf { it.isNotEmpty() },
            rows = rows
        )
    }

    private fun inlines(el: Element): List<Inline> {
        val out = mutableListOf<Inline>()

        fun walk(node: Node, bold: Boolean, underline: Boolean) {
            when (node) {
                is TextNode -> {
                    val t = node.text()
                    if (t.isNotBlank()) out.add(Inline.Text(t, bold, underline))
                }
                is Element -> when (node.tagName()) {
                    "a" -> {
                        val url = node.absUrl("href")
                        val text = node.text().trim()
                        if (text.isNotBlank()) {
                            out.add(Inline.Link(text, url, bold, underline))
                        }
                    }
                    "br" -> out.add(Inline.Text("\n", bold, underline))
                    "img", "script", "style" -> Unit
                    "strong", "b" -> node.childNodes().forEach { walk(it, true, underline) }
                    "u", "ins" -> node.childNodes().forEach { walk(it, bold, true) }
                    else -> node.childNodes().forEach { walk(it, bold, underline) }
                }
            }
        }

        el.childNodes().forEach { walk(it, false, false) }
        return out
    }
}
