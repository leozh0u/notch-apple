import AppKit
import Combine
import Foundation
@preconcurrency import Network
import Security

/// A small catalog client. Playback stays in the user's background Spotify app.
/// Tokens never enter UserDefaults, URLs, diagnostic output, or the repository.
@MainActor
final class SpotifyLibrary: ObservableObject {
    static let shared = SpotifyLibrary()
    static let redirectURI = SpotifyAuthorization.redirectURI

    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    @Published private(set) var connectionPhase: SpotifyConnectionPhase?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var albums: [SpotifyAlbum] = []
    @Published private(set) var playlists: [SpotifyPlaylist] = []
    @Published private(set) var hasMorePlaylists = false
    @Published private(set) var tracks: [SpotifyTrack] = []
    @Published private(set) var hasMoreAlbums = false
    @Published private(set) var hasMoreTracks = false
    @Published private(set) var albumPageOffset = 0
    @Published private(set) var playlistPageOffset = 0
    @Published private(set) var trackPageOffset = 0
    @Published private(set) var hasPreviousAlbums = false
    @Published private(set) var hasPreviousPlaylists = false
    @Published private(set) var hasPreviousTracks = false

    @Published private(set) var playbackDevices: [SpotifyPlaybackDevice] = []
    @Published var preferredPlaybackDeviceID = UserDefaults.standard.string(forKey: "spotifyPlaybackDeviceID") ?? "" {
        didSet { UserDefaults.standard.set(preferredPlaybackDeviceID, forKey: "spotifyPlaybackDeviceID") }
    }
    var playbackAccountID: UUID { accountGeneration }
    var hasPlaybackAccess: Bool { SpotifyAuthorization.hasPlaybackScopes(credentials?.scope) }

    // Raw source ranges include unavailable entries that the UI omits.
    var albumPageEndOffset: Int { nextAlbumOffset }
    var playlistPageEndOffset: Int { nextPlaylistOffset }
    var trackPageEndOffset: Int { nextTrackOffset }

    var clientID: String {
        get { UserDefaults.standard.string(forKey: "spotifyLibraryClientID") ?? "" }
        set {
            let value = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value != clientID else { return }
            disconnect()
            UserDefaults.standard.set(value, forKey: "spotifyLibraryClientID")
            objectWillChange.send()
        }
    }

