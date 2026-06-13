//
//  ImageIterate2App.swift
//  ImageIterate2
//
//  Created by u on 13/06/2026.
//

import SwiftUI

@main
struct ImageIterate2App: App {
    /// Demo bearer used by this sample app. Real apps consuming the
    /// `ContentView` library MUST source their bearer from Keychain or a
    /// server-issued session — never from a literal in source.
    static let demoBearer = "019ec07a-c943-7275-b758-2315b8c9fa6f"

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
                bearer: Self.demoBearer,
                onCommit: { _, _ in }
            )
        }
    }
}

#Preview {
    ContentView(
        initialImagePath: ImageIterate2App.demoImagePath,
        bearer: ImageIterate2App.demoBearer,
        onCommit: { _, _ in }
    )
}
