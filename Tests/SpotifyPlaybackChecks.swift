import Foundation

@main struct SpotifyPlaybackChecks {
    static func main() {
        let track = "spotify:track:0123456789ABCDEFGHIJKL"
        let album = "spotify:album:abcdefghijklmnopqrstuv"
        let request = SpotifyPlaybackRequest(uri: track, context: album)!

        let event = request.makeEvent()
        assert(event.eventClass == 0x73706679) // spfy from Spotify.sdef
        assert(event.eventID == 0x50437478) // PCtx from Spotify.sdef
        assert(event.paramDescriptor(forKeyword: SpotifyPlaybackTransport.code("----"))?.stringValue == track)
        assert(event.paramDescriptor(forKeyword: SpotifyPlaybackTransport.code("cotx"))?.stringValue == album)
        assert(SpotifyPlaybackRequest(uri: album)!.makeEvent().paramDescriptor(forKeyword: SpotifyPlaybackTransport.code("cotx")) == nil)
        assert(SpotifyPlaybackTransport.sendOptions.contains(.waitForReply))
        assert(SpotifyPlaybackTransport.sendOptions.contains(.neverInteract))
        assert(!SpotifyPlaybackTransport.sendOptions.contains(.canSwitchLayer))
        assert(SpotifyPlaybackTransport.timeout == 3)
        let address = event.attributeDescriptor(forKeyword: SpotifyPlaybackTransport.code("addr"))
        assert(address?.descriptorType == 0x62756e64) // bund
        assert(address.map { String(data: $0.data, encoding: .utf8) } == "com.spotify.client")
        for command in ["Play", "Paus", "PlPs", "Next", "Prev"] {
            assert(SpotifyPlaybackTransport.makeEvent(command: command).eventID == SpotifyPlaybackTransport.code(command))
        }
        assert(SpotifyPlaybackRequest(uri: album) != nil)
        assert(SpotifyPlaybackRequest(uri: "spotify:playlist:0123456789ABCDEFGHIJKL") != nil)
        assert(SpotifyPlaybackRequest(uri: track, context: "spotify:playlist:0123456789ABCDEFGHIJKL") != nil)
        for uri in ["https://open.spotify.com/track/123", "spotify:artist:0123456789ABCDEFGHIJKL", "spotify:track:short", "spotify:track:0123456789ABCDEFGHIJKL\" & quit", "spotify:track:ééééééééééé", "spotify:track:0123456789ABCDEFGHIJKL\n"] {
            assert(SpotifyPlaybackRequest(uri: uri) == nil, uri)
        }
        assert(SpotifyPlaybackRequest(uri: track, context: track) == nil)
        print("Spotify playback checks passed: URI types, IDs, album context, injection rejection, event codes/parameters, and bounded noninteractive transport (no live sends).")
    }
}
