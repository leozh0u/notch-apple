import AppKit
import UniformTypeIdentifiers

// Test doubles keep the real state model away from the user's persisted Shelf.
@MainActor
final class ShelfPersistenceService {
    static let shared = ShelfPersistenceService()
    var saved: [ShelfItem] = []
    func load() -> [ShelfItem] { saved }
    func save(_ items: [ShelfItem]) { saved = items }
}

@MainActor
final class SharingStateManager {
    static let shared = SharingStateManager()
    func beginInteraction() {}
    func endInteraction() {}
}

@main
struct ShelfDropChecks {
    static func dataProvider(_ data: Data, type: UTType) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let directory = fm.temporaryDirectory.appendingPathComponent("shelf-check-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        let source = directory.appendingPathComponent("Finder image with spaces.png")
        let contents = Data("Synthetic file bytes".utf8)
        try contents.write(to: source)

        let direct = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
        let encodedURL = dataProvider(Data(source.absoluteString.utf8), type: .fileURL)
        let path = NSItemProvider(item: source.path as NSString, typeIdentifier: UTType.fileURL.identifier)
        let references = await ShelfDropService.items(from: [direct, encodedURL, path])
        precondition(references.items.count == 3 && references.failedCount == 0,
                     "Finder NSURL, URL bytes, and absolute paths must import")
        for item in references.items {
            precondition(!item.isTemporary && item.fileURL?.standardizedFileURL == source.standardizedFileURL)
            item.cleanupStoredData()
            precondition(fm.fileExists(atPath: source.path), "Removing a reference must preserve the original")
        }

        let representation = NSItemProvider()
        representation.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                                   fileOptions: [], visibility: .all) { completion in
            completion(source, false, nil)
            return nil
        }
        let copied = await ShelfDropService.items(from: [representation])
        precondition(copied.items.count == 1 && copied.failedCount == 0)
        let copy = copied.items[0]
        let copyURL = copy.fileURL!
        precondition(copy.isTemporary && copyURL != source && (try? Data(contentsOf: copyURL)) == contents,
                     "Provider-owned temporary URLs must be copied before their callback expires")
        copy.cleanupStoredData()
        precondition(!fm.fileExists(atPath: copyURL.path) && fm.fileExists(atPath: source.path),
                     "Copy still exists: \(fm.fileExists(atPath: copyURL.path)); source exists: \(fm.fileExists(atPath: source.path)); copy: \(copyURL.path)")

