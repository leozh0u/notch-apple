import Foundation

@main
struct SpotifyLibraryChecks {
    @MainActor
    static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        // RFC 7636 appendix B: the published verifier/challenge test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        check(SpotifyAuthorization.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "PKCE S256 mismatch")
        let first = try SpotifyAuthorization.randomURLSafeString()
        let second = try SpotifyAuthorization.randomURLSafeString()
        check(first.count == 43 && first != second, "PKCE randomness/length")
        check(first.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }, "Verifier alphabet")
        let clientID = String(repeating: "a", count: 32)
        let authorization = SpotifyAuthorization.authorizationURL(clientID: clientID, state: first, verifier: second)!
        let authorizationItems = URLComponents(url: authorization, resolvingAgainstBaseURL: false)!.queryItems!
        check(authorization.scheme == "https" && authorization.host == "accounts.spotify.com", "Fixed authorize origin")
        let requestedScopes = Set((authorizationItems.first(where: { $0.name == "scope" })?.value ?? "").split(separator: " ").map(String.init))
        check(requestedScopes == ["user-library-read", "playlist-read-private", "playlist-read-collaborative"], "Read-only library scopes")
        check(!SpotifyAuthorization.hasRequiredScopes("user-library-read"), "Old album-only credentials require reconnect")
        check(!SpotifyAuthorization.hasRequiredScopes(nil), "Legacy credentials require reconnect once")
        check(SpotifyAuthorization.hasRequiredScopes(SpotifyAuthorization.scope), "Full new read-only grants accepted")
        check(authorizationItems.first(where: { $0.name == "redirect_uri" })?.value == SpotifyAuthorization.redirectURI, "Loopback callback")
        check(!authorization.absoluteString.contains(second), "Verifier must not appear in the authorization URL")
        check(SpotifyAuthorization.authorizationURL(clientID: "bad", state: first, verifier: second) == nil, "Invalid Client ID")
        check(!SpotifyAuthorization.isValidID("../../arbitrary/command"), "Reject URI injection")
        check(!SpotifyAuthorization.isValidID(String(repeating: "é", count: 22)), "Spotify IDs are ASCII")
        check(SpotifyAuthorization.isValidID("4aawyAB9vmqN3uQ7FjRGTy"), "Valid Spotify ID")

        func header(_ target: String, host: String = "127.0.0.1:8898", method: String = "GET") -> Data {
            Data("\(method) \(target) HTTP/1.1\r\nHost: \(host)\r\n\r\n".utf8)
        }
        let callback = "/callback?state=expected&code=one-use-code"
        check(SpotifyAuthorization.callback(header: header(callback), expectedState: "expected") == .code("one-use-code"), "Accept matching callback")
        check(SpotifyAuthorization.callback(header: header(callback), expectedState: "wrong") == nil, "Reject CSRF state mismatch")
        check(SpotifyAuthorization.callback(header: header("/callback?code=code"), expectedState: "expected") == nil, "Reject absent state")
        check(SpotifyAuthorization.callback(header: header("/callback?state=expected&state=expected&code=x"), expectedState: "expected") == nil, "Reject duplicate state")
        check(SpotifyAuthorization.callback(header: header(callback + "&code=x"), expectedState: "expected") == nil, "Reject duplicate code")
        check(SpotifyAuthorization.callback(header: header(callback + "&error=x&error=y"), expectedState: "expected") == nil, "Reject duplicated conflicting errors")
        check(SpotifyAuthorization.callback(header: header(callback, host: "evil.example"), expectedState: "expected") == nil, "Reject DNS rebinding Host")
        check(SpotifyAuthorization.callback(header: header(callback, method: "POST"), expectedState: "expected") == nil, "GET only")
        check(SpotifyAuthorization.callback(header: header("https://evil.example" + callback), expectedState: "expected") == nil, "Reject absolute request target")
        check(SpotifyAuthorization.callback(header: header("/other?state=expected&code=x"), expectedState: "expected") == nil, "Exact callback path")
        check(SpotifyAuthorization.callback(header: header("/callback?state=expected&error=access_denied"), expectedState: "expected") == .denied, "Handle account cancellation")
        check(SpotifyAuthorization.callback(header: header("/callback?state=expected&error=access_denied&code=x"), expectedState: "expected") == nil, "Reject simultaneous code and denial")
        check(SpotifyAuthorization.callback(header: Data(repeating: 65, count: 8193), expectedState: "expected") == nil, "Bound HTTP headers")
        check(SpotifyAuthorization.callback(header: Data("GET /callback?state=expected&code=x HTTP/1.1\r\nHost: 127.0.0.1:8898".utf8), expectedState: "expected") == nil, "Wait for complete headers")

        let body = String(data: SpotifyAuthorization.formBody(["code": "a+b &c=é", "client_id": "test"]), encoding: .utf8)!
        check(body == "client_id=test&code=a%2Bb%20%26c%3D%C3%A9", "Form encoding must preserve special characters")
        let albumJSON = """
        {"id":"4aawyAB9vmqN3uQ7FjRGTy","name":"Example album","artists":[{"name":"One"},{"name":"Two"}],"images":[{"url":"https://i.scdn.co/image/large","width":640},{"url":"https://i.scdn.co/image/medium","width":300},{"url":"https://i.scdn.co/image/small","width":64}]}
        """
        let album = try JSONDecoder().decode(SpotifyAlbum.self, from: Data(albumJSON.utf8))
        check(album.artists == "One, Two" && album.uri == "spotify:album:4aawyAB9vmqN3uQ7FjRGTy", "Album mapping")
        check(album.imageURL?.lastPathComponent == "medium", "Choose bounded album art")
        check(SpotifyAuthorization.artworkURL("http://i.scdn.co/image/x") == nil, "No cleartext artwork")
        check(SpotifyAuthorization.artworkURL("https://i.scdn.co.evil.example/image/x") == nil, "No third-party artwork")
        check(SpotifyAuthorization.artworkURL("https://user:pass@i.scdn.co/image/x") == nil, "No URL credentials")
        let trackJSON = """
        {"id":"11dFghVXANMlKmJXsNCbNl","name":"Example track","artists":[{"name":"One"}],"duration_ms":123456,"track_number":2}
        """
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: Data(trackJSON.utf8))
        check(track.durationMS == 123456 && track.trackNumber == 2 && track.uri == "spotify:track:11dFghVXANMlKmJXsNCbNl", "Track mapping")
        do {
            _ = try JSONDecoder().decode(SpotifyAlbum.self, from: Data(albumJSON.replacingOccurrences(of: "4aawyAB9vmqN3uQ7FjRGTy", with: "bad-id").utf8))
            preconditionFailure("Invalid API IDs must not reach playback")
        } catch is DecodingError {}
        checkPageWindows()
        try checkLibraryFixtures(trackJSON: trackJSON)
        try await checkRefreshTransactions()
        #if SPOTIFY_KEYCHAIN_TESTING
        try await checkKeychainWorker()
        #endif
        print("Spotify PKCE, callback security, catalog decoding and refresh cancellation checks passed.")
    }

    #if SPOTIFY_KEYCHAIN_TESTING
    @MainActor
    private static func checkKeychainWorker() async throws {
        let release = DispatchSemaphore(value: 0)
        var order: [String] = [] // Worker-only access until its final barrier returns.
        await withCheckedContinuation { started in
            SpotifyKeychainWorker.enqueue({
                precondition(!Thread.isMainThread, "Keychain work must never run on the UI thread")
                started.resume()
                release.wait()
                order.append("save-old-account")
            }, completion: { _ in })
        }
        var uiTick = false
        Task { @MainActor in uiTick = true }
        while !uiTick { await Task.yield() }
        SpotifyKeychainWorker.enqueue({ order.append("disconnect-delete") }, completion: { _ in })
        release.signal()
        let recorded: [String] = try await SpotifyKeychainWorker.perform {
            precondition(!Thread.isMainThread)
            order.append("save-new-account")
            return order
        }
        precondition(recorded == ["save-old-account", "disconnect-delete", "save-new-account"], "Deletion must not be overtaken by stale credential saves")
        enum Denied: Error { case interactionNotAllowed }
        do {
            let _: Void = try await SpotifyKeychainWorker.perform { throw Denied.interactionNotAllowed }
            preconditionFailure("Denied Keychain access must return an error")
        } catch Denied.interactionNotAllowed {}
    }
    #endif

    private static func checkPageWindows() {
        let first = SpotifyPageWindow(offset: 0, pageSize: 50, receivedCount: 50, total: 12000)
        precondition(first.hasNext && !first.hasPrevious && first.previousOffset == 0 && first.nextOffset == 50)
        let deep = SpotifyPageWindow(offset: 5000, pageSize: 50, receivedCount: 50, total: 12000)
        precondition(deep.hasNext && deep.hasPrevious && deep.previousOffset == 4950 && deep.nextOffset == 5050, "Library remains accessible far beyond the old cap")
        let filtered = SpotifyPageWindow(offset: 250, pageSize: 50, receivedCount: 50, total: 333)
        precondition(filtered.nextOffset == 300, "Advance by source entries, regardless of filtered or duplicate music")
        let last = SpotifyPageWindow(offset: 300, pageSize: 50, receivedCount: 33, total: 333)
        precondition(!last.hasNext && last.hasPrevious && last.previousOffset == 250)
        let empty = SpotifyPageWindow(offset: 0, pageSize: 50, receivedCount: 0, total: 0)
        precondition(!empty.hasNext && !empty.hasPrevious)
        let removedPage = SpotifyPageWindow(offset: 50, pageSize: 50, receivedCount: 0, total: 20)
        precondition(!removedPage.hasNext && removedPage.hasPrevious && removedPage.previousOffset == 0, "Previous still works after library deletions")
        for size in [10, 20, 50] {
            let next = SpotifyPageWindow(offset: size * 15, pageSize: size, receivedCount: size, total: 100000)
            precondition(next.nextOffset == size * 16 && next.previousOffset == size * 14 && next.hasNext)
            precondition(SpotifyPageWindow.previousOffset(from: 3, pageSize: size) == 0, "Never request negative offsets")
        }
        let overflow = SpotifyPageWindow(offset: Int.max - 1, pageSize: 50, receivedCount: 50, total: Int.max)
        precondition(!overflow.hasNext && overflow.nextOffset == Int.max, "Untrusted pagination cannot overflow")
    }

    private static func checkLibraryFixtures(trackJSON: String) throws {
        let decoder = JSONDecoder()
        let playlistJSON = """
        {"id":"3cEYpjA9oz9GiPac4AsH4n","name":"My playlist","owner":{"id":"owner-id","display_name":"Owner name"},"images":[{"url":"https://mosaic.scdn.co/640/cover","width":640}]}
        """
        let playlist = try decoder.decode(SpotifyPlaylist.self, from: Data(playlistJSON.utf8))
        precondition(playlist.owner == "Owner name" && playlist.uri == "spotify:playlist:3cEYpjA9oz9GiPac4AsH4n")
        precondition(playlist.imageURL?.host == "mosaic.scdn.co", "Spotify playlist CDN accepted")
        let noName = playlistJSON.replacingOccurrences(of: "\"display_name\":\"Owner name\"", with: "\"display_name\":null")
        let fallbackOwner = try decoder.decode(SpotifyPlaylist.self, from: Data(noName.utf8))
        precondition(fallbackOwner.owner == "owner-id")
        let liked = try decoder.decode(SpotifyTrackItem.self, from: Data("{\"added_at\":\"2026-10-15T00:00:00Z\",\"track\":\(trackJSON)}".utf8))
        precondition(liked.track?.name == "Example track", "Liked-song wrapper decoded")
        let newItem = try decoder.decode(SpotifyTrackItem.self, from: Data("{\"item\":\(trackJSON)}".utf8))
        let legacyItem = try decoder.decode(SpotifyTrackItem.self, from: Data("{\"track\":\(trackJSON)}".utf8))
        precondition(newItem.track == legacyItem.track, "New item and legacy track payloads agree")
        let episode = trackJSON.dropLast() + ",\"type\":\"episode\"}"
        let local = trackJSON.dropLast() + ",\"is_local\":true}"
        let unavailable = trackJSON.dropLast() + ",\"is_playable\":false}"
        for value in ["null", "{\"item\":null}", "{\"track\":null}", "{\"item\":\(episode)}", "{\"track\":\(local)}", "{\"item\":\(unavailable)}", "{\"is_local\":true,\"item\":\(trackJSON)}"] {
            let entry = try decoder.decode(SpotifyTrackItem.self, from: Data(value.utf8))
            precondition(entry.track == nil, "Unavailable/non-music entry must be skipped")
        }
        let directPage = "{\"total\":5,\"items\":[\(trackJSON),null,\(episode),\(local),\(unavailable)]}"
        let searchPage = try decoder.decode(SpotifyTrackPage.self, from: Data(directPage.utf8))
        precondition(searchPage.items.count == 1 && searchPage.receivedCount == 5 && searchPage.total == 5, "Song search pagination advances over skipped entries")
        let wrappedPage = "[{\"track\":\(trackJSON)},{\"item\":null},null,{\"item\":\(episode)},{\"item\":\(trackJSON)}]"
        let entries = try decoder.decode([SpotifyTrackItem].self, from: Data(wrappedPage.utf8))
        precondition(entries.count == 5 && entries.compactMap(\.track).count == 2, "Mixed playlist entries retain valid music")
    }

    @MainActor
    private static func checkRefreshTransactions() async throws {
        let transaction = SpotifyRefreshTransaction<String>()
        let gate = RefreshGate()
        var operationCount = 0
        var persisted: [String] = []
        var generation = UUID()
        let initialGeneration = generation
        func refresh() async throws -> String {
            let token = try await transaction.value(operation: {
                operationCount += 1
                await gate.wait()
                return "rotated-refresh-token"
            }, isCurrent: { generation == initialGeneration }, commit: { persisted.append($0) })
            try Task.checkCancellation()
            return token
        }
        let initiator = Task { try await refresh() }
        while !gate.entered { await Task.yield() }
        var waiterEntered = false
        let waiter = Task {
            waiterEntered = true
            return try await refresh()
        }
        while !waiterEntered { await Task.yield() }
        initiator.cancel()
        gate.release()
        do {
            _ = try await initiator.value
            preconditionFailure("Cancelled initiator must abandon its request")
        } catch is CancellationError {}
        let received = try await waiter.value
        precondition(received == "rotated-refresh-token", "Concurrent waiter receives rotated token")
        precondition(operationCount == 1, "Concurrent callers share one refresh")
        precondition(persisted == ["rotated-refresh-token"], "Rotated token commits exactly once despite initiator cancellation")

        let staleGate = RefreshGate()
        let staleGeneration = generation
        let stale = Task {
            try await transaction.value(operation: {
                await staleGate.wait()
                return "stale-token"
            }, isCurrent: { generation == staleGeneration }, commit: { persisted.append($0) })
        }
        while !staleGate.entered { await Task.yield() }
        generation = UUID() // The account disconnected while refresh was in flight.
        staleGate.release()
        do {
            _ = try await stale.value
            preconditionFailure("A stale account generation must not commit")
        } catch is CancellationError {}
        precondition(persisted == ["rotated-refresh-token"], "Disconnect generation discards stale credentials")

        let cancelledGate = RefreshGate()
        let cancelled = Task {
            try await transaction.value(operation: {
                await cancelledGate.wait() // Simulates transport that completes despite cancellation.
                return "cancelled-owner-token"
            }, isCurrent: { true }, commit: { persisted.append($0) })
        }
        while !cancelledGate.entered { await Task.yield() }
        transaction.cancel()
        cancelledGate.release()
        do {
            _ = try await cancelled.value
            preconditionFailure("Explicit transaction cancellation must prevent commit")
        } catch is CancellationError {}
        precondition(persisted.count == 1, "Disconnect cancels the refresh owner without credential resurrection")
    }

}


@MainActor
private final class RefreshGate {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered = true
        }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}
