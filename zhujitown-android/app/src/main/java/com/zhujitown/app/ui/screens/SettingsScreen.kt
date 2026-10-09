package com.zhujitown.app.ui.screens

import android.content.Context
import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.zhujitown.app.data.AppViewModel
import com.zhujitown.app.data.AuthBackend
import com.zhujitown.app.data.Cache

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(vm: AppViewModel, onOpenAccount: () -> Unit) {
    val context = LocalContext.current
    var siteText by remember(vm.siteUrl) { mutableStateOf(vm.siteUrl) }
    var cacheSize by remember { mutableStateOf(Cache.size(context)) }
    var note by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            val s = vm.session
            Section("账号") {
                if (s == null) {
                    Text(
                        text = "当前未登录。登录用的是你网站的账号；若站点开放了注册，也可在 App 内直接注册。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Button(
                        onClick = onOpenAccount,
                        modifier = Modifier.padding(top = 8.dp)
                    ) { Text("登录 / 注册") }
                } else {
                    Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                        if (s.avatarUrl.isNotBlank()) {
                            coil.compose.AsyncImage(
                                model = s.avatarUrl,
                                contentDescription = null,
                                modifier = Modifier
                                    .size(52.dp)
                                    .clip(androidx.compose.foundation.shape.CircleShape)
                            )
                        } else {
                            androidx.compose.foundation.layout.Box(
                                modifier = Modifier
                                    .size(52.dp)
                                    .background(
                                        MaterialTheme.colorScheme.primaryContainer,
                                        androidx.compose.foundation.shape.CircleShape
                                    ),
                                contentAlignment = androidx.compose.ui.Alignment.Center
                            ) {
                                Text(
                                    text = s.name.take(1).uppercase(),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onPrimaryContainer
                                )
                            }
                        }
                        Column(modifier = Modifier.padding(start = 12.dp)) {
                            Text(s.name, style = MaterialTheme.typography.titleSmall)
                            if (s.email.isNotBlank()) {
                                Text(
                                    s.email,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                            Text(
                                text = when (s.backend) {
                                    AuthBackend.PLUGIN.id -> "已登录 · 站点账号"
                                    AuthBackend.JWT_PLUGIN.id -> "已登录 · JWT"
                                    else -> "已登录 · 应用密码"
                                },
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.primary
                            )
                        }
                    }
                    Row(modifier = Modifier.padding(top = 10.dp)) {
                        Button(onClick = onOpenAccount) { Text("账号管理") }
                        androidx.compose.material3.OutlinedButton(
                            onClick = { vm.logout(); note = "已退出登录" },
                            modifier = Modifier.padding(start = 8.dp)
                        ) { Text("退出登录") }
                    }
                }
            }
        }

        item {
            Section("站点") {
                OutlinedTextField(
                    value = siteText,
                    onValueChange = { siteText = it },
                    singleLine = true,
                    label = { Text("WordPress 站点地址") },
                    modifier = Modifier.fillMaxWidth()
                )
                Button(
                    onClick = {
                        vm.saveSite(siteText)
                        note = "已保存并重新加载"
                    },
                    modifier = Modifier.padding(top = 8.dp)
                ) { Text("保存并刷新") }
            }
        }

        item {
            Section("外观") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilterChip(
                        selected = vm.themeMode == 0,
                        onClick = { vm.applyThemeMode(0) },
                        label = { Text("跟随系统") }
                    )
                    FilterChip(
                        selected = vm.themeMode == 1,
                        onClick = { vm.applyThemeMode(1) },
                        label = { Text("浅色") }
                    )
                    FilterChip(
                        selected = vm.themeMode == 2,
                        onClick = { vm.applyThemeMode(2) },
                        label = { Text("深色") }
                    )
                }
            }
        }

        item {
            Section("阅读") {
                Text(
                    text = "正文字号：${(vm.fontScale * 100).toInt()}%",
                    style = MaterialTheme.typography.bodyMedium
                )
                Slider(
                    value = vm.fontScale,
                    onValueChange = { vm.applyFontScale(it) },
                    valueRange = 0.85f..1.35f
                )
                Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Switch(
                        checked = vm.blockImages,
                        onCheckedChange = { vm.applyBlockImages(it) }
                    )
                    Text(
                        text = "无图模式（省流量）",
                        modifier = Modifier.padding(start = 10.dp),
                        style = MaterialTheme.typography.bodyMedium
                    )
                }
            }
        }

        item {
            Section("离线缓存") {
                Text(
                    text = "已缓存 ${formatSize(context, cacheSize)}（收藏的文章可离线阅读）",
                    style = MaterialTheme.typography.bodyMedium
                )
                Button(
                    onClick = {
                        Cache.clear(context)
                        cacheSize = Cache.size(context)
                        note = "缓存已清除"
                    },
                    modifier = Modifier.padding(top = 8.dp)
                ) { Text("清除缓存") }
            }
        }

        item {
            Section("关于") {
                Text(
                    text = "主机镇 App v1.0.0\n数据源：WordPress REST API（/wp-json/wp/v2）",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
                if (note.isNotBlank()) {
                    Text(
                        text = note,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(top = 6.dp)
                    )
                }
            }
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurface
            )
            Column(modifier = Modifier.padding(top = 10.dp)) {
                content()
            }
        }
    }
}

private fun formatSize(context: Context, bytes: Long): String =
    Formatter.formatShortFileSize(context, bytes)
