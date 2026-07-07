//
//  MainActivity.kt
//  Demo
//

package studio.femi.demo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import market.femi.engineer.ContentView

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The Engineer screen is dark regardless of system theme; keep the
        // system bar scrims transparent with light foreground icons.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
        )
        setContent {
            ContentView(user = "019ec07a-c943-7275-b758-2315b8c9fa6f", password = "jkjk")
        }
    }
}
