//
//  ProdApp.swift
//  Prod
//

import SwiftUI

@main
struct ProdApp: App {
    /// Demo credentials sourced from process args: `-u <user> -p <password>`.
    /// Set them in the Xcode scheme (Edit Scheme → Run → Arguments → Arguments
    /// Passed On Launch). Missing flags crash on launch — no silent empty
    /// fallback that would produce confusing 401s downstream.
    static var demoUser: String { requireArg("-u") }
    static var demoPassword: String { requireArg("-p") }

    private static func requireArg(_ flag: String) -> String {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            preconditionFailure("Missing required launch argument \(flag). Set it in Edit Scheme → Run → Arguments.")
        }
        return args[idx + 1]
    }

    var body: some Scene {
        WindowGroup {
            ContentView(user: Self.demoUser, password: Self.demoPassword)
        }
    }
}
