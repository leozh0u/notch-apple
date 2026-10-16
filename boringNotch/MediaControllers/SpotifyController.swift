//
//  SpotifyController.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import Foundation
import Combine
import SwiftUI

class SpotifyController: MediaControllerProtocol {
    func setFavorite(_ favorite: Bool) async {
        //Placeholder
    }
    
    // MARK: - Properties
    @Published private var playbackState: PlaybackState = PlaybackState(
        bundleIdentifier: "com.spotify.client"
    )
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { false }

    private var workspaceObservers: [NSObjectProtocol] = []
    private var notificationTask: Task<Void, Never>?
    private var playbackCommandRevision = 0
    private var playbackCommandPending = false
    private var confirmedPlaying = false
    
    // Constant for time between command and update
    private let commandUpdateDelay: Duration = .milliseconds(25)

    private var lastArtworkURL: String?
    private var artworkFetchTask: Task<Void, Never>?
    
    init() {
        setupPlaybackStateChangeObserver()
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.spotify.client" else { return }
                Task { await self?.updatePlaybackInfo() }
            }
            workspaceObservers.append(observer)
        }
        Task {
            if isActive() {
                await updatePlaybackInfo()
            }
        }
    }
    
    private func setupPlaybackStateChangeObserver() {
        notificationTask = Task { @Sendable [weak self] in
            let notifications = DistributedNotificationCenter.default().notifications(
                named: NSNotification.Name("com.spotify.client.PlaybackStateChanged")
            )
            
            for await _ in notifications {
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    deinit {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notificationTask?.cancel()
        artworkFetchTask?.cancel()
    }
    
    // MARK: - Protocol Implementation
    func play() async { await sendPlaybackCommand("Play", desiredPlaying: true) }
    func pause() async { await sendPlaybackCommand("Paus", desiredPlaying: false) }
    func togglePlay() async { await sendPlaybackCommand("PlPs", togglesPlayback: true) }
    func nextTrack() async { await sendPlaybackCommand("Next") }
    func previousTrack() async { await sendPlaybackCommand("Prev") }
    
    func seek(to time: Double) async {
        await executeAndRefresh("set player position to \(time)")
    }
    
    func toggleShuffle() async {
        await executeAndRefresh("set shuffling to not shuffling")
    }
    
    func toggleRepeat() async {
        await executeAndRefresh("set repeating to not repeating")
    }
    
    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        await executeCommand("set sound volume to \(volumePercentage)")
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == playbackState.bundleIdentifier }
    }
    
    @MainActor
    func updatePlaybackInfo() async {
        guard !playbackCommandPending else { return }
        let revision = playbackCommandRevision
        guard isActive() else {
            artworkFetchTask?.cancel()
            lastArtworkURL = nil
            await MainActor.run { self.playbackState = PlaybackState(bundleIdentifier: "com.spotify.client", title: "Nothing playing", artist: "Open Spotify to choose a track") }
            return
        }
        guard let descriptor = try? await fetchPlaybackInfoAsync() else { return }
        guard !playbackCommandPending, playbackCommandRevision == revision,
              descriptor.numberOfItems >= 11 else { return }
        
        let trackURI = SpotifyPlaybackRequest.trackURI(from: descriptor.atIndex(11)?.stringValue)
        let isPlaying = descriptor.atIndex(1)?.booleanValue ?? false
        let currentTrack = descriptor.atIndex(2)?.stringValue ?? "Unknown"
        let currentTrackArtist = descriptor.atIndex(3)?.stringValue ?? "Unknown"
        let currentTrackAlbum = descriptor.atIndex(4)?.stringValue ?? "Unknown"
        let currentTime = descriptor.atIndex(5)?.doubleValue ?? 0
        let duration = (descriptor.atIndex(6)?.doubleValue ?? 0)/1000
        let isShuffled = descriptor.atIndex(7)?.booleanValue ?? false
        let isRepeating = descriptor.atIndex(8)?.booleanValue ?? false
        let volumePercentage = descriptor.atIndex(9)?.int32Value ?? 50
        let artworkURL = descriptor.atIndex(10)?.stringValue ?? ""
        
        var state = PlaybackState(
            bundleIdentifier: "com.spotify.client",
            trackURI: trackURI,
            isPlaying: isPlaying,
            title: currentTrack,
            artist: currentTrackArtist,
            album: currentTrackAlbum,
            currentTime: currentTime,
            duration: duration,
            playbackRate: isPlaying ? 1 : 0,
            isShuffled: isShuffled,
            repeatMode: isRepeating ? .all : .off,
            lastUpdated: Date(),
            artwork: nil,
            volume: Double(volumePercentage) / 100.0
        )

        if artworkURL == lastArtworkURL, let existingArtwork = self.playbackState.artwork {
            state.artwork = existingArtwork
        }

        confirmedPlaying = state.isPlaying
        playbackState = state

        if !artworkURL.isEmpty, let url = URL(string: artworkURL) {
            guard artworkURL != lastArtworkURL || state.artwork == nil else { return }
            artworkFetchTask?.cancel()

            let currentState = state

            artworkFetchTask = Task {
                do {
                    let data = try await ImageService.shared.fetchImageData(from: url)

                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard self.playbackState.title == currentState.title,
                              self.playbackState.artist == currentState.artist,
                              self.playbackState.album == currentState.album else { return }
                        var updatedState = self.playbackState
                        updatedState.artwork = data
                        self.playbackState = updatedState
                        self.lastArtworkURL = artworkURL
                        self.artworkFetchTask = nil
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.artworkFetchTask = nil
                    }
                }
            }
        }
    }
    
    @MainActor
    func acceptConfirmedPlayback(_ snapshot: SpotifyPlaybackSnapshot) {
        guard let item = snapshot.item else { return }
        playbackCommandRevision += 1
        playbackCommandPending = false
        artworkFetchTask?.cancel()
        lastArtworkURL = nil
        var state = playbackState
        state.trackURI = item.linked_from?.uri ?? item.uri
        state.title = item.name
        state.artist = item.artists.map(\.name).joined(separator: ", ")
        state.album = item.album?.name ?? ""
        state.duration = Double(item.duration_ms) / 1000
        state.currentTime = Double(snapshot.progress_ms ?? 0) / 1000
        state.isPlaying = snapshot.is_playing
        state.playbackRate = snapshot.is_playing ? 1 : 0
        state.lastUpdated = Date()
        state.artwork = nil
        confirmedPlaying = state.isPlaying
        playbackState = state
    }

