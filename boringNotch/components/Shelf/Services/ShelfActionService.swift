//
//  ShelfActionService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ShelfPhotoClipboard {
    struct Photo: Sendable {
        let representations: [String: Data]
    }

    static func prepare(bookmarks: [Data]) async -> [Photo] {
        await Task.detached(priority: .userInitiated) {
            bookmarks.compactMap { bookmark in
                autoreleasepool {
                    guard let url = Bookmark(data: bookmark).resolveURL() else { return nil }
                    return url.accessSecurityScopedResource { url -> Photo? in
                        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let identifier = CGImageSourceGetType(source) as String?,
                              let type = UTType(identifier), type.conforms(to: .image),
                              let data = try? Data(contentsOf: url) else { return nil }
                        var representations = [identifier: data]
                        // Eager image bytes keep Paste working after Shelf's temporary copy is cleared.
                        if type != .png {
                            let png = NSMutableData()
                            guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                                  let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
                            CGImageDestinationAddImage(destination, image, nil)
                            guard CGImageDestinationFinalize(destination) else { return nil }
                            representations[UTType.png.identifier] = png as Data
                        } else if CGImageSourceGetCount(source) == 0 {
                            return nil
                        }
                        return Photo(representations: representations)
                    }
                }
            }
        }.value
    }

    @MainActor
    @discardableResult
    static func write(_ photos: [Photo], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !photos.isEmpty else { return false }
        let items = photos.map { photo in
            let item = NSPasteboardItem()
            for (type, data) in photo.representations {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(items)
    }
}

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmark):
            handleBookmarkedFile(bookmark) { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    private static func handleBookmarkedFile(_ bookmarkData: Data, action: @escaping @Sendable (URL) -> Void) {
        Task {
            let bookmark = Bookmark(data: bookmarkData)
            if let url = bookmark.resolveURL() {
                url.accessSecurityScopedResource { accessibleURL in
                    action(accessibleURL)
                }
            }
        }
    }
}

