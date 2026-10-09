package com.zhujitown.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val Brand = Color(0xFF1B64F2)
private val BrandDark = Color(0xFF8AB4F8)

private val LightColors = lightColorScheme(
    primary = Brand,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFDCE6FF),
    secondary = Color(0xFF00A870),
    background = Color(0xFFF6F7F9),
    surface = Color.White,
    surfaceVariant = Color(0xFFF1F2F5),
    onSurface = Color(0xFF1F2126),
    outline = Color(0xFFD8DAE0)
)

private val DarkColors = darkColorScheme(
    primary = BrandDark,
    onPrimary = Color(0xFF0B1C33),
    primaryContainer = Color(0xFF24406B),
    secondary = Color(0xFF4CD9A6),
    background = Color(0xFF101114),
    surface = Color(0xFF16181C),
    surfaceVariant = Color(0xFF22252B),
    onSurface = Color(0xFFE6E8EC),
    outline = Color(0xFF33373F)
)

@Composable
fun ZhujitownTheme(
    themeMode: Int = 0, // 0 跟随系统 1 浅色 2 深色
    content: @Composable () -> Unit
) {
    val dark = when (themeMode) {
        1 -> false
        2 -> true
        else -> isSystemInDarkTheme()
    }
    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        typography = Typography(),
        content = content
    )
}