// MARK: - Private Methods
    
    @MainActor
    private func sendPlaybackCommand(_ command: String, desiredPlaying: Bool? = nil, togglesPlayback: Bool = false) async {
        guard isActive() else { return }
        playbackCommandRevision += 1
        let revision = playbackCommandRevision
        playbackCommandPending = true
        if let desired = togglesPlayback ? !playbackState.isPlaying : desiredPlaying {
            var state = playbackState
            if state.isPlaying {
                state.currentTime += Date().timeIntervalSince(state.lastUpdated) * state.playbackRate
            }
            state.isPlaying = desired
            state.playbackRate = desired ? 1 : 0
            state.lastUpdated = Date()
            playbackState = state
        }
        do {
            try await SpotifyPlaybackTransport.send(command: command)
        } catch {
            guard playbackCommandRevision == revision else { return }
            playbackState.isPlaying = confirmedPlaying
            playbackState.playbackRate = confirmedPlaying ? 1 : 0
        }
        // Later clicks own the optimistic state. A prior reply or metadata fetch
        // must not flip it back while those commands are still queued.
        guard playbackCommandRevision == revision else { return }
        playbackCommandPending = false
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }

    private func executeCommand(_ command: String) async {
        guard isActive() else { return }
        let script = "tell application \"Spotify\" to \(command)"
        try? await AppleScriptHelper.executeVoid(script)
    }

    private func executeAndRefresh(_ command: String) async {
        await executeCommand(command)
        try? await Task.sleep(for: commandUpdateDelay)
        await updatePlaybackInfo()
    }
    
    private func fetchPlaybackInfoAsync() async throws -> NSAppleEventDescriptor? {
        let script = """
        tell application "Spotify"
            set isRunning to true
            try
                set playerState to player state is playing
                set currentTrackName to name of current track
                set currentTrackArtist to artist of current track
                set currentTrackAlbum to album of current track
                set trackPosition to player position
                set trackDuration to duration of current track
                set shuffleState to shuffling
                set repeatState to repeating
                set currentVolume to sound volume
                set artworkURL to artwork url of current track
                set trackURI to id of current track
                return {playerState, currentTrackName, currentTrackArtist, currentTrackAlbum, trackPosition, trackDuration, shuffleState, repeatState, currentVolume, artworkURL, trackURI}
            on error
                return {false, "Unknown", "Unknown", "Unknown", 0, 0, false, false, 50, "", ""}
            end try
        end tell
        """
        
        return try await AppleScriptHelper.execute(script)
    }
    
}
