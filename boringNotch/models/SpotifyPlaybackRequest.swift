import Foundation

struct SpotifyPlaybackRequest {
    let uri: String
    let context: String?

    init?(uri: String, context: String? = nil) {
        guard Self.validURI(uri, types: ["album", "track", "playlist"]),
              context.map({ Self.validURI($0, types: ["album", "playlist"]) }) ?? true else { return nil }
        self.uri = uri
        self.context = context
    }

    private static func validURI(_ value: String, types: Set<String>) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "spotify" && types.contains(String(parts[1]))
            && parts[2].utf8.count == 22 && parts[2].utf8.allSatisfy {
                (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
            }
    }

    var playbackBody: Data {
        get throws {
            let body: [String: Any]
            if uri.hasPrefix("spotify:track:") {
                if let context {
                    body = ["context_uri": context, "offset": ["uri": uri], "position_ms": 0]
                } else {
                    body = ["uris": [uri], "position_ms": 0]
                }
            } else {
                body = ["context_uri": uri, "position_ms": 0]
            }
            return try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        }
    }
}

struct SpotifyPlaybackDevice: Decodable {
    let id: String?
    let name: String
    let type: String
    let is_restricted: Bool

    var isUsableComputer: Bool {
        type.lowercased() == "computer" && !is_restricted && id?.isEmpty == false
    }

    static func thisMac(in devices: [Self], preferredID: String, hostNames: [String]) -> Self? {
        let usable = devices.filter(\.isUsableComputer)
        if !preferredID.isEmpty { return usable.first { $0.id == preferredID } }
        let names = Set(hostNames.map { $0.precomposedStringWithCanonicalMapping.lowercased() })
        let matches = usable.filter { names.contains($0.name.precomposedStringWithCanonicalMapping.lowercased()) }
        return matches.count == 1 ? matches.first : nil
    }
}

/// Resume/pause/skip use noninteractive local events; selecting music uses the Web API.
/// Spotify's local PCtx command may activate its window despite the event flags.
/// The codes come from Spotify.app's published Spotify.sdef dictionary.
enum SpotifyPlaybackTransport {
    static let sendOptions: NSAppleEventDescriptor.SendOptions = [.waitForReply, .neverInteract]
    static let timeout: TimeInterval = 3
    private static let queue = DispatchQueue(label: "com.leozhou.notchapple.spotify-playback")

    static func code(_ value: String) -> UInt32 {
        precondition(value.utf8.count == 4)
        return value.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    static func makeEvent(command: String) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(
            eventClass: code("spfy"), eventID: code(command),
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.spotify.client"),
            returnID: -1, transactionID: 0
        )
    }

    static func send(command: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let event = makeEvent(command: command)
                    let reply = try event.sendEvent(options: sendOptions, timeout: timeout)
                    if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
                        throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
