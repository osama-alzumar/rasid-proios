package pro.rasid.app.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import pro.rasid.app.Appearance

/** rasid.pro brand: brand-500 #00D1A0, brand-600 #00A37D, navy #0B1220. */
object Brand {
    val green = Color(0xFF00A37D)
    val greenBright = Color(0xFF00D1A0)
    val navy = Color(0xFF0B1220)
    val orange = Color(0xFFFF9500)
    val cardShape = RoundedCornerShape(18.dp)
}

@Composable
fun RasidTheme(appearance: Appearance, content: @Composable () -> Unit) {
    val dark = when (appearance) { Appearance.SYSTEM -> isSystemInDarkTheme(); Appearance.LIGHT -> false; Appearance.DARK -> true }
    val colors = if (dark) darkColorScheme(
        primary = Brand.greenBright, onPrimary = Brand.navy, secondary = Brand.green,
        background = Color(0xFF000000), surface = Color(0xFF121212), surfaceVariant = Color(0xFF1E1E1E),
    ) else lightColorScheme(
        primary = Brand.green, onPrimary = Color.White, secondary = Brand.greenBright,
        background = Color(0xFFF2F2F7), surface = Color.White, surfaceVariant = Color(0xFFF2F2F7),
    )
    // The app is Arabic-only: force right-to-left even on phones set to another language.
    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
        MaterialTheme(colorScheme = colors, content = content)
    }
}

fun Modifier.cardPadding() = padding(16.dp)
