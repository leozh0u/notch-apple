import Foundation
import CryptoKit
import Security

enum SpotifyConnectionPhase: Equatable {
    case browser, token, keychain

    var title: String {
        switch self {
        case .browser: return "Finish sign-in in your browser"
        case .token: return "Connecting to Spotify…"
        case .keychain: return "Saving your Spotify sign-in…"
        }
    }
    var timeout: TimeInterval {
        switch self {
        case .browser: return 300
        case .token: return 30
        case .keychain: return 10
        }
    }
    var timeoutMessage: String {
        switch self {
        case .browser: return "Spotify sign-in timed out. Connect again and finish sign-in in your browser."
        case .token: return "Spotify took too long to connect. Check your connection and try again."
        case .keychain: return "macOS took too long to save your sign-in. Unlock your Mac and reconnect Spotify."
        }
    }
}

// Pure helpers shared with the credential-free command-line checks.
enum SpotifyAuthorization {
    static let redirectURI = "http://127.0.0.1:8898/callback"
    static let maximumHeaderBytes = 8192
    static let requiredScopes: Set<String> = ["user-library-read", "playlist-read-private", "playlist-read-collaborative"]
    static let playbackScopes: Set<String> = ["user-read-playback-state", "user-modify-playback-state"]
    static var scope: String { requiredScopes.union(playbackScopes).sorted().joined(separator: " ") }
    static func hasPlaybackScopes(_ value: String?) -> Bool {
        playbackScopes.isSubset(of: Set((value ?? "").split(separator: " ").map(String.init)))
    }
    static func hasRequiredScopes(_ value: String?) -> Bool {
        requiredScopes.isSubset(of: Set((value ?? "").split(separator: " ").map(String.init)))
    }

    static func randomURLSafeString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SpotifyLibraryError.message("Could not create a secure Spotify connection. Try again.")
        }
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func isValidID(_ value: String) -> Bool {
        value.count == 22 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
        }
    }

    static func isValidClientID(_ value: String) -> Bool {
        value.count == 32 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    static func authorizationURL(clientID: String, state: String, verifier: String) -> URL? {
        guard isValidClientID(clientID) else { return nil }
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge(for: verifier))
        ]
        return components.url
    }

    enum Callback: Equatable { case code(String), denied }

    static func callback(header: Data, expectedState: String) -> Callback? {
        guard header.count <= maximumHeaderBytes,
              let text = String(data: header, encoding: .utf8), text.contains("\r\n\r\n") else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        let request = lines[0].split(separator: " ", omittingEmptySubsequences: true)
        guard request.count == 3, request[0] == "GET", request[2] == "HTTP/1.1",
              request[1].hasPrefix("/callback?"),
              let components = URLComponents(string: String(request[1])),
              components.scheme == nil, components.host == nil, components.path == "/callback",
              components.fragment == nil else { return nil }
        let hosts = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == "host" else { return nil }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard hosts == ["127.0.0.1:8898"] else { return nil }
        let items = components.queryItems ?? []
        guard ["state", "code", "error"].allSatisfy({ name in items.filter { $0.name == name }.count <= 1 }) else { return nil }
        func unique(_ name: String) -> String? {
            let matches = items.filter { $0.name == name }
            return matches.count == 1 ? matches[0].value : nil
        }
        guard let state = unique("state"), state == expectedState, !state.isEmpty else { return nil }
        if let error = unique("error"), error == "access_denied", unique("code") == nil { return .denied }
        guard unique("error") == nil, let code = unique("code"), !code.isEmpty, code.count <= 2048 else { return nil }
        return .code(code)
    }

    static func formBody(_ values: [String: String]) -> Data {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted(by: { $0.key < $1.key }).map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: safe)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: safe)!)"
        }.joined(separator: "&").utf8)
    }

    static func artworkURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme == "https",
              ["i.scdn.co", "mosaic.scdn.co", "image-cdn-ak.spotifycdn.com", "image-cdn-fa.spotifycdn.com"].contains(url.host ?? ""), url.user == nil, url.password == nil, url.port == nil else { return nil }
        return url
    }
}

enum SpotifyLibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

struct SpotifyAlbum: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let artists: String
    let imageURL: URL?
    var uri: String { "spotify:album:\(id)" }

    private enum CodingKeys: String, CodingKey { case id, name, artists, images }
    private struct Artist: Decodable { let name: String }
    private struct Artwork: Decodable { let url: String; let width: Int? }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        guard SpotifyAuthorization.isValidID(id) else { throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Invalid Spotify album ID") }
        name = try values.decode(String.self, forKey: .name)
        artists = try values.decode([Artist].self, forKey: .artists).map(\.name).joined(separator: ", ")
        let images = try values.decodeIfPresent([Artwork].self, forKey: .images) ?? []
        let ordered = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        let thumbnail = ordered.first(where: { ($0.width ?? 0) >= 128 }) ?? ordered.last
        imageURL = SpotifyAuthorization.artworkURL(thumbnail?.url)
    }
}