    private var credentials: SpotifyCredentials?
    private var callbackServer: SpotifyCallbackServer?
    private var connectionTask: Task<Void, Never>?
    private var connectionTimeoutTask: Task<Void, Never>?
    private var pendingAuthorizationURL: URL?
    private let refreshTransaction = SpotifyRefreshTransaction<SpotifyCredentials>()
    private var accountGeneration = UUID()
    private var latestLoad = UUID()
    private var lastAlbumQuery: String?
    private var nextAlbumOffset = 0
    private var nextTrackOffset = 0
    private var nextPlaylistOffset = 0
    private enum TrackSource: Equatable { case album(String), liked, playlist(String), search(String) }
    private var trackSource: TrackSource?
    private var cooldownUntil: Date?
    private var session: URLSession

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration, delegate: SpotifyNoRedirectDelegate(), delegateQueue: nil)
    }

    private init() {
        session = Self.makeSession()
        #if !SPOTIFY_KEYCHAIN_TESTING
        let generation = accountGeneration
        // Keychain ACL checks may involve securityd; never perform them on the UI thread.
        Task { [weak self] in
            do {
                let stored = try await SpotifyCredentialStore.read()
                guard let self, self.accountGeneration == generation else { return }
                if stored?.clientID == self.clientID, stored?.refreshToken.isEmpty == false,
                   SpotifyAuthorization.hasRequiredScopes(stored?.scope) {
                    self.credentials = stored
                    self.isConnected = true
                    await self.loadSavedAlbums()
                } else if stored != nil {
                    self.errorMessage = "Reconnect Spotify to access Liked Songs and playlists."
                }
            } catch {
                guard let self, self.accountGeneration == generation else { return }
                self.errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    func connect() {
        guard !isConnecting else { return }
        guard SpotifyAuthorization.isValidClientID(clientID) else {
            errorMessage = "Enter the Client ID from your Spotify developer app first."
            return
        }
        errorMessage = nil
        isConnecting = true
        let generation = UUID()
        accountGeneration = generation
        setConnectionPhase(.browser)
        let selectedClientID = clientID
        do {
            let state = try SpotifyAuthorization.randomURLSafeString()
            let verifier = try SpotifyAuthorization.randomURLSafeString()
            guard let url = SpotifyAuthorization.authorizationURL(clientID: selectedClientID, state: state, verifier: verifier) else {
                throw SpotifyLibraryError.message("The Spotify Client ID is invalid.")
            }
            pendingAuthorizationURL = url
            let server = try SpotifyCallbackServer(expectedState: state)
            callbackServer = server
            server.start(onReady: { [weak self] in
                guard let self, self.accountGeneration == generation, self.isConnecting else { return }
                if !NSWorkspace.shared.open(url) {
                    self.finishConnecting(error: "Could not open your browser for Spotify. Try again.")
                }
            }, completion: { [weak self] result in
                guard let self, self.accountGeneration == generation, self.isConnecting else { return }
                self.callbackServer?.cancel()
                self.callbackServer = nil
                switch result {
                case .failure(let error): self.finishConnecting(error: error.localizedDescription)
                case .success(.denied): self.finishConnecting(error: "Spotify connection cancelled. You can connect whenever you're ready.")
                case .success(.code(let code)):
                    self.pendingAuthorizationURL = nil
                    self.setConnectionPhase(.token)
                    self.connectionTask = Task { [weak self] in
                        guard let self else { return }
                        do {
                            let token = try await self.exchangeToken([
                                "grant_type": "authorization_code", "code": code,
                                "redirect_uri": Self.redirectURI, "client_id": selectedClientID,
                                "code_verifier": verifier
                            ], clientID: selectedClientID, previousRefreshToken: nil)
                            try Task.checkCancellation()
                            guard self.accountGeneration == generation, self.isConnecting else { return }
                            self.setConnectionPhase(.keychain)
                            try await self.persist(token, generation: generation, allowReplacingDeniedItem: true)
                            self.credentials = token
                            self.isConnected = true
                            self.finishConnecting(error: nil)
                            await self.loadSavedAlbums()
                        } catch is CancellationError {} catch {
                            guard self.accountGeneration == generation, self.isConnecting else { return }
                            self.finishConnecting(error: error.localizedDescription)
                        }
                    }
                }
            })
        } catch { finishConnecting(error: "Could not start Spotify sign-in. Port 8898 may be busy; close another sign-in attempt and retry.") }
    }

    func resumeSignIn() {
        guard isConnecting, connectionPhase == .browser, let url = pendingAuthorizationURL else { return }
        if !NSWorkspace.shared.open(url) {
            cancelConnection(error: "Could not open your browser for Spotify. Try connecting again.")
        }
    }

    func cancelConnection() { cancelConnection(error: nil) }

    private func cancelConnection(error: String?) {
        guard isConnecting else { return }
        accountGeneration = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        refreshTransaction.cancel()
        finishConnecting(error: error)
        // Cancelling sign-in must not disconnect an existing account or delete its Keychain item.
    }

    private func setConnectionPhase(_ phase: SpotifyConnectionPhase, timeout: TimeInterval? = nil) {
        connectionTimeoutTask?.cancel()
        connectionPhase = phase
        let generation = accountGeneration
        let deadline = Date().addingTimeInterval(timeout ?? phase.timeout)
        connectionTimeoutTask = Task { [weak self] in
            // Recheck wall time after sleep/wake; never leave a stale sign-in spinner.
            while Date() < deadline {
                let remaining = min(1, deadline.timeIntervalSinceNow)
                guard remaining > 0 else { break }
                do { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) } catch { return }
            }
            guard !Task.isCancelled, let self, self.accountGeneration == generation,
                  self.isConnecting, self.connectionPhase == phase else { return }
            self.cancelConnection(error: phase.timeoutMessage)
        }
    }

    #if SPOTIFY_KEYCHAIN_TESTING
    static func connectedForTesting() -> SpotifyLibrary {
        let library = SpotifyLibrary()
        library.isConnected = true
        return library
    }
    func beginConnectionForTesting(_ phase: SpotifyConnectionPhase, timeout: TimeInterval) {
        isConnecting = true
        setConnectionPhase(phase, timeout: timeout)
    }
    #endif

    func disconnect() {
        cancelConnection()
        accountGeneration = UUID()
        latestLoad = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        refreshTransaction.cancel()
        callbackServer?.cancel()
        callbackServer = nil
        session.invalidateAndCancel()
        session = Self.makeSession()
        credentials = nil
        playbackDevices = []
        preferredPlaybackDeviceID = ""
        albums = []
        tracks = []
        playlists = []
        hasMorePlaylists = false
        hasMoreAlbums = false
        hasMoreTracks = false
        trackSource = nil
        albumPageOffset = 0
        playlistPageOffset = 0
        trackPageOffset = 0
        hasPreviousAlbums = false
        hasPreviousPlaylists = false
        hasPreviousTracks = false
        isConnected = false
        isConnecting = false
        isLoading = false
        cooldownUntil = nil
        errorMessage = nil
        let generation = accountGeneration
        SpotifyCredentialStore.delete { [weak self] result in
            Task { @MainActor in
                guard let self, self.accountGeneration == generation else { return }
                if case .failure(let error) = result { self.errorMessage = error.localizedDescription }
            }
        }
    }

    func loadSavedAlbums() async {
        lastAlbumQuery = nil
        await loadAlbums(query: nil, offset: 0)
    }

    func searchAlbums(query: String) async {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { await loadSavedAlbums(); return }
        lastAlbumQuery = query
        await loadAlbums(query: query, offset: 0)
    }

    func loadMoreAlbums() async {
        guard hasMoreAlbums, !isLoading else { return }
        await loadAlbums(query: lastAlbumQuery, offset: nextAlbumOffset)
    }

    func loadPreviousAlbums() async {
        guard hasPreviousAlbums, !isLoading else { return }
        let size = lastAlbumQuery == nil ? 20 : 10
        await loadAlbums(query: lastAlbumQuery, offset: SpotifyPageWindow.previousOffset(from: albumPageOffset, pageSize: size))
    }

    private func loadAlbums(query: String?, offset: Int) async {
        let loadID = beginLoad()
        let generation = accountGeneration
        defer { endLoad(loadID) }
        do {
            let pageSize = query == nil ? 20 : 10
            let result: [SpotifyAlbum]
            let total: Int
            if let query {
                let response: SpotifySearchPage = try await api(path: "/v1/search", query: [
                    URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "album"),
                    URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "offset", value: String(offset))])
                result = response.albums.items
                total = response.albums.total
            } else {
                let response: SpotifyPage<SpotifySavedAlbum> = try await api(path: "/v1/me/albums", query: [
                    URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: String(offset))])
                result = response.items.map(\.album)
                total = response.total
            }
            guard latestLoad == loadID, accountGeneration == generation else { return }
            let window = SpotifyPageWindow(offset: offset, pageSize: pageSize, receivedCount: result.count, total: total)
            albums = Self.uniqued(Array(result.prefix(pageSize)))
            albumPageOffset = window.offset
            hasPreviousAlbums = window.hasPrevious
            nextAlbumOffset = window.nextOffset
            hasMoreAlbums = window.hasNext
        } catch { show(error, loadID: loadID, generation: generation) }
    }

    func loadPlaylists() async { await loadPlaylists(offset: 0) }

    func loadMorePlaylists() async {
        guard hasMorePlaylists, !isLoading else { return }
        await loadPlaylists(offset: nextPlaylistOffset)
    }

    func loadPreviousPlaylists() async {
        guard hasPreviousPlaylists, !isLoading else { return }
        await loadPlaylists(offset: SpotifyPageWindow.previousOffset(from: playlistPageOffset, pageSize: 20))
    }

    private func loadPlaylists(offset: Int) async {
        let loadID = beginLoad()
        let generation = accountGeneration
        defer { endLoad(loadID) }
        do {
            let page: SpotifyPage<SpotifyOptionalItem<SpotifyPlaylist>> = try await api(path: "/v1/me/playlists", query: [
                URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "offset", value: String(offset))])
            guard latestLoad == loadID, accountGeneration == generation else { return }
            let available = page.items.compactMap(\.value)
            let window = SpotifyPageWindow(offset: offset, pageSize: 20, receivedCount: page.items.count, total: page.total)
            playlists = Self.uniqued(Array(available.prefix(20)))
            playlistPageOffset = window.offset
            hasPreviousPlaylists = window.hasPrevious
            nextPlaylistOffset = window.nextOffset
            hasMorePlaylists = window.hasNext
        } catch { show(error, loadID: loadID, generation: generation) }
    }

    func loadTracks(album: SpotifyAlbum) async { await selectTracks(.album(album.id)) }
    func loadLikedTracks() async { await selectTracks(.liked) }
    func loadPlaylistTracks(playlist: SpotifyPlaylist) async { await selectTracks(.playlist(playlist.id)) }
    func searchSongs(query: String) async {
        let query = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard !query.isEmpty else { await loadLikedTracks(); return }
        await selectTracks(.search(query))
    }

    private func selectTracks(_ source: TrackSource) async {
        trackSource = source
        tracks = []
        hasMoreTracks = false
        hasPreviousTracks = false
        trackPageOffset = 0
        await loadTracks(source: source, offset: 0)
    }

    func loadMoreTracks() async {
        guard hasMoreTracks, !isLoading, let source = trackSource else { return }
        await loadTracks(source: source, offset: nextTrackOffset)
    }

    func loadPreviousTracks() async {
        guard hasPreviousTracks, !isLoading, let source = trackSource else { return }
        let size: Int
        if case .search = source { size = 10 } else { size = 50 }
        await loadTracks(source: source, offset: SpotifyPageWindow.previousOffset(from: trackPageOffset, pageSize: size))
    }

    private func loadTracks(source: TrackSource, offset: Int) async {
        let loadID = beginLoad()
        let generation = accountGeneration
        defer { endLoad(loadID) }
        do {
            let pageSize: Int
            if case .search = source { pageSize = 10 } else { pageSize = 50 }
            let path: String
            var query = [URLQueryItem(name: "limit", value: "50"), URLQueryItem(name: "offset", value: String(offset))]
            switch source {
            case .album(let id):
                guard SpotifyAuthorization.isValidID(id) else { return }
                path = "/v1/albums/\(id)/tracks"
            case .liked: path = "/v1/me/tracks"
            case .playlist(let id):
                guard SpotifyAuthorization.isValidID(id) else { return }
                path = "/v1/playlists/\(id)/items"
            case .search(let term):
                path = "/v1/search"
                query = [URLQueryItem(name: "q", value: term), URLQueryItem(name: "type", value: "track"),
                         URLQueryItem(name: "limit", value: "10"), URLQueryItem(name: "offset", value: String(offset))]
            }
            let result: [SpotifyTrack]
            let total: Int
            let receivedCount: Int
            switch source {
            case .liked, .playlist:
                let page: SpotifyPage<SpotifyTrackItem> = try await api(path: path, query: query)
                result = page.items.compactMap(\.track)
                receivedCount = page.items.count
                total = page.total
            case .album:
                let page: SpotifyTrackPage = try await api(path: path, query: query)
                result = page.items
                receivedCount = page.receivedCount
                total = page.total
            case .search:
                let page: SpotifySongSearchPage = try await api(path: path, query: query)
                result = page.tracks.items
                receivedCount = page.tracks.receivedCount
                total = page.tracks.total
            }
            guard latestLoad == loadID, accountGeneration == generation, trackSource == source else { return }
            let window = SpotifyPageWindow(offset: offset, pageSize: pageSize, receivedCount: receivedCount, total: total)
            tracks = Self.uniqued(Array(result.prefix(pageSize)))
            trackPageOffset = window.offset
            hasPreviousTracks = window.hasPrevious
            nextTrackOffset = window.nextOffset
            hasMoreTracks = window.hasNext
        } catch { show(error, loadID: loadID, generation: generation) }
    }

    private static func uniqued<T: Identifiable>(_ values: [T]) -> [T] where T.ID: Hashable {
        var ids: Set<T.ID> = []
        return values.filter { ids.insert($0.id).inserted }
    }

    private func beginLoad() -> UUID {
        let id = UUID()
        latestLoad = id
        errorMessage = nil
        isLoading = true
        return id
    }
    private func endLoad(_ id: UUID) { if latestLoad == id { isLoading = false } }
    private func show(_ error: Error, loadID: UUID, generation: UUID) {
        guard latestLoad == loadID, accountGeneration == generation, !(error is CancellationError),
              (error as? URLError)?.code != .cancelled else { return }
        errorMessage = error is URLError ? "Spotify could not be reached. Check your connection and try again." : error.localizedDescription
    }
    private func finishConnecting(error: String?) {
        connectionTimeoutTask?.cancel()
        connectionTimeoutTask = nil
        pendingAuthorizationURL = nil
        connectionPhase = nil
        callbackServer?.cancel()
        callbackServer = nil
        isConnecting = false
        errorMessage = error
    }

    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = credentials, current.clientID == clientID else {
            throw SpotifyLibraryError.message("Connect Spotify to browse your library.")
        }
        if !forceRefresh && current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        let generation = accountGeneration
        let refreshed = try await refreshTransaction.value(operation: { [weak self] in
            guard let self else { throw CancellationError() }
            let refreshed = try await self.exchangeToken([
                "grant_type": "refresh_token", "refresh_token": current.refreshToken,
                "client_id": current.clientID
            ], clientID: current.clientID, previousRefreshToken: current.refreshToken, previousScope: current.scope)
            try await self.persist(refreshed, generation: generation)
            return refreshed
        }, isCurrent: { [weak self] in
            self?.accountGeneration == generation
        }, commit: { [weak self] refreshed in
            guard let self else { throw CancellationError() }
            self.credentials = refreshed
        })
        // Each caller may abandon its API request after the shared transaction commits.
        try Task.checkCancellation()
        guard accountGeneration == generation else { throw CancellationError() }
        return refreshed.accessToken
    }

    private func persist(_ token: SpotifyCredentials, generation: UUID, allowReplacingDeniedItem: Bool = false) async throws {
        guard accountGeneration == generation else { throw CancellationError() }
        try await SpotifyCredentialStore.save(token, allowReplacingDeniedItem: allowReplacingDeniedItem)
        // Disconnect's deletion is queued after any already-started save. It cannot
        // be overtaken by that save, and an old account never returns to UI state.
        guard accountGeneration == generation else { throw CancellationError() }
    }

    private func exchangeToken(_ form: [String: String], clientID: String, previousRefreshToken: String?, previousScope: String? = nil) async throws -> SpotifyCredentials {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = SpotifyAuthorization.formBody(form)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpotifyLibraryError.message("Spotify returned an unreadable response.") }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw rateLimitError(http) }
            if http.statusCode == 400 || http.statusCode == 401 {
                throw SpotifyLibraryError.message("Spotify sign-in expired or the app's Client ID/redirect URI does not match. Reconnect Spotify.")
            }
            throw SpotifyLibraryError.message("Spotify sign-in is unavailable. Try again later.")
        }
        let token = try JSONDecoder().decode(SpotifyTokenResponse.self, from: data)
        guard token.token_type.lowercased() == "bearer", !token.access_token.isEmpty,
              token.expires_in > 0, let refresh = token.refresh_token ?? previousRefreshToken, !refresh.isEmpty else {
            throw SpotifyLibraryError.message("Spotify did not return a usable sign-in. Reconnect Spotify.")
        }
        let scope = token.scope ?? previousScope ?? SpotifyAuthorization.scope
        guard SpotifyAuthorization.hasRequiredScopes(scope) else {
            throw SpotifyLibraryError.message("Reconnect Spotify and allow library and playlist access.")
        }
        return SpotifyCredentials(clientID: clientID, accessToken: token.access_token, refreshToken: refresh,
                                  expiresAt: Date().addingTimeInterval(TimeInterval(token.expires_in)), scope: scope)
    }

    func refreshPlaybackDevices() async {
        let generation = accountGeneration
        do { try await fetchPlaybackDevices() }
        catch {
            guard accountGeneration == generation, !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func fetchPlaybackDevices() async throws {
        guard hasPlaybackAccess else {
            throw SpotifyLibraryError.message("Enable background playback in Settings → Media to play without opening Spotify.")
        }
        let generation = accountGeneration
        let response: SpotifyDevicesResponse = try await api(path: "/v1/me/player/devices", query: [])
        try Task.checkCancellation()
        guard accountGeneration == generation else { throw CancellationError() }
        playbackDevices = response.devices.filter(\.isUsableComputer)
    }

    func playOnThisMac(_ request: SpotifyPlaybackRequest) async throws {
        let generation = accountGeneration
        let names = [Host.current().localizedName, Host.current().name, ProcessInfo.processInfo.hostName].compactMap { $0 }
        for attempt in 0..<4 {
            try Task.checkCancellation()
            guard accountGeneration == generation else { throw CancellationError() }
            try await fetchPlaybackDevices()
            try Task.checkCancellation()
            guard accountGeneration == generation else { throw CancellationError() }
            if let device = SpotifyPlaybackDevice.thisMac(in: playbackDevices, preferredID: preferredPlaybackDeviceID, hostNames: names),
               let id = device.id {
                _ = try await authorizedRequest(path: "/v1/me/player/play", query: [URLQueryItem(name: "device_id", value: id)],
                                                method: "PUT", body: try request.playbackBody)
                return
            }
            // A freshly launched client may take a moment to register with Connect.
            if !playbackDevices.isEmpty || attempt == 3 { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw SpotifyLibraryError.message("Choose this Mac under Settings → Media → Playback device, then try again.")
    }

    private func api<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        let data = try await authorizedRequest(path: path, query: query)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func authorizedRequest(path: String, query: [URLQueryItem] = [], method: String = "GET",
                                   body: Data? = nil, retried: Bool = false) async throws -> Data {
        if let cooldownUntil, cooldownUntil > Date() {
            throw SpotifyLibraryError.message("Spotify is limiting requests. Try again in \(Int(ceil(cooldownUntil.timeIntervalSinceNow))) seconds.")
        }
        let generation = accountGeneration
        let token = try await accessToken(forceRefresh: retried)
        guard accountGeneration == generation else { throw CancellationError() }
        var components = URLComponents(string: "https://api.spotify.com")!
        components.path = path
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard accountGeneration == generation else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw SpotifyLibraryError.message("Spotify returned an unreadable response.") }
        if http.statusCode == 401 && !retried { return try await authorizedRequest(path: path, query: query, method: method, body: body, retried: true) }
        guard http.statusCode == (method == "GET" ? 200 : 204) else {
            if http.statusCode == 429 { throw rateLimitError(http) }
            if http.statusCode == 401 { throw SpotifyLibraryError.message("Spotify authorization expired. Disconnect and connect again.") }
            if path.hasPrefix("/v1/me/player") {
                if http.statusCode == 404 { throw SpotifyLibraryError.message("Spotify on this Mac is not ready yet. Try playing again.") }
                if http.statusCode == 403 { throw SpotifyLibraryError.message("Background playback needs Spotify Premium and playback permission. Reconnect in Settings → Media.") }
            }
            if http.statusCode == 403 {
                if path.hasPrefix("/v1/playlists/") {
                    throw SpotifyLibraryError.message("Spotify only allows browsing tracks in playlists you own or collaborate on.")
                }
                throw SpotifyLibraryError.message("Spotify denied this request. Reconnect to allow library access, and check that your account is allowed in the developer app.")
            }
            throw SpotifyLibraryError.message("Spotify could not load your Spotify library. Try again later.")
        }
        guard data.count <= 2_000_000 else { throw SpotifyLibraryError.message("Spotify returned too much data. Try a narrower search.") }
        return data
    }

    private func rateLimitError(_ response: HTTPURLResponse) -> SpotifyLibraryError {
        let delay = max(1, min(86400, Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 30))
        cooldownUntil = Date().addingTimeInterval(delay)
        return .message("Spotify is limiting requests. Try again in \(Int(ceil(delay))) seconds.")
    }
}

private struct SpotifyDevicesResponse: Decodable { let devices: [SpotifyPlaybackDevice] }
private struct SpotifyPage<Item: Decodable>: Decodable { let items: [Item]; let total: Int }
private struct SpotifySavedAlbum: Decodable { let album: SpotifyAlbum }
private struct SpotifySearchPage: Decodable { let albums: SpotifyPage<SpotifyAlbum> }
private struct SpotifySongSearchPage: Decodable { let tracks: SpotifyTrackPage }
private struct SpotifyTokenResponse: Decodable {
    let scope: String?
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
}
private struct SpotifyCredentials: Codable {
    let clientID: String
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let scope: String?
}

/// Serializes Keychain transactions off the main actor, including disconnect deletion.
/// No operation permits SecurityAgent to display an access prompt.
enum SpotifyKeychainWorker {
    private static let queue = DispatchQueue(label: "com.leozhou.notchapple.spotify-keychain", qos: .utility)
    static func perform<Value>(_ operation: @escaping () throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(operation) { continuation.resume(with: $0) }
        }
    }
    static func enqueue<Value>(_ operation: @escaping () throws -> Value,
                               completion: @escaping (Result<Value, Error>) -> Void) {
        queue.async { completion(Result { try operation() }) }
    }
}

private enum SpotifyCredentialStore {
    private static let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.leozhou.notchapple.spotify",
        kSecAttrAccount as String: "library-oauth",
        kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
    ]
    static func read() async throws -> SpotifyCredentials? {
        try await SpotifyKeychainWorker.perform {
            var query = identity
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            guard status == errSecSuccess, let data = item as? Data else { throw keychainError(status) }
            return try JSONDecoder().decode(SpotifyCredentials.self, from: data)
        }
    }
    static func save(_ credentials: SpotifyCredentials, allowReplacingDeniedItem: Bool) async throws {
        try await SpotifyKeychainWorker.perform {
            let data = try JSONEncoder().encode(credentials)
            let updates = [kSecValueData as String: data]
            let status = SecItemUpdate(identity as CFDictionary, updates as CFDictionary)
            var shouldAdd = status == errSecItemNotFound
            if allowReplacingDeniedItem && (status == errSecInteractionNotAllowed || status == errSecAuthFailed) {
                // Only an explicit, successful fresh OAuth grant can replace this
                // app's inaccessible old item. Refresh never deletes credentials.
                let deleted = SecItemDelete(identity as CFDictionary)
                guard deleted == errSecSuccess || deleted == errSecItemNotFound else { throw keychainError(deleted) }
                shouldAdd = true
            } else if status != errSecSuccess && !shouldAdd { throw keychainError(status) }
            if shouldAdd {
                var item = identity
                item[kSecValueData as String] = data
                item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
                let added = SecItemAdd(item as CFDictionary, nil)
                guard added == errSecSuccess else { throw keychainError(added) }
            }
        }
    }
    static func delete(completion: @escaping (Result<Void, Error>) -> Void) {
        SpotifyKeychainWorker.enqueue({
            let status = SecItemDelete(identity as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw keychainError(status) }
        }, completion: completion)
    }
    private static func keychainError(_ status: OSStatus) -> SpotifyLibraryError {
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return .message("macOS blocked this build's saved Spotify sign-in. In Keychain Access, remove the com.leozhou.notchapple.spotify item, then reconnect Spotify.")
        }
        return .message("Spotify credentials are unavailable in Keychain. Unlock your Mac and reconnect Spotify.")
    }
}

