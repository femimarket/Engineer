pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}
dependencyResolutionManagement {
    // NOTE: no repositoriesMode = FAIL_ON_PROJECT_REPOS here (unlike the reference).
    // The :demo-web browser target makes Kotlin/JS add a project-level repo
    // (https://nodejs.org/dist) to download Node; FAIL_ON_PROJECT_REPOS would reject
    // it. The femi webApp — which runs on web — omits the mode for the same reason.
    repositories {
        google()
        mavenCentral()
        // io.github.femimarket:api lives on GitHub Packages.
        maven("https://maven.pkg.github.com/femimarket/api") {
            credentials {
                username = providers.gradleProperty("gpr.user").orNull ?: System.getenv("GITHUB_ACTOR")
                password = providers.gradleProperty("gpr.key").orNull ?: System.getenv("GITHUB_TOKEN")
            }
            content { includeGroup("io.github.femimarket") }
        }
    }
}

rootProject.name = "EngineerKmp"
include(":engineer")
include(":demo")
include(":demo-web")
