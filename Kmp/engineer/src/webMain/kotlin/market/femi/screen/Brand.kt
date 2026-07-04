package market.femi.screen

// Brand font for the Engineer screen. The screen inherits the host's font when
// the host theme provides one (MaterialTheme typography / ProvideTextStyle);
// otherwise it falls back to this local's brand default. The screen root's
// `LocalBrandFont provides brandFamily()` anchors the detected family for
// every Text inside.

import androidx.compose.material3.LocalTextStyle
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.font.FontFamily

internal val LocalBrandFont = staticCompositionLocalOf<FontFamily> { FontFamily.SansSerif }

@Composable
internal fun brandFamily(): FontFamily =
    LocalTextStyle.current.fontFamily   // host theme set a font → inherit it
        ?: LocalBrandFont.current       // host set none → lib brand default
