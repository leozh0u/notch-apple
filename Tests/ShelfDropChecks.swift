import AppKit
import UniformTypeIdentifiers

// Keep the standalone test away from the user's persisted Shelf.
@MainActor
final class ShelfStateViewModel {
    static let shared = ShelfStateViewModel()
    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let data) = item.kind else { return nil }
        return Bookmark(data: data).resolveURL()
    }
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
        print("Shelf checks passed: Finder URL/data/path imports, bookmark resolution, owned copies, original preservation, text/links, failure counts, traversal-safe names.")
    }
}
