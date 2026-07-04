package market.femi.screen

// Brand-font slot for the Engineer screen. The screen itself ships no font —
// a host app supplies its brand family by wrapping the screen, and every child
// Text inherits it through this CompositionLocal:
//
//     CompositionLocalProvider(LocalBrandFont provides myFamily) {
//         Engineer(...)
//     }

import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.text.font.FontFamily

val LocalBrandFont = staticCompositionLocalOf<FontFamily> { FontFamily.SansSerif }

/** Kept so Engineer.kt stays line-compatible with the webApp original: the
 *  screen's own `LocalBrandFont provides brandFamily()` becomes a passthrough
 *  of whatever the host provided. */
@Composable
internal fun brandFamily(): FontFamily = LocalBrandFont.current
