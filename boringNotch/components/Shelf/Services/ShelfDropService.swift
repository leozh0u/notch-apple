//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> (items: [ShelfItem], failedCount: Int) {
        var results: [ShelfItem] = []
        var failedCount = 0

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            } else {
                failedCount += 1
            }
        }

        return (results, failedCount)
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            // Create the bookmark while the provider's file access is still valid.
            if let bookmark = await loadFileBookmark(provider, typeIdentifier: UTType.fileURL.identifier) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }
        
        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        for typeIdentifier in provider.registeredTypeIdentifiers {
            guard let type = UTType(typeIdentifier), type.conforms(to: .item),
                  !type.conforms(to: .url), !type.conforms(to: .text) else { continue }
            if let bookmark = await copyFileRepresentation(provider, typeIdentifier: typeIdentifier) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            if let data = await loadData(provider, typeIdentifier: typeIdentifier),
               let url = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)) {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
                }
                TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            }
        }
        
        return nil
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        return (try? Bookmark(url: url))?.data
    }

    private static func loadFileBookmark(_ provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = String(data: data, encoding: .utf8).flatMap(fileURL(from:))
                        ?? Bookmark(data: data).resolveURL()
                } else if let string = item as? String {
                    url = fileURL(from: string)
                } else {
                    url = nil
                }
                continuation.resume(returning: url.flatMap(createBookmark(for:)))
            }
        }
    }

    private static func fileURL(from string: String) -> URL? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/") { return URL(fileURLWithPath: value) }
        guard let url = URL(string: value), url.isFileURL else { return nil }
        return url
    }

    private static func copyFileRepresentation(_ provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // Provider URLs expire when this callback returns; retain only our own copy.
                let directory = TemporaryFileStorageService.storageDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                let copy = directory.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try url.accessSecurityScopedResource { source in
                        try FileManager.default.copyItem(at: source, to: copy)
                    }
                    let bookmark = try Bookmark(url: copy).data
                    continuation.resume(returning: bookmark)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadData(_ provider: NSItemProvider, typeIdentifier: String) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

