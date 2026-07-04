//
//  ImageIterate2App.swift
//  ImageIterate2
//

import SwiftUI

@main
struct ImageIterate2App: App {
    /// Demo credentials sourced from process args: `-u <user> -p <password>`.
    /// Set them in the Xcode scheme (Edit Scheme → Run → Arguments → Arguments
    /// Passed On Launch). Missing flags crash on launch.
    static var demoUser: String { requireArg("-u") }
    static var demoPassword: String { requireArg("-p") }

    private static func requireArg(_ flag: String) -> String {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            preconditionFailure("Missing required launch argument \(flag). Set it in Edit Scheme → Run → Arguments.")
        }
        return args[idx + 1]
    }

    /// Disk path of the bundled demo PNG. Its basename happens to match a
    /// real asset on femi.market, so the first generation can reference it.
    static var demoImagePath: String {
        Bundle.main.path(
            forResource: "demoUploadSong_019e7f3d-aa21-7173-86ae-fbe8d61d0a84",
            ofType: "png"
        ) ?? ""
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                initialImagePath: Self.demoImagePath,
                user: Self.demoUser,
                password: Self.demoPassword,
                onCommit: { _, _ in }
            )
        }
    }
}

#Preview {
    ContentView(
        initialImagePath: ImageIterate2App.demoImagePath,
        user: "preview",
        password: "preview",
        onCommit: { _, _ in }
    )
}
