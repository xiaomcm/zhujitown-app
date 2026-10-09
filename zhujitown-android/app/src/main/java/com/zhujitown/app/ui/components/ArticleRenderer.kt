package com.zhujitown.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.LinkInteractionListener
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import coil.compose.SubcomposeAsyncImage
import com.zhujitown.app.util.Block
import com.zhujitown.app.util.Inline

/** 行内富文本（加粗 + 可点链接） */
@Composable
fun RichText(
    spans: List<Inline>,
    fontSize: TextUnit,
    color: Color,
    linkColor: Color,
    align: TextAlign = TextAlign.Start,
    onLink: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val annotated = buildAnnotatedString {
        spans.forEach { s ->
            when (s) {
                is Inline.Text -> withStyle(
                    SpanStyle(
                        fontWeight = if (s.bold) FontWeight.Bold else FontWeight.Normal,
                        textDecoration = if (s.underline) TextDecoration.Underline else TextDecoration.None
                    )
                ) { append(s.value) }
                is Inline.Link -> {
                    pushLink(
                        LinkAnnotation.Url(
                            url = s.url,
                            linkInteractionListener = LinkInteractionListener { onLink(s.url) }
                        )
                    )
                    withStyle(
                        SpanStyle(
                            color = linkColor,
                            fontWeight = if (s.bold) FontWeight.Bold else FontWeight.Medium,
                            textDecoration = if (s.underline) {
                                TextDecoration.combine(
                                    listOf(TextDecoration.Underline)
                                )
                            } else {
                                TextDecoration.None
                            }
                        )
                    ) { append(s.text) }
                    pop()
                }
            }
        }
    }
    Text(
        text = annotated,
        modifier = modifier,
        style = TextStyle(
            fontSize = fontSize,
            lineHeight = fontSize * 1.75f,
            color = color,
            textAlign = align
        )
    )
}

@Composable
fun BlockView(
    block: Block,
    fontSize: TextUnit,
    onLink: (String) -> Unit,
    onPreviewImage: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val cs = MaterialTheme.colorScheme
    val bodyColor = cs.onSurface
    val linkColor = cs.primary
    val subColor = cs.onSurfaceVariant

    when (block) {
        is Block.Heading -> {
            val size = when (block.level) {
                1 -> fontSize * 1.45f
                2 -> fontSize * 1.22f
                3 -> fontSize * 1.08f
                else -> fontSize * 1.0f
            }
            Row(
                modifier = modifier
                    .fillMaxWidth()
                    .padding(top = 18.dp, bottom = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Box(
                    modifier = Modifier
                        .width(4.dp)
                        .height((size.value * 1.2).dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(cs.primary)
                )
                Text(
                    text = block.text,
                    style = MaterialTheme.typography.titleMedium.copy(
                        fontSize = size,
                        fontWeight = FontWeight.Bold,
                        lineHeight = size * 1.45f
                    ),
                    color = cs.onSurface,
                    modifier = Modifier.padding(start = 10.dp)
                )
            }
        }

        is Block.Paragraph -> RichText(
            spans = block.spans,
            fontSize = fontSize,
            color = bodyColor,
            linkColor = linkColor,
            align = if (block.center) TextAlign.Center else TextAlign.Start,
            onLink = onLink,
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 6.dp)
        )

        is Block.Image -> Column(
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            SubcomposeAsyncImage(
                model = block.url,
                contentDescription = block.alt.ifBlank { null },
                contentScale = ContentScale.FillWidth,
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .clickable { onPreviewImage(block.url) },
                loading = {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(150.dp)
                            .background(cs.surfaceVariant)
                    )
                },
                error = {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 60.dp)
                            .background(cs.surfaceVariant),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = block.alt.ifBlank { "图片加载失败" },
                            style = MaterialTheme.typography.labelSmall,
                            color = subColor
                        )
                    }
                }
            )
            block.caption?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelSmall,
                    color = subColor,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(top = 6.dp)
                )
            }
        }

        is Block.Table -> TableView(
            table = block,
            fontSize = fontSize,
            onLink = onLink,
            modifier = modifier
        )

        is Block.ListBlock -> Column(
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            block.items.forEachIndexed { i, item ->
                Row(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = if (block.ordered) "${i + 1}. " else "• ",
                        style = MaterialTheme.typography.bodyMedium.copy(fontSize = fontSize),
                        color = subColor
                    )
                    Box(modifier = Modifier.weight(1f)) {
                        RichText(
                            spans = item,
                            fontSize = fontSize,
                            color = bodyColor,
                            linkColor = linkColor,
                            onLink = onLink
                        )
                    }
                }
            }
        }

        is Block.Quote -> Surface(
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
            color = cs.surfaceVariant
        ) {
            Box(modifier = Modifier.fillMaxWidth()) {
                Box(
                    modifier = Modifier
                        .width(3.dp)
                        .height(6.dp)
                        .background(Color.Transparent)
                )
                RichText(
                    spans = block.spans,
                    fontSize = fontSize,
                    color = subColor,
                    linkColor = linkColor,
                    onLink = onLink,
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 10.dp)
                )
            }
        }

        is Block.Code -> Surface(
            modifier = modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            shape = RoundedCornerShape(8.dp),
            color = cs.surfaceVariant
        ) {
            Text(
                text = block.text,
                style = MaterialTheme.typography.bodySmall.copy(
                    fontFamily = FontFamily.Monospace,
                    fontSize = fontSize * 0.9f
                ),
                color = bodyColor,
                modifier = Modifier.padding(12.dp)
            )
        }

        Block.Divider -> HorizontalDivider(
            modifier = modifier.padding(vertical = 14.dp),
            color = cs.outline
        )
    }
}

