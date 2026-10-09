package com.zhujitown.app.ui.screens

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ListAlt
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.OpenInBrowser
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import coil.compose.AsyncImage
import com.zhujitown.app.data.AppViewModel
import com.zhujitown.app.data.Cache
import com.zhujitown.app.data.Comment
import com.zhujitown.app.data.Post
import com.zhujitown.app.data.categoryNames
import com.zhujitown.app.data.coverUrl
import com.zhujitown.app.data.tagNames
import com.zhujitown.app.ui.components.BlockView
import com.zhujitown.app.ui.components.ImageViewer
import com.zhujitown.app.ui.components.headingsOf
import com.zhujitown.app.util.ArticleParser
import com.zhujitown.app.util.Block
import com.zhujitown.app.util.Html
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DetailScreen(
    vm: AppViewModel,
    postId: Int,
    onBack: () -> Unit,
    onOpenPost: (Int) -> Unit
) {
    val context = LocalContext.current
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    val listState = rememberLazyListState()
    val fontSize = (16f * vm.fontScale).sp

    var post by remember(postId) { mutableStateOf<Post?>(Cache.load(context, postId)) }
    var blocks by remember(postId) { mutableStateOf<List<Block>>(emptyList()) }
    var related by remember(postId) { mutableStateOf<List<Post>>(emptyList()) }
    var prevPost by remember(postId) { mutableStateOf<Post?>(null) }
    var nextPost by remember(postId) { mutableStateOf<Post?>(null) }
    var comments by remember(postId) { mutableStateOf<List<Comment>>(emptyList()) }
    var loading by remember(postId) { mutableStateOf(false) }
    var error by remember(postId) { mutableStateOf<String?>(null) }
    var favVersion by remember { mutableIntStateOf(0) }
    var preview by remember { mutableStateOf<String?>(null) }
    var tocOpen by remember { mutableStateOf(false) }

    LaunchedEffect(postId) {
        if (post == null) loading = true
    }

    LaunchedEffect(post, loading) {
        if (post == null && loading && error == null) {
            runCatching { vm.fetchPost(postId) }
                .onSuccess { post = it }
                .onFailure { error = vm.messageOf(it) }
            loading = false
        }
    }

    // 正文解析成原生块 + 顺带拉相关阅读 / 上下篇 / 评论
    LaunchedEffect(post?.id) {
        val p = post ?: return@LaunchedEffect
        blocks = withContext(Dispatchers.Default) {
            ArticleParser.parse(p.content.rendered, vm.siteUrl, vm.blockImages)
        }
        Cache.save(context, p)
        launch { related = vm.related(p) }
        launch {
            prevPost = vm.previous(p)
            nextPost = vm.next(p)
        }
        launch { comments = vm.comments(p.id) }
    }

    val openLink: (String) -> Unit = { url ->
        val uri = runCatching { Uri.parse(url) }.getOrNull()
        val siteHost = runCatching { Uri.parse(vm.siteUrl).host }.getOrNull().orEmpty()
            .removePrefix("www.")
        val innerId = uri?.lastPathSegment
            ?.let { Regex("(\\d+)").find(it)?.value?.toIntOrNull() }
        val isInner = uri != null && siteHost.isNotBlank() &&
            uri.host?.endsWith(siteHost) == true && innerId != null
        if (isInner && innerId != postId) {
            onOpenPost(innerId!!)
        } else {
            openExternal(context, url)
        }
    }

    val headings = remember(blocks) { headingsOf(blocks) }

    val progress by remember {
        derivedStateOf {
            val info = listState.layoutInfo
            val total = info.totalItemsCount
            if (total <= 1) 0f else {
                val last = listState.firstVisibleItemIndex + info.visibleItemsInfo.size
                (last.toFloat() / total.toFloat()).coerceIn(0f, 1f)
            }
        }
    }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        Text(
                            text = post?.let { Html.entities(it.title.rendered) } ?: "文章详情",
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            style = MaterialTheme.typography.titleMedium
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = onBack) {
                            Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                        }
                    },
                    actions = {
                        IconButton(onClick = { post?.let { share(context, it) } }) {
                            Icon(Icons.Default.Share, contentDescription = "分享")
                        }
                        IconButton(onClick = { post?.let { openExternal(context, it.link) } }) {
                            Icon(Icons.Default.OpenInBrowser, contentDescription = "浏览器打开")
                        }
                    }
                )
                if (post != null && progress > 0f && progress < 1f) {
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(2.dp)
                    )
                }
            }
        },
        floatingActionButton = {
            if (headings.size >= 2) {
                FloatingActionButton(onClick = { tocOpen = true }) {
                    Icon(Icons.AutoMirrored.Filled.ListAlt, contentDescription = "目录")
                }
            }
        },
        bottomBar = {
            Surface(tonalElevation = 2.dp) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp, vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceEvenly,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val fav = remember(postId, favVersion) { vm.prefs.isFav(postId) }
                    ActionItem(
                        icon = {
                            Icon(
                                imageVector = if (fav) Icons.Default.Bookmark else Icons.Default.BookmarkBorder,
                                contentDescription = null
                            )
                        },
                        label = if (fav) "已收藏" else "收藏",
                        onClick = {
                            post?.let { Cache.save(context, it) }
                            vm.prefs.toggleFav(postId)
                            favVersion++
                        }
                    )
                    ActionItem(
                        icon = { Icon(Icons.Default.FormatSize, contentDescription = null) },
                        label = "字号",
                        onClick = {
                            val next = when {
                                vm.fontScale < 1.0f -> 1.0f
                                vm.fontScale < 1.15f -> 1.15f
                                vm.fontScale < 1.3f -> 1.3f
                                else -> 0.9f
                            }
                            vm.applyFontScale(next)
                        }
                    )
                    ActionItem(
                        icon = { Icon(Icons.AutoMirrored.Filled.ListAlt, contentDescription = null) },
                        label = "目录",
                        onClick = { tocOpen = true }
                    )
                    ActionItem(
                        icon = { Icon(Icons.Default.Refresh, contentDescription = null) },
                        label = "刷新",
                        onClick = { error = null; post = null; loading = true }
                    )
                    ActionItem(
                        icon = { Icon(Icons.Default.OpenInBrowser, contentDescription = null) },
                        label = "原网页",
                        onClick = { post?.let { openExternal(context, it.link) } }
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when {
                post != null -> {
                    val p = post!!
                    LazyColumn(
                        state = listState,
                        modifier = Modifier.fillMaxSize()
                    ) {
                        item { ArticleHeader(post = p, blockImages = vm.blockImages) }

                        itemsIndexed(items = blocks, key = { i, _ -> i }) { _, block ->
                            BlockView(
                                block = block,
                                fontSize = fontSize,
                                onLink = openLink,
                                onPreviewImage = { preview = it },
                                modifier = Modifier.padding(horizontal = 16.dp)
                            )
                        }

                        item { TagSection(post = p) }

                        if (related.isNotEmpty()) {
                            item { RelatedSection(related = related, onOpen = onOpenPost) }
                        }

                        item { NeighborSection(prev = prevPost, next = nextPost, onOpen = onOpenPost) }

                        if (comments.isNotEmpty()) {
                            item { CommentSection(comments = comments) }
                        }

                        item { Spacer(modifier = Modifier.height(72.dp)) }
                    }
                }
                loading -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                error != null -> Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                        modifier = Modifier.padding(24.dp)
                    ) {
                        Text(
                            text = error ?: "加载失败",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center
                        )
                        Button(onClick = { error = null; loading = true }) { Text("重试") }
                    }
                }
            }
        }
    }

    if (tocOpen) {
        Dialog(onDismissRequest = { tocOpen = false }) {
            Surface(shape = RoundedCornerShape(16.dp)) {
                Column(modifier = Modifier.padding(vertical = 12.dp)) {
                    Text(
                        text = "目录",
                        style = MaterialTheme.typography.titleMedium,
                        modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp)
                    )
                    LazyColumn(modifier = Modifier.height(360.dp)) {
                        itemsIndexed(headings) { index, h ->
                            Text(
                                text = if (h.level >= 3) "　　${h.text}" else h.text,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .clickable {
                                        tocOpen = false
                                        scope.launch {
                                            listState.animateScrollToItem(index + 1)
                                        }
                                    }
                                    .padding(horizontal = 18.dp, vertical = 10.dp)
                            )
                        }
                    }
                }
            }
        }
    }

    preview?.let { url ->
        ImageViewer(url = url, onDismiss = { preview = null })
    }
}

