package com.zhujitown.app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.zhujitown.app.data.AppViewModel
import com.zhujitown.app.ui.AppRoot
import com.zhujitown.app.ui.theme.ZhujitownTheme

class MainActivity : ComponentActivity() {

    private var deepLinkPostId by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deepLinkPostId = parsePostId(intent)
        setContent {
            val vm: AppViewModel = viewModel()
            ZhujitownTheme(themeMode = vm.themeMode) {
                AppRoot(vm = vm, initialPostId = deepLinkPostId)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val id = parsePostId(intent)
        if (id > 0) deepLinkPostId = id
    }

    /** 支持 https://www.zhujitown.com/3149.html 与 ?p=3149 两种形态 */
    private fun parsePostId(intent: Intent?): Int {
        val uri = intent?.data ?: return 0
        uri.getQueryParameter("p")?.toIntOrNull()?.let { return it }
        val seg = uri.lastPathSegment ?: return 0
        return Regex("(\\d+)").find(seg)?.value?.toIntOrNull() ?: 0
    }
}
