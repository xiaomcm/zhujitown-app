package com.zhujitown.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.zhujitown.app.data.AppViewModel
import com.zhujitown.app.data.AuthBackend
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AccountScreen(vm: AppViewModel, onBack: () -> Unit) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("账号") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(padding)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            val session = vm.session
            if (session != null) {
                ProfileCard(vm)
            } else {
                val canRegister = vm.registrationOpen
                var tab by remember(canRegister) { mutableIntStateOf(0) }

                if (canRegister) {
                    TabRow(selectedTabIndex = tab) {
                        Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("登录") })
                        Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("注册") })
                    }
                }

                if (tab == 0) {
                    LoginForm(vm)
                } else {
                    RegisterForm(vm)
                }

                BackendHint(vm)
            }
        }
    }
}

@Composable
private fun ProfileCard(vm: AppViewModel) {
    val s = vm.session ?: return
    Surface(
        shape = MaterialTheme.shapes.large,
        color = MaterialTheme.colorScheme.surfaceContainer,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(18.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (s.avatarUrl.isNotBlank()) {
                    coil.compose.AsyncImage(
                        model = s.avatarUrl,
                        contentDescription = null,
                        modifier = Modifier
                            .size(60.dp)
                            .clip(CircleShape)
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .size(60.dp)
                            .background(MaterialTheme.colorScheme.primaryContainer, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = s.name.take(1).uppercase(),
                            style = MaterialTheme.typography.titleLarge,
                            color = MaterialTheme.colorScheme.onPrimaryContainer
                        )
                    }
                }
                Column(modifier = Modifier.padding(start = 14.dp)) {
                    Text(s.name, style = MaterialTheme.typography.titleMedium)
                    if (s.email.isNotBlank()) {
                        Text(
                            s.email,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.padding(top = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Badge(if (s.backend == AuthBackend.PLUGIN.id) "站点账号" else "应用密码")
                if (s.canManage) Badge("可查看草稿")
            }

            OutlinedButton(
                onClick = { vm.logout() },
                modifier = Modifier.padding(top = 14.dp)
            ) { Text("退出登录") }
        }
    }

    if (vm.authNotice != null) {
        Text(
            text = vm.authNotice.orEmpty(),
            color = MaterialTheme.colorScheme.primary,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun Badge(text: String) {
    Box(
        modifier = Modifier
            .background(MaterialTheme.colorScheme.secondaryContainer, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 4.dp)
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSecondaryContainer
        )
    }
}

@Composable
private fun LoginForm(vm: AppViewModel) {
    var user by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var showPass by remember { mutableStateOf(false) }
    var showLost by remember { mutableStateOf(false) }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        OutlinedTextField(
            value = user,
            onValueChange = { user = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("用户名或邮箱") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = pass,
            onValueChange = { pass = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("密码") },
            visualTransformation = if (showPass) VisualTransformation.None else PasswordVisualTransformation(),
            trailingIcon = {
                TextButton(onClick = { showPass = !showPass }) {
                    Text(if (showPass) "隐藏" else "显示")
                }
            },
            modifier = Modifier.fillMaxWidth()
        )

        Message(vm)

        Button(
            onClick = { vm.login(user, pass) },
            enabled = !vm.authBusy,
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            if (vm.authBusy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Text("登录")
            }
        }

        TextButton(onClick = { showLost = !showLost }) {
            Text("忘记密码？")
        }

        if (showLost) {
            LostPasswordBlock(vm)
        }
    }
}

@Composable
private fun RegisterForm(vm: AppViewModel) {
    var user by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var pass by remember { mutableStateOf("") }
    var pass2 by remember { mutableStateOf("") }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "注册的是你站点上的账号，新账号默认角色为订阅者。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        OutlinedTextField(
            value = user,
            onValueChange = { user = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("用户名（至少 3 个字符）") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = email,
            onValueChange = { email = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("邮箱") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = pass,
            onValueChange = { pass = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("密码（至少 6 位）") },
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedTextField(
            value = pass2,
            onValueChange = { pass2 = it; vm.clearAuthMessage() },
            singleLine = true,
            label = { Text("确认密码") },
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier.fillMaxWidth()
        )

        Message(vm)

        Button(
            onClick = {
                if (pass != pass2) {
                    vm.clearAuthMessage()
                } else {
                    vm.register(user, email, pass)
                }
            },
            enabled = !vm.authBusy && (pass.isEmpty() || pass == pass2),
            modifier = Modifier
                .fillMaxWidth()
                .height(48.dp)
        ) {
            if (vm.authBusy) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp
                )
            } else {
                Text("注册并登录")
            }
        }
        if (pass.isNotEmpty() && pass != pass2) {
            Text(
                "两次输入的密码不一致",
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall
            )
        }
    }
}

@Composable
private fun LostPasswordBlock(vm: AppViewModel) {
    var login by remember { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surfaceContainer, RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            "填写用户名或邮箱，站点会给你发送一封重置密码邮件。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        OutlinedTextField(
            value = login,
            onValueChange = { login = it },
            singleLine = true,
            label = { Text("用户名或邮箱") },
            modifier = Modifier.fillMaxWidth()
        )
        OutlinedButton(
            onClick = { vm.lostPassword(login) },
            enabled = !vm.authBusy
        ) { Text("发送重置邮件") }
    }
}

@Composable
private fun Message(vm: AppViewModel) {
    vm.authError?.let {
        Text(
            text = it,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium
        )
    }
    vm.authNotice?.let {
        Text(
            text = it,
            color = MaterialTheme.colorScheme.primary,
            style = MaterialTheme.typography.bodyMedium
        )
    }
}

@Composable
private fun BackendHint(vm: AppViewModel) {
    Surface(
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = Modifier.fillMaxWidth()
    ) {
        Column(modifier = Modifier.padding(14.dp)) {
            Text(
                text = if (vm.pluginReady) {
                    "已检测到站点启用了 ZhuJiTown Auth 插件，可直接用站点账号登录${if (vm.registrationOpen) "、注册" else ""}。"
                } else {
                    "站点尚未启用 ZhuJiTown Auth 插件，当前使用 WordPress 自带的「应用程序密码」登录：到网站后台 → 用户 → 个人资料里生成一串应用密码，填在这里的用户名 / 密码即可。"
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