@Composable
private fun ArticleHeader(post: Post, blockImages: Boolean) {
    val cover = post.coverUrl()
    Column(modifier = Modifier.fillMaxWidth()) {
        if (!blockImages && cover != null) {
            AsyncImage(
                model = cover,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
            )
        }
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Text(
                text = Html.entities(post.title.rendered),
                style = MaterialTheme.typography.headlineSmall,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(modifier = Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                post.categoryNames().take(3).forEach { name ->
                    Surface(
                        shape = RoundedCornerShape(6.dp),
                        color = MaterialTheme.colorScheme.primaryContainer
                    ) {
                        Text(
                            text = name,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp)
                        )
                    }
                    Spacer(modifier = Modifier.width(6.dp))
                }
                Text(
                    text = Html.dateOf(post.date),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

@Composable
private fun TagSection(post: Post) {
    val tags = post.tagNames()
    if (tags.isEmpty()) return
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        Text(
            text = "相关标签",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface
        )
        LazyRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 8.dp)
        ) {
            items(tags) { t ->
                Surface(
                    shape = RoundedCornerShape(14.dp),
                    color = MaterialTheme.colorScheme.surfaceVariant
                ) {
                    Text(
                        text = t,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun RelatedSection(related: List<Post>, onOpen: (Int) -> Unit) {
    Column(modifier = Modifier.padding(vertical = 12.dp)) {
        Text(
            text = "相关阅读",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(horizontal = 16.dp)
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(items = related, key = { it.id }) { p ->
                Column(
                    modifier = Modifier
                        .width(150.dp)
                        .clickable { onOpen(p.id) }
                ) {
                    val cover = p.coverUrl()
                    if (cover != null) {
                        AsyncImage(
                            model = cover,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(84.dp)
                                .clip(RoundedCornerShape(8.dp))
                        )
                    }
                    Text(
                        text = Html.entities(p.title.rendered),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun NeighborSection(prev: Post?, next: Post?, onOpen: (Int) -> Unit) {
    if (prev == null && next == null) return
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        prev?.let {
            NeighborRow(title = "上一篇：${Html.entities(it.title.rendered)}", onClick = { onOpen(it.id) })
        }
        next?.let {
            NeighborRow(title = "下一篇：${Html.entities(it.title.rendered)}", onClick = { onOpen(it.id) })
        }
    }
}

@Composable
private fun NeighborRow(title: String, onClick: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp)
            .clickable { onClick() }
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)
        )
    }
}

@Composable
private fun CommentSection(comments: List<Comment>) {
    Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
        Text(
            text = "评论 ${comments.size}",
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface
        )
        comments.take(10).forEach { c ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 10.dp)
            ) {
                val avatar = c.author_avatar_urls?.get("48")
                if (avatar != null) {
                    AsyncImage(
                        model = avatar,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .size(36.dp)
                            .clip(CircleShape)
                            .background(MaterialTheme.colorScheme.primaryContainer)
                    )
                }
                Column(modifier = Modifier.padding(start = 10.dp)) {
                    Text(
                        text = Html.entities(c.author_name),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                    Text(
                        text = Html.plain(c.content.rendered, 200),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                    Text(
                        text = Html.dateOf(c.date),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 4.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun ActionItem(
    icon: @Composable () -> Unit,
    label: String,
    onClick: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .clickable { onClick() }
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        icon()
        Text(text = label, style = MaterialTheme.typography.labelSmall)
    }
}

private fun openExternal(context: Context, url: String) {
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return
    val viaTabs = runCatching {
        CustomTabsIntent.Builder().build().launchUrl(context, uri)
    }.isSuccess
    if (!viaTabs) {
        runCatching {
            context.startActivity(
                Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }
}

private fun share(context: Context, post: Post) {
    val text = "${Html.entities(post.title.rendered)}\n${post.link}"
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
        putExtra(Intent.EXTRA_SUBJECT, Html.entities(post.title.rendered))
    }
    runCatching {
        context.startActivity(
            Intent.createChooser(intent, "分享文章").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}
