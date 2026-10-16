import SwiftUI

struct SpotifyBrowserView: View {
    private enum LibrarySection: String, CaseIterable {
        case albums = "Albums", liked = "Liked Songs", playlists = "Playlists"
    }
    private enum SearchKind: String, CaseIterable { case songs = "Songs", albums = "Albums" }

    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var library = SpotifyLibrary.shared
    @ObservedObject private var music = MusicManager.shared
    @State private var section: LibrarySection = .albums
    @State private var searchKind: SearchKind = .songs
    @State private var query = ""
    @State private var submittedQuery: String?
    @State private var selectedAlbum: SpotifyAlbum?
    @State private var selectedPlaylist: SpotifyPlaylist?
    @State private var request: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var isNavigating = false
    @State private var searchFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            toolbar
            if library.isConnected { navigation }
            if let error = music.appLaunchError {
                Text(error).font(.caption).lineLimit(2).foregroundStyle(.secondary)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if library.isConnected { pagination }
        }
        .buttonStyle(.plain)
        .onChange(of: searchFocused) { _, focused in
            vm.isSpotifySearchFocused = focused
            if !focused { searchTask?.cancel() }
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .onExitCommand {
            if searchFocused { searchFocused = false }
            else if selectedAlbum != nil || selectedPlaylist != nil || submittedQuery != nil { goBack() }
            else { dismiss() }
        }
        .onDisappear {
            request?.cancel()
            searchTask?.cancel()
            searchFocused = false
            vm.isSpotifySearchFocused = false
        }
        .task {
            if library.isConnected { refresh() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button(action: goBack) {
                HStack(spacing: 4) {
                    if selectedAlbum != nil || selectedPlaylist != nil || submittedQuery != nil {
                        Image(systemName: "chevron.left")
                    } else {
                        AppIcon(for: "com.spotify.client").resizable().frame(width: 14, height: 14)
                    }
                    Text("Spotify")
                }
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 64, alignment: .leading)
            }
            .disabled(!library.isConnected)
            .help("Back to Spotify library")
            .accessibilityLabel("Back to Spotify library")

            if library.isConnected {
                SpotifySearchField(text: $query, isFocused: $searchFocused,
                                   onSubmit: submitSearch, onFocusLost: endSearchAfterLosingFocus)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(height: 23)
                    .layoutPriority(1)
                Picker("Search for", selection: $searchKind) {
                    ForEach(SearchKind.allCases, id: \.self) { kind in Text(kind.rawValue).tag(kind) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 104)
                .fixedSize(horizontal: true, vertical: false)
                .onChange(of: searchKind) { _, _ in
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || submittedQuery != nil {
                        performSearch(endEditing: false)
                    }
                }
            } else {
                Spacer()
            }

            if library.isLoading {
                ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                    .accessibilityLabel("Loading Spotify")
            }
            Button(action: music.togglePlay) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 24, height: 24)
            }
            .help(music.isPlaying ? "Pause music" : "Play music")
            .accessibilityLabel(music.isPlaying ? "Pause music" : "Play music")
            Button(action: dismiss) {
                Label("Now Playing", systemImage: "waveform")
                    .font(.system(size: 10, weight: .medium)).fixedSize()
            }
            .help("Return to player")
            .accessibilityLabel("Return to Now Playing")
        }
        .frame(height: 26)
    }

    private var navigation: some View {
        HStack(spacing: 16) {
            ForEach(LibrarySection.allCases, id: \.self) { item in
                Button {
                    section = item
                    query = ""
                    submittedQuery = nil
                    selectedAlbum = nil
                    selectedPlaylist = nil
                    searchFocused = false
                    refresh()
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(section == item && submittedQuery == nil ? Color.primary : Color.secondary)
                        .padding(.vertical, 3)
                        .overlay(alignment: .bottom) {
                            if section == item && submittedQuery == nil {
                                Rectangle().fill(Color.effectiveAccent).frame(height: 1)
                            }
                        }
                }
                .accessibilityAddTraits(section == item && submittedQuery == nil ? .isSelected : [])
            }
            Spacer()
            if let submittedQuery {
                Text("Results for “\(submittedQuery)”").font(.system(size: 10))
                    .foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var content: some View {
        if !library.isConnected {
            connectionState
        } else if isNavigating || (library.isLoading && !hasContent) {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading Spotify")
        } else if let error = library.errorMessage {
            VStack(spacing: 6) {
                Text(error).font(.caption).lineLimit(3).multilineTextAlignment(.center)
                Button("Try again", action: refresh)
            }
        } else if let album = selectedAlbum {
            detail(name: album.name, subtitle: album.artists, imageURL: album.imageURL,
                   uri: album.uri, sourceURL: sourceURL(kind: "album", id: album.id))
        } else if let playlist = selectedPlaylist {
            detail(name: playlist.name, subtitle: playlist.owner, imageURL: playlist.imageURL,
                   uri: playlist.uri, sourceURL: sourceURL(kind: "playlist", id: playlist.id))
        } else if showsTracks {
            trackList(context: nil)
        } else if submittedQuery != nil || section == .albums {
            albumLibrary
        } else {
            playlistLibrary
        }
    }

    private var showsTracks: Bool {
        selectedAlbum != nil || selectedPlaylist != nil || (submittedQuery != nil ? searchKind == .songs : section == .liked)
    }
    private var hasContent: Bool {
        showsTracks ? !library.tracks.isEmpty : (submittedQuery != nil || section == .albums ? !library.albums.isEmpty : !library.playlists.isEmpty)
    }

    private var connectionState: some View {
        VStack(spacing: 8) {
            Text(library.connectionPhase?.title ?? "Connect your Spotify library")
                .font(.system(size: 13, weight: .medium))
            if library.connectionPhase == .browser {
                Text("Finish signing in to Spotify in your browser, then choose Agree.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let error = library.errorMessage {
                Text(error).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            HStack {
                if library.isConnecting {
                    ProgressView().controlSize(.small)
                    if library.connectionPhase == .browser {
                        Button("Continue in browser", action: library.resumeSignIn)
                            .buttonStyle(.borderedProminent).tint(.effectiveAccent)
                    }
                    Button("Cancel", action: library.cancelConnection)
                } else if !library.clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Connect Spotify", action: library.connect)
                        .buttonStyle(.borderedProminent).tint(.effectiveAccent)
                } else {
                    Button("Set up Spotify") {
                        NotificationCenter.default.post(name: .init("notchAppleShowMediaSettings"), object: nil)
                        SettingsWindowController.shared.showWindow()
                    }
                    .buttonStyle(.borderedProminent).tint(.effectiveAccent)
                }
            }
        }
    }

    private var albumLibrary: some View {
        Group {
            if library.albums.isEmpty {
                emptyState(submittedQuery == nil ? "No saved albums yet" : "No albums found", hint: "Search for an album above.")
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(library.albums, id: \.id) { album in
                            Button {
                                selectedAlbum = album
                                selectedPlaylist = nil
                                searchFocused = false
                                run { await library.loadTracks(album: album) }
                            } label: {
                                artworkTile(name: album.name, subtitle: album.artists, url: album.imageURL)
                            }
                            .help("\(album.name) — \(album.artists), on Spotify")
                            .accessibilityLabel("Show tracks on \(album.name), by \(album.artists)")
                        }
                    }
                }
                .id(library.albumPageOffset)
                .scrollIndicators(.automatic).disabled(library.isLoading)
            }
        }
    }

    private var playlistLibrary: some View {
        Group {
            if library.playlists.isEmpty {
                emptyState("No playlists found", hint: nil)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(library.playlists, id: \.id) { playlist in
                            Button {
                                selectedPlaylist = playlist
                                selectedAlbum = nil
                                searchFocused = false
                                run { await library.loadPlaylistTracks(playlist: playlist) }
                            } label: {
                                artworkTile(name: playlist.name, subtitle: playlist.owner, url: playlist.imageURL)
                            }
                            .help("\(playlist.name), on Spotify")
                            .accessibilityLabel("Show tracks in \(playlist.name), by \(playlist.owner)")
                        }
                    }
                }
                .id(library.playlistPageOffset)
                .scrollIndicators(.automatic).disabled(library.isLoading)
            }
        }
    }

    private func artworkTile(name: String, subtitle: String, url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SpotifyAlbumArtwork(url: url).frame(width: 66, height: 66)
            Text(name).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 82, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func detail(name: String, subtitle: String, imageURL: URL?, uri: String, sourceURL: URL?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 8) {
                    SpotifyAlbumArtwork(url: imageURL).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name).font(.system(size: 12, weight: .semibold)).lineLimit(2).help("\(name) on Spotify")
                        Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                HStack(spacing: 8) {
                    Button { music.playSpotifyURI(uri) } label: {
                        Label("Play all", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.vertical, 5).padding(.horizontal, 9)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .help("Play \(name) in the background")
                    if let sourceURL {
                        Link(destination: sourceURL) {
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .medium))
                                .frame(width: 24, height: 24)
                        }
                        .help("View on Spotify").accessibilityLabel("View \(name) on Spotify")
                    }
                }
            }
            .frame(width: 185, alignment: .leading)
            trackList(context: uri)
        }
    }

    private func trackList(context: String?) -> some View {
        Group {
            if library.tracks.isEmpty {
                emptyState(submittedQuery != nil ? "No songs found" : "No playable songs", hint: nil)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 1) {
                        ForEach(library.tracks, id: \.id) { track in
                            trackRow(track, context: context)
                        }
                    }
                }
                .id(library.trackPageOffset)
                .scrollIndicators(.automatic).disabled(library.isLoading)
            }
        }
    }

    private func trackRow(_ track: SpotifyTrack, context: String?) -> some View {
        let isActive = music.bundleIdentifier == "com.spotify.client" && music.currentTrackURI == track.uri
        let isPending = music.pendingSpotifyTrackURI == track.uri
        let action = isActive ? (music.isPlaying ? "Pause" : "Resume") : "Play"
        return Button { music.toggleSpotifyTrack(track, context: context) } label: {
            HStack(spacing: 8) {
                Group {
                    if isPending {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: isActive && music.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(isActive ? Color.green : Color.secondary)
                    }
                }
                .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name).foregroundStyle(isActive ? Color.green : Color.primary).lineLimit(1)
                    Text(track.artists).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(duration(track.durationMS)).monospacedDigit().foregroundStyle(.secondary)
            }
            .font(.system(size: 11)).padding(.vertical, 4).padding(.horizontal, 5)
            .contentShape(Rectangle())
        }
        .disabled(isPending)
        .help("\(isPending ? "Starting" : action) \(track.name), by \(track.artists)")
        .accessibilityLabel("\(action) \(track.name), by \(track.artists)")
        .accessibilityValue(isPending ? "Starting playback" : isActive ? (music.isPlaying ? "Playing" : "Paused") : "")
    }

    private var showsAlbums: Bool { !showsTracks && (submittedQuery != nil || section == .albums) }
    private var hasPreviousPage: Bool {
        showsTracks ? library.hasPreviousTracks : (showsAlbums ? library.hasPreviousAlbums : library.hasPreviousPlaylists)
    }
    private var hasNextPage: Bool {
        showsTracks ? library.hasMoreTracks : (showsAlbums ? library.hasMoreAlbums : library.hasMorePlaylists)
    }
    private var pageRange: String {
        let offset = showsTracks ? library.trackPageOffset : (showsAlbums ? library.albumPageOffset : library.playlistPageOffset)
        let end = showsTracks ? library.trackPageEndOffset : (showsAlbums ? library.albumPageEndOffset : library.playlistPageEndOffset)
        let name = showsTracks ? "Songs" : (showsAlbums ? "Albums" : "Playlists")
        return end > offset ? "\(name) \(offset + 1)–\(end)" : name
    }

    @ViewBuilder
    private var pagination: some View {
        if hasPreviousPage || hasNextPage {
            HStack {
                Button {
                    run(showLoading: false) {
                        if showsTracks { await library.loadPreviousTracks() }
                        else if showsAlbums { await library.loadPreviousAlbums() }
                        else { await library.loadPreviousPlaylists() }
                    }
                } label: {
                    Label("Previous page", systemImage: "chevron.left")
                }
                .disabled(!hasPreviousPage)
                Spacer()
                Text(pageRange).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button {
                    run(showLoading: false) {
                        if showsTracks { await library.loadMoreTracks() }
                        else if showsAlbums { await library.loadMoreAlbums() }
                        else { await library.loadMorePlaylists() }
                    }
                } label: {
                    HStack(spacing: 4) { Text("Next page"); Image(systemName: "chevron.right") }
                }
                .accessibilityLabel("Next page")
                .disabled(!hasNextPage)
            }
            .font(.system(size: 10, weight: .medium))
            .frame(height: 20)
            .disabled(library.isLoading || isNavigating || library.errorMessage != nil)
        }
    }

    private func emptyState(_ title: String, hint: String?) -> some View {
        VStack(spacing: 5) {
            Text(title).font(.system(size: 12, weight: .medium))
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        guard searchFocused else { return }
        let value = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard value.count >= 2 || (value.isEmpty && submittedQuery != nil) else { return }
        guard value != (submittedQuery ?? "") else { return }
        searchTask = Task {
            do { try await Task.sleep(for: .milliseconds(450)) } catch { return }
            guard !Task.isCancelled, searchFocused,
                  String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200)) == value else { return }
            searchTask = nil
            performSearch(endEditing: false)
        }
    }

    private func submitSearch() { performSearch(endEditing: true) }

    private func performSearch(endEditing: Bool) {
        searchTask?.cancel()
        selectedAlbum = nil
        selectedPlaylist = nil
        let value = String(query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        submittedQuery = value.isEmpty ? nil : value
        if endEditing {
            searchFocused = false
            vm.isSpotifySearchFocused = false
        }
        refresh()
    }

    private func goBack() {
        searchFocused = false
        if selectedAlbum != nil || selectedPlaylist != nil {
            selectedAlbum = nil
            selectedPlaylist = nil
        } else {
            submittedQuery = nil
            query = ""
        }
        refresh()
    }

    private func refresh() {
        run {
            if let album = selectedAlbum { await library.loadTracks(album: album) }
            else if let playlist = selectedPlaylist { await library.loadPlaylistTracks(playlist: playlist) }
            else if let query = submittedQuery {
                if searchKind == .songs { await library.searchSongs(query: query) }
                else { await library.searchAlbums(query: query) }
            } else {
                switch section {
                case .albums: await library.loadSavedAlbums()
                case .liked: await library.loadLikedTracks()
                case .playlists: await library.loadPlaylists()
                }
            }
        }
    }

    private func run(showLoading: Bool = true, _ operation: @escaping () async -> Void) {
        request?.cancel()
        let id = UUID()
        requestID = id
        isNavigating = showLoading
        request = Task {
            await operation()
            if requestID == id { isNavigating = false }
        }
    }

    private func sourceURL(kind: String, id: String) -> URL? {
        guard SpotifyAuthorization.isValidID(id) else { return nil }
        return URL(string: "https://open.spotify.com/\(kind)/\(id)")
    }

    private func endSearchAfterLosingFocus() {
        guard searchFocused else { return }
        searchFocused = false
        vm.isSpotifySearchFocused = false
        if !vm.isMouseHovering() { vm.close() }
    }

    private func dismiss() {
        searchFocused = false
        vm.isSpotifySearchFocused = false
        vm.isSpotifyBrowserPresented = false
    }

    private func duration(_ milliseconds: Int) -> String {
        let seconds = max(0, milliseconds / 1000)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct SpotifySearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSubmit: () -> Void
    var onFocusLost: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NativeSearchField {
        let field = NativeSearchField()
        field.placeholderString = "Search Spotify"
        field.font = .systemFont(ofSize: 11)
        field.controlSize = .small
        field.focusRingType = .default
        field.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        field.setAccessibilityLabel("Search Spotify songs or albums. Results update as you type.")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submitSearch(_:))
        field.onFocusRequested = { [weak coordinator = context.coordinator] in
            coordinator?.parent.isFocused = true
        }
        field.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.observe(window: window)
        }
        context.coordinator.field = field
        return field
    }

    func updateNSView(_ field: NativeSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if !isFocused, field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
    }

    static func dismantleNSView(_ field: NativeSearchField, coordinator: Coordinator) {
        field.onWindowChanged = nil
        field.onFocusRequested = nil
        field.delegate = nil
        field.target = nil
        coordinator.stopObserving()
    }

    final class NativeSearchField: NSSearchField {
        var onWindowChanged: ((NSWindow?) -> Void)?
        var onFocusRequested: (() -> Void)?
        override var needsPanelToBecomeKey: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onFocusRequested?()
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocusRequested?() }
            return accepted
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SpotifySearchField
        weak var field: NativeSearchField?
        private var windowObserver: NSObjectProtocol?
        private var applicationObserver: NSObjectProtocol?

        init(_ parent: SpotifySearchField) { self.parent = parent }

        func controlTextDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }
        func controlTextDidEndEditing(_ notification: Notification) { parent.onFocusLost() }

        @objc func submitSearch(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onSubmit()
            sender.window?.makeFirstResponder(nil)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)), let field {
                submitSearch(field)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onFocusLost()
                field?.window?.makeFirstResponder(nil)
                return true
            }
            return false
        }

        func observe(window: NSWindow?) {
            stopObserving()
            guard let window else { return }
            windowObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishEditing() }
                }
            applicationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                object: NSApp, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finishEditing() }
                }
        }

        private func finishEditing() {
            guard parent.isFocused else { return }
            parent.onFocusLost()
            field?.window?.makeFirstResponder(nil)
        }

        func stopObserving() {
            if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
            if let applicationObserver { NotificationCenter.default.removeObserver(applicationObserver) }
            windowObserver = nil
            applicationObserver = nil
        }
    }
}

private struct SpotifyAlbumArtwork: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5)).clipped().accessibilityHidden(true)
        .task(id: url) {
            image = nil
            guard let url, url.scheme?.lowercased() == "https" else { return }
            do {
                let data = try await ImageService.shared.fetchImageData(from: url)
                try Task.checkCancellation()
                image = NSImage.downsampledArtwork(data: data, maxPixelSize: 144)
            } catch { }
        }
    }
}
