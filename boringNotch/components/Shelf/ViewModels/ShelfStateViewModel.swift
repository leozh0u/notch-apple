//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false
    @Published var importError: String?
    @Published private(set) var copiedPhotoCount = 0
    private var importEpoch = UUID()
    private var latestImport = UUID()
    private var activeImports = 0

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        importEpoch = UUID()
        activeImports = 0
        isLoading = false
        copiedPhotoCount = 0
        importError = nil
        updateTask?.cancel()
        pendingBookmarkUpdates.removeAll()
        let removed = items
        items = []
        ShelfSelectionModel.shared.clear()
        for item in removed { item.cleanupStoredData() }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider], pasteboard: NSPasteboard = .general) {
        guard !providers.isEmpty else { return }
        importError = nil
        copiedPhotoCount = 0
        let epoch = importEpoch
        let importID = UUID()
        latestImport = importID
        activeImports += 1
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            guard let self, epoch == self.importEpoch else {
                for item in dropped.items { item.cleanupStoredData() }
                return
            }
            self.add(dropped.items)
            if dropped.failedCount > 0 {
                self.importError = "Couldn't add \(dropped.failedCount) \(dropped.failedCount == 1 ? "item" : "items"). Try Add files to choose files directly."
            }
            let bookmarks = dropped.items.compactMap { item -> Data? in
                if case .file(let data) = item.kind { return data }
                return nil
            }
            let photos = await ShelfPhotoClipboard.prepare(bookmarks: bookmarks)
            guard epoch == self.importEpoch else { return }
            if importID == self.latestImport, ShelfPhotoClipboard.write(photos, to: pasteboard) {
                self.copiedPhotoCount = photos.count
            }
            self.activeImports -= 1
            self.isLoading = self.activeImports > 0
        }
    }

    func chooseFiles() {
        SharingStateManager.shared.beginInteraction()
        defer { SharingStateManager.shared.endInteraction() }
        let panel = NSOpenPanel()
        panel.title = "Add files to Shelf"
        panel.prompt = "Add"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            load(panel.urls.map { NSItemProvider(item: $0 as NSURL, typeIdentifier: UTType.fileURL.identifier) })
        }
    }

    func cleanupInvalidItems() {
        let epoch = importEpoch
        Task { [weak self] in
            guard let self else { return }
            var invalidIDs: Set<UUID> = []
            for item in self.items {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if !(await bookmark.validate()) {
                        invalidIDs.insert(item.id)
                        item.cleanupStoredData()
                    }
                default:
                    break
                }
            }
            guard epoch == self.importEpoch else { return }
            self.items.removeAll { invalidIDs.contains($0.id) }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