        let text = NSItemProvider(item: "Shelf text" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
        let link = NSItemProvider(item: URL(string: "https://example.com/shelf")! as NSURL,
                                  typeIdentifier: UTType.url.identifier)
        let missing = NSItemProvider(item: directory.appendingPathComponent("missing.png") as NSURL,
                                     typeIdentifier: UTType.fileURL.identifier)
        let mixed = await ShelfDropService.items(from: [text, link, missing])
        precondition(mixed.items.count == 2 && mixed.failedCount == 1)
        precondition(mixed.items[0].kind == .text(string: "Shelf text"))
        precondition(mixed.items[1].kind == .link(url: URL(string: "https://example.com/shelf")!))

        let sentinel = fm.temporaryDirectory.appendingPathComponent("shelf-sentinel-\(UUID().uuidString)")
        try contents.write(to: sentinel)
        defer { try? fm.removeItem(at: sentinel) }
        TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: sentinel)
        precondition(fm.fileExists(atPath: sentinel.path), "Cleanup must refuse unowned temporary files")
        for name in ["../\(sentinel.lastPathComponent)", sentinel.path, "..", ".", "", "/"] {
            let stored = await TemporaryFileStorageService.shared.createTempFile(for: .data(Data("new".utf8), suggestedName: name))!
            precondition(stored != sentinel && stored.deletingLastPathComponent() != fm.temporaryDirectory)
            precondition(stored.standardizedFileURL.path.hasPrefix(stored.deletingLastPathComponent().path + "/"))
            if ["..", ".", "", "/"].contains(name) { precondition(stored.lastPathComponent == "Data.dat") }
            precondition((try? Data(contentsOf: sentinel)) == contents, "Provider names must not overwrite outside their directory")
            TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: stored)
        }
        // Use real image encoders and an isolated pasteboard, never the user's clipboard.
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 12, pixelsHigh: 8,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.systemYellow, atX: 0, y: 0)
        let png = bitmap.representation(using: .png, properties: [:])!
        let jpeg = bitmap.representation(using: .jpeg, properties: [:])!
        let photo = directory.appendingPathComponent("Shelf photo.png")
        let secondPhoto = directory.appendingPathComponent("Shelf photo.jpg")
        try png.write(to: photo)
        try jpeg.write(to: secondPhoto)
        let state = ShelfStateViewModel.shared
        state.load([NSItemProvider(item: photo as NSURL, typeIdentifier: UTType.fileURL.identifier),
                    NSItemProvider(item: secondPhoto as NSURL, typeIdentifier: UTType.fileURL.identifier)],
                   pasteboard: pasteboard)
        for _ in 0..<200 where state.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        precondition(!state.isLoading && state.items.count == 2 && state.copiedPhotoCount == 2)
        precondition(pasteboard.pasteboardItems?.count == 2)
        precondition(pasteboard.pasteboardItems?[0].data(forType: .png) == png, "Preserve original PNG bytes")
        precondition(pasteboard.pasteboardItems?[1].data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)) == jpeg)
        precondition(NSImage(pasteboard: pasteboard)?.size == NSSize(width: 12, height: 8), "Clipboard must contain a pasteable image")
        ShelfSelectionModel.shared.selectSingle(state.items[0])
        let clipboardVersion = pasteboard.changeCount
        state.clear()
        precondition(state.isEmpty && ShelfPersistenceService.shared.saved.isEmpty && !ShelfSelectionModel.shared.hasSelection)
        precondition(fm.fileExists(atPath: photo.path) && fm.fileExists(atPath: secondPhoto.path))
        precondition(pasteboard.changeCount == clipboardVersion && NSImage(pasteboard: pasteboard) != nil,
                     "Clear All must preserve the copied image and original files")

        let ownedProvider = NSItemProvider()
        ownedProvider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(photo, false, nil)
            return nil
        }
        state.load([ownedProvider], pasteboard: pasteboard)
        for _ in 0..<200 where state.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        let ownedURL = state.items.first!.fileURL!
        precondition(ownedURL != photo && state.copiedPhotoCount == 1)
        state.clear()
        precondition(!fm.fileExists(atPath: ownedURL.path) && pasteboard.data(forType: .png) == png,
                     "Owned copies are cleaned up; image bytes survive clearing Shelf")

        // A normal document must not erase an existing photo on the clipboard.
        state.load([direct], pasteboard: pasteboard)
        for _ in 0..<200 where state.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        precondition(state.items.count == 1 && state.copiedPhotoCount == 0 && pasteboard.data(forType: .png) == png)
        state.clear()

        let webPhoto = dataProvider(png, type: .png)
        webPhoto.registerDataRepresentation(forTypeIdentifier: UTType.url.identifier, visibility: .all) { completion in
            completion(Data("https://example.com/photo.png".utf8), nil)
            return nil
        }
        state.load([webPhoto], pasteboard: pasteboard)
        for _ in 0..<200 where state.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        precondition(state.items.count == 1 && state.items[0].isTemporary && state.copiedPhotoCount == 1,
                     "An image offered alongside its web URL must import as an image")
        state.clear()

        let slowPhoto = NSItemProvider()
        slowPhoto.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) { completion(jpeg, nil) }
            return nil
        }
        state.load([slowPhoto], pasteboard: pasteboard)
        state.load([NSItemProvider(item: photo as NSURL, typeIdentifier: UTType.fileURL.identifier)], pasteboard: pasteboard)
        for _ in 0..<200 where state.isLoading { try await Task.sleep(for: .milliseconds(20)) }
        precondition(state.items.count == 2 && pasteboard.data(forType: .png) == png,
                     "A slower earlier drop must not overwrite the newer photo on the clipboard")
        state.clear()

        let lateProvider = NSItemProvider()
        lateProvider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { completion(png, nil) }
            return nil
        }
        state.load([lateProvider], pasteboard: pasteboard)
        state.clear()
        try await Task.sleep(for: .milliseconds(400))
        precondition(state.isEmpty && !state.isLoading && state.copiedPhotoCount == 0,
                     "Clear All must also discard pending imports")
        print("Shelf checks passed: imports, owned cleanup, original preservation, PNG/JPEG image clipboard, retained photos, Clear All, pending import cancellation, and document clipboard preservation.")
    }
}
