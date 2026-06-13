//
//  MediaApi.swift
//  femi
//
//  Created by u on 11/06/2026.
//
//  Authenticated media (images, audio, video) from femi.market.
//

import Foundation

enum MediaApi {
    /// Fetch bytes for a filename. The only thing this API does.
    static func fetch(_ filename: String, idToken: String) async throws -> Data {
        let path = filename.hasPrefix("/") ? String(filename.dropFirst()) : filename
        guard !path.isEmpty, let url = URL(string: "https://femi.market/\(path)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        return data
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024
        )
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config)
    }()
}