private final class SpotifyNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Never forward a token to a redirect target, including a different Spotify host.
        completionHandler(nil)
    }
}

@MainActor
private final class SpotifyCallbackServer {
    private let listener: NWListener
    private let expectedState: String
    private var completion: ((Result<SpotifyAuthorization.Callback, Error>) -> Void)?
    private var connections: [UUID: NWConnection] = [:]
    private var finished = false

    init(expectedState: String) throws {
        self.expectedState = expectedState
        let parameters = NWParameters.tcp
        // Explicit loopback binding: no listener on the LAN or all interfaces.
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 8898)
        listener = try NWListener(using: parameters)
    }

    func start(onReady: @escaping () -> Void, completion: @escaping (Result<SpotifyAuthorization.Callback, Error>) -> Void) {
        self.completion = completion
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self, !self.finished else { return }
                switch state {
                case .ready: onReady()
                case .failed: self.finish(.failure(SpotifyLibraryError.message("Spotify sign-in could not listen locally. Close another sign-in attempt and retry.")))
                default: break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
    }

    func cancel() {
        finished = true
        listener.cancel()
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        completion = nil
    }

    private func accept(_ connection: NWConnection) {
        guard !finished, connections.count < 4 else { connection.cancel(); return }
        let id = UUID()
        connections[id] = connection
        connection.start(queue: .main)
        receive(connection, id: id, buffer: Data())
    }

    private func receive(_ connection: NWConnection, id: UUID, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: SpotifyAuthorization.maximumHeaderBytes - buffer.count + 1) {
            [weak self] data, _, done, error in
            Task { @MainActor in
                guard let self, !self.finished, self.connections[id] != nil else { return }
                var header = buffer
                if let data { header.append(data) }
                if header.count > SpotifyAuthorization.maximumHeaderBytes {
                    self.respond(connection, id: id, success: false, result: nil)
                } else if header.range(of: Data("\r\n\r\n".utf8)) != nil {
                    let result = SpotifyAuthorization.callback(header: header, expectedState: self.expectedState)
                    self.respond(connection, id: id, success: result != nil, result: result)
                } else if done || error != nil {
                    connection.cancel()
                    self.connections[id] = nil
                } else {
                    self.receive(connection, id: id, buffer: header)
                }
            }
        }
    }

    private func respond(_ connection: NWConnection, id: UUID, success: Bool, result: SpotifyAuthorization.Callback?) {
        let body = success ? "Spotify sign-in received. You can close this tab and return to Notch Apple." : "This sign-in request was not accepted. Return to Notch Apple and try connecting again."
        let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nX-Content-Type-Options: nosniff\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            Task { @MainActor in
                connection.cancel()
                guard let self else { return }
                self.connections[id] = nil
                if let result { self.finish(.success(result)) }
            }
        })
    }

    private func finish(_ result: Result<SpotifyAuthorization.Callback, Error>) {
        guard !finished else { return }
        let callback = completion
        cancel()
        callback?(result)
    }
}
