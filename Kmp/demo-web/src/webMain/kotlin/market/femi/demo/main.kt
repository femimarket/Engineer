package market.femi.demo

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.window.ComposeViewport
import market.femi.engineer.screen.Engineer

// Standalone browser host for the Engineer screen — the web analog of the
// android :demo MainActivity. Renders the library's Engineer composable full
// viewport; credentials are hardcoded to the same demo user the android app uses.
@OptIn(ExperimentalComposeUiApi::class)
fun main() {
    ComposeViewport {
        Engineer(
            user = "019ec07a-c943-7275-b758-2315b8c9fa6f0",
            password = "ppooiii",
        )
    }
}