struct SpotifyTrack: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let artists: String
    let durationMS: Int
    let trackNumber: Int
    var uri: String { "spotify:track:\(id)" }

    private enum CodingKeys: String, CodingKey { case id, name, artists; case durationMS = "duration_ms"; case trackNumber = "track_number"; case type; case isLocal = "is_local"; case isPlayable = "is_playable" }
    private struct Artist: Decodable { let name: String }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        guard SpotifyAuthorization.isValidID(id) else { throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Invalid Spotify track ID") }
        name = try values.decode(String.self, forKey: .name)
        artists = try values.decode([Artist].self, forKey: .artists).map(\.name).joined(separator: ", ")
        guard try values.decodeIfPresent(String.self, forKey: .type) ?? "track" == "track",
              try values.decodeIfPresent(Bool.self, forKey: .isLocal) != true,
              try values.decodeIfPresent(Bool.self, forKey: .isPlayable) != false else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Unavailable or non-music Spotify item")
        }
        durationMS = max(0, try values.decode(Int.self, forKey: .durationMS))
        trackNumber = max(1, try values.decode(Int.self, forKey: .trackNumber))
    }
}

/// Shares one refresh transaction without tying credential persistence to a view task.
/// Cancelling a waiter does not cancel token rotation; disconnect cancels the owner.
@MainActor
final class SpotifyRefreshTransaction<Value> {
    private var task: Task<Value, Error>?
    private var transactionID = UUID()

    func value(operation: @escaping @MainActor () async throws -> Value,
               isCurrent: @escaping @MainActor () -> Bool,
               commit: @escaping @MainActor (Value) throws -> Void) async throws -> Value {
        if let task { return try await task.value }
        let id = UUID()
        transactionID = id
        let owner = Task { @MainActor in
            let refreshed = try await operation()
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
            // There is no suspension between validating the account and committing.
            try commit(refreshed)
            return refreshed
        }
        task = owner
        defer { if transactionID == id { task = nil } }
        return try await owner.value
    }

    func cancel() {
        transactionID = UUID()
        task?.cancel()
        task = nil
    }
}


struct SpotifyPlaylist: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
    let owner: String
    let imageURL: URL?
    var uri: String { "spotify:playlist:\(id)" }
    private enum CodingKeys: String, CodingKey { case id, name, owner, images }
    private struct Owner: Decodable { let id: String?; let display_name: String? }
    private struct Artwork: Decodable { let url: String; let width: Int? }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        guard SpotifyAuthorization.isValidID(id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: values, debugDescription: "Invalid Spotify playlist ID")
        }
        name = try values.decode(String.self, forKey: .name)
        let profile = try values.decodeIfPresent(Owner.self, forKey: .owner)
        owner = profile?.display_name ?? profile?.id ?? "Spotify"
        let images = try values.decodeIfPresent([Artwork].self, forKey: .images) ?? []
        let ordered = images.sorted { ($0.width ?? 0) < ($1.width ?? 0) }
        imageURL = SpotifyAuthorization.artworkURL((ordered.first { ($0.width ?? 0) >= 128 } ?? ordered.last)?.url)
    }
}

/// Playlist responses renamed `track` to `item` in 2026. Saved songs still use `track`.
/// Null, unavailable, local and podcast entries do not prevent loading valid music.
struct SpotifyTrackItem: Decodable {
    let track: SpotifyTrack?
    private enum CodingKeys: String, CodingKey { case item, track, isLocal = "is_local" }
    init(from decoder: Decoder) throws {
        guard let values = try? decoder.container(keyedBy: CodingKeys.self) else { track = nil; return }
        if (try? values.decode(Bool.self, forKey: .isLocal)) == true { track = nil; return }
        if values.contains(.item) {
            track = try? values.decode(SpotifyTrack.self, forKey: .item)
        } else {
            track = try? values.decode(SpotifyTrack.self, forKey: .track)
        }
    }
}

struct SpotifyOptionalItem<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

struct SpotifyTrackPage: Decodable {
    let items: [SpotifyTrack]
    let total: Int
    let receivedCount: Int
    private enum CodingKeys: String, CodingKey { case items, total }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try values.decode([SpotifyOptionalItem<SpotifyTrack>].self, forKey: .items)
        items = entries.compactMap(\.value)
        receivedCount = entries.count
        total = try values.decode(Int.self, forKey: .total)
    }
}


/// Only the current metadata page is retained; source offsets include skipped entries.
struct SpotifyPageWindow {
    let offset: Int
    let pageSize: Int
    let receivedCount: Int
    let total: Int
    var nextOffset: Int {
        let next = offset.addingReportingOverflow(receivedCount)
        return next.overflow ? Int.max : next.partialValue
    }
    var previousOffset: Int { Self.previousOffset(from: offset, pageSize: pageSize) }
    static func previousOffset(from offset: Int, pageSize: Int) -> Int {
        max(0, max(0, offset) - max(1, pageSize))
    }
    var hasPrevious: Bool { offset > 0 }
    var hasNext: Bool { receivedCount > 0 && nextOffset > offset && nextOffset < total }
    init(offset: Int, pageSize: Int, receivedCount: Int, total: Int) {
        self.offset = max(0, offset)
        self.pageSize = max(1, pageSize)
        self.receivedCount = max(0, receivedCount)
        self.total = max(0, total)
    }
}
