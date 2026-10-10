package com.zhujitown.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Bookmarks
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import com.zhujitown.app.data.AppViewModel
import com.zhujitown.app.data.Cache
import com.zhujitown.app.data.Category
import com.zhujitown.app.data.FeedMode
import com.zhujitown.app.data.Post
import com.zhujitown.app.ui.components.PostCard
import com.zhujitown.app.ui.components.PostList
import com.zhujitown.app.ui.screens.AccountScreen
import com.zhujitown.app.ui.screens.CategoriesScreen
import com.zhujitown.app.ui.screens.DetailScreen
import com.zhujitown.app.ui.screens.DraftsScreen
import com.zhujitown.app.ui.screens.FavoritesScreen
import com.zhujitown.app.ui.screens.HistoryScreen
import com.zhujitown.app.ui.screens.MyCommentsScreen
import com.zhujitown.app.ui.screens.MyPostsScreen
import com.zhujitown.app.ui.screens.ProfileScreen
import com.zhujitown.app.ui.screens.SettingsScreen

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppRoot(vm: AppViewModel, initialPostId: Int) {
    val context = LocalContext.current
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var openPostId by rememberSaveable { mutableIntStateOf(0) }
    var openCategoryId by rememberSaveable { mutableIntStateOf(0) }
    var homeCategoryId by rememberSaveable { mutableIntStateOf(0) }
    var searchOpen by rememberSaveable { mutableStateOf(false) }
    var searchText by rememberSaveable { mutableStateOf("") }
    /** 个人中心子页面：""=个人中心，posts/comments/favorites/history/account/settings/drafts */
    var profileDest by rememberSaveable { mutableStateOf("") }

    LaunchedEffect(initialPostId) {
        if (initialPostId > 0) openPostId = initialPostId
    }

    if (openPostId > 0) {
        DetailScreen(
            vm = vm,
            postId = openPostId,
            onBack = { openPostId = 0 },
            onOpenPost = { openPostId = it }
        )
        return
    }

    val inSearch = searchOpen
    val inCategory = tab == 1 && openCategoryId > 0

    BackHandler(enabled = inSearch || inCategory || profileDest.isNotEmpty()) {
        if (inSearch) {
            searchOpen = false
            vm.refresh(FeedMode.LATEST)
        } else if (inCategory) {
            openCategoryId = 0
        } else if (profileDest.isNotEmpty()) {
            profileDest = ""
        }
    }

    // 进入分类页时拉取该分类文章
    LaunchedEffect(openCategoryId, tab) {
        if (tab == 1 && openCategoryId > 0) {
            val cat = vm.categories.firstOrNull { it.id == openCategoryId }
            vm.refresh(FeedMode.CATEGORY, cat)
        }
    }

    val title = when {
        inSearch -> "搜索文章"
        tab == 0 -> "主机镇"
        tab == 1 -> vm.categories.firstOrNull { it.id == openCategoryId }?.name ?: "全部分类"
        tab == 2 -> "我的收藏"
        else -> "我的"
    }

    val openPost: (Post) -> Unit = { post ->
        Cache.save(context, post)
        openPostId = post.id
    }

    val openPostById: (Int) -> Unit = { openPostId = it }

    Scaffold(
        topBar = {
            Column {
                TopAppBar(
                    title = {
                        if (inSearch) {
                            OutlinedTextField(
                                value = searchText,
                                onValueChange = { searchText = it },
                                singleLine = true,
                                placeholder = { Text("搜商家 / 机型，如：搬瓦工") },
                                textStyle = MaterialTheme.typography.bodyMedium,
                                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                                keyboardActions = KeyboardActions(
                                    onSearch = {
                                        if (searchText.isNotBlank()) {
                                            vm.refresh(FeedMode.SEARCH, null, searchText.trim())
                                        }
                                    }
                                ),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .height(52.dp)
                            )
                        } else {
                            Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                    },
                    navigationIcon = {
                        if (inSearch || inCategory) {
                            IconButton(onClick = {
                                if (inSearch) {
                                    searchOpen = false
                                    vm.refresh(FeedMode.LATEST)
                                } else {
                                    openCategoryId = 0
                                }
                            }) {
                                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                            }
                        }
                    },
                    actions = {
                        if (!inSearch) {
                            IconButton(onClick = {
                                searchText = ""
                                searchOpen = true
                            }) {
                                Icon(Icons.Default.Search, contentDescription = "搜索")
                            }
                        }
                        IconButton(onClick = { vm.refresh() }) {
                            Icon(Icons.Default.Refresh, contentDescription = "刷新")
                        }
                    }
                )
                if (tab == 0 && !inSearch) {
                    CategoryChips(
                        vm = vm,
                        selectedId = homeCategoryId,
                        onSelect = { id ->
                            homeCategoryId = id
                            val cat = vm.categories.firstOrNull { it.id == id }
                            if (cat == null) vm.refresh(FeedMode.LATEST)
                            else vm.refresh(FeedMode.CATEGORY, cat)
                        }
                    )
                }
            }
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = tab == 0,
                    onClick = { tab = 0; searchOpen = false },
                    icon = { Icon(Icons.Default.Home, contentDescription = "首页") },
                    label = { Text("首页") }
                )
                NavigationBarItem(
                    selected = tab == 1,
                    onClick = { tab = 1; searchOpen = false },
                    icon = { Icon(Icons.Default.GridView, contentDescription = "分类") },
                    label = { Text("分类") }
                )
                NavigationBarItem(
                    selected = tab == 2,
                    onClick = { tab = 2; searchOpen = false },
                    icon = { Icon(Icons.Default.Bookmarks, contentDescription = "收藏") },
                    label = { Text("收藏") }
                )
                NavigationBarItem(
                    selected = tab == 3,
                    onClick = { tab = 3; searchOpen = false },
                    icon = { Icon(Icons.Default.Settings, contentDescription = "我的") },
                    label = { Text("我的") }
                )
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when {
                inSearch -> {
                    if (vm.mode == FeedMode.SEARCH && vm.query.isNotBlank()) {
                        PostList(vm = vm, onOpen = openPost)
                    } else {
                        Box(
                            modifier = Modifier
                                .padding(24.dp)
                                .fillMaxWidth()
                        ) {
                            Text(
                                text = "输入关键词后点键盘上的「搜索」",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
                tab == 0 -> PostList(vm = vm, bigFirst = true, onOpen = openPost)
                tab == 1 -> {
                    if (inCategory) {
                        PostList(vm = vm, onOpen = openPost)
                    } else {
                        CategoriesScreen(
                            vm = vm,
                            onOpenCategory = { openCategoryId = it.id },
                            onOpenDrafts = {
                                vm.refresh(FeedMode.DRAFTS)
                                tab = 0
                            }
                        )
                    }
                }
                tab == 2 -> FavoritesScreen(vm = vm, onOpen = openPost)
                else -> when (profileDest) {
                    "posts" -> MyPostsScreen(
                        vm = vm,
                        onBack = { profileDest = "" },
                        onOpenPostId = openPostById
                    )
                    "comments" -> MyCommentsScreen(
                        vm = vm,
                        onBack = { profileDest = "" },
                        onOpenPostId = openPostById
                    )
                    "favorites" -> FavoritesScreen(vm = vm, onOpen = openPost)
                    "history" -> HistoryScreen(
                        vm = vm,
                        onBack = { profileDest = "" },
                        onOpenPost = openPostById
                    )
                    "account" -> AccountScreen(vm = vm, onBack = { profileDest = "" })
                    "settings" -> SettingsScreen(vm = vm, onOpenAccount = { profileDest = "account" })
                    "drafts" -> DraftsScreen(
                        vm = vm,
                        onBack = { profileDest = "" },
                        onOpenPostId = openPostById
                    )
                    else -> ProfileScreen(
                        vm = vm,
                        onNavigate = { profileDest = it },
                        onOpenPost = openPostById
                    )
                }
            }
        }
    }
}

@Composable
private fun CategoryChips(
    vm: AppViewModel,
    selectedId: Int,
    onSelect: (Int) -> Unit
) {
    if (vm.categories.isEmpty()) return
    val shown = remember(vm.categories) { vm.categories.take(20) }
    LazyRow(
        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            FilterChip(
                selected = selectedId == 0,
                onClick = { onSelect(0) },
                label = { Text("最新") }
            )
        }
        items(items = shown, key = { it.id }) { cat: Category ->
            FilterChip(
                selected = selectedId == cat.id,
                onClick = { onSelect(cat.id) },
                label = { Text("${cat.name} ${cat.count}") }
            )
        }
    }
}