@Composable
private fun TableView(
    table: Block.Table,
    fontSize: TextUnit,
    onLink: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    val cs = MaterialTheme.colorScheme
    val borderColor = cs.outline
    val headBg = cs.surfaceVariant

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp)
            .horizontalScroll(rememberScrollState())
    ) {
        Column {
            table.header?.let { head ->
                Row {
                    head.forEach { cell ->
                        CellBox(
                            cell = cell,
                            fontSize = fontSize,
                            onLink = onLink,
                            background = headBg,
                            bold = true,
                            borderColor = borderColor
                        )
                    }
                }
            }
            table.rows.forEach { row ->
                Row {
                    row.forEach { cell ->
                        CellBox(
                            cell = cell,
                            fontSize = fontSize,
                            onLink = onLink,
                            background = Color.Transparent,
                            bold = false,
                            borderColor = borderColor
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CellBox(
    cell: Block.Cell,
    fontSize: TextUnit,
    onLink: (String) -> Unit,
    background: Color,
    bold: Boolean,
    borderColor: Color
) {
    val cs = MaterialTheme.colorScheme
    Box(
        modifier = Modifier
            .widthIn(min = 96.dp, max = 210.dp)
            .background(background)
            .border(0.5.dp, borderColor)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        contentAlignment = if (cell.center) Alignment.Center else Alignment.CenterStart
    ) {
        val spans = if (bold) {
            cell.spans.map {
                when (it) {
                    is Inline.Text -> it.copy(bold = true)
                    is Inline.Link -> it
                }
            }
        } else {
            cell.spans
        }
        RichText(
            spans = spans,
            fontSize = fontSize * 0.95f,
            color = cs.onSurface,
            linkColor = cs.primary,
            align = if (cell.center) TextAlign.Center else TextAlign.Start,
            onLink = onLink
        )
    }
}

/** 把解析好的块渲染成列表项（供 LazyColumn 使用） */
@Composable
fun BlocksContent(
    blocks: List<Block>,
    fontSize: TextUnit,
    onLink: (String) -> Unit,
    onPreviewImage: (String) -> Unit
) {
    blocks.forEach { block ->
        BlockView(
            block = block,
            fontSize = fontSize,
            onLink = onLink,
            onPreviewImage = onPreviewImage,
            modifier = Modifier.fillMaxWidth()
        )
    }
}

/** 供目录使用 */
fun headingsOf(blocks: List<Block>): List<Block.Heading> =
    blocks.filterIsInstance<Block.Heading>().filter { it.level <= 3 }
