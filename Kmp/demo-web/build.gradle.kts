import org.jetbrains.kotlin.gradle.ExperimentalWasmDsl

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.composeMultiplatform)
}

// Web analog of the android :demo app — a standalone browser host that renders
// the :engineer library's Engineer screen. Run with:
//   ./gradlew :demo-web:jsBrowserDevelopmentRun
//   ./gradlew :demo-web:wasmJsBrowserDevelopmentRun
kotlin {
    js {
        useEsModules() // the api is a pure ESM package; @JsModule needs ES output
        browser {
            commonWebpackConfig {
                outputFileName = "demoWeb.js"
            }
        }
        binaries.executable()
    }
    @OptIn(ExperimentalWasmDsl::class)
    wasmJs {
        browser {
            commonWebpackConfig {
                outputFileName = "demoWeb.js"
            }
        }
        binaries.executable()
    }

    sourceSets {
        commonMain.dependencies {
            implementation(project(":engineer"))
            implementation(compose.runtime)
            implementation(compose.ui)
        }
    }
}
