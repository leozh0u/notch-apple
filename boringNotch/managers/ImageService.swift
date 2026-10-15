//
//  ImageService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-13.
//

import Foundation
import Defaults

public protocol ImageServiceProtocol {
    func fetchImageData(from url: URL) async throws -> Data
}

public final class ImageService: ImageServiceProtocol {
    public static let shared = ImageService()

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024,
                             diskCapacity: 16 * 1024 * 1024,
                             diskPath: "artwork_cache")
        config.urlCache = cache
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpShouldSetCookies = false
        self.session = URLSession(configuration: config)

        performLegacyCacheCleanupIfNeeded(cache: cache)
    }

    private func performLegacyCacheCleanupIfNeeded(cache: URLCache) {

        if !Defaults[.didClearLegacyURLCacheV1] {
            cache.removeAllCachedResponses()
            Defaults[.didClearLegacyURLCacheV1] = true
        }
    }

    public func fetchImageData(from url: URL) async throws -> Data {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw URLError(.unsupportedURL)
        }
        let (data, _) = try await session.data(from: url)
        return data
    }
}
