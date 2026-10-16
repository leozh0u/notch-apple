import Foundation

@main struct SpotifyPlaybackChecks {
    static func main() {
        let track = "spotify:track:0123456789ABCDEFGHIJKL"
        let album = "spotify:album:abcdefghijklmnopqrstuv"
        let request = SpotifyPlaybackRequest(uri: track, context: album)!
        assert(SpotifyPlaybackRequest.trackURI(from: track) == track)
        assert(SpotifyPlaybackRequest.trackURI(from: "0123456789ABCDEFGHIJKL") == track)
        assert(SpotifyPlaybackRequest.trackURI(from: "spotify:local:foo") == nil)
        let before = PlaybackState(bundleIdentifier: "com.spotify.client", trackURI: track)
        var after = before
        after.trackURI = "spotify:track:ABCDEFGHIJKL0123456789"
        assert(before != after, "Identical metadata with a different song ID must publish an update")

        let body = try! JSONSerialization.jsonObject(with: request.playbackBody) as! [String: Any]
        assert(body["context_uri"] as? String == album)
        assert((body["offset"] as? [String: String])?["uri"] == track)
        assert(body["uris"] == nil)
        let single = try! JSONSerialization.jsonObject(with: SpotifyPlaybackRequest(uri: track)!.playbackBody) as! [String: Any]
        assert(single["uris"] as? [String] == [track] && single["context_uri"] == nil)
        let collection = try! JSONSerialization.jsonObject(with: SpotifyPlaybackRequest(uri: album)!.playbackBody) as! [String: Any]
        assert(collection["context_uri"] as? String == album && (collection["offset"] as? [String: Int])?["position"] == 0)
        let event = SpotifyPlaybackTransport.makeEvent(command: "Play")
        assert(event.eventClass == 0x73706679)
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
        func device(_ id: String?, _ name: String, type: String = "computer", restricted: Bool = false) -> SpotifyPlaybackDevice {
            SpotifyPlaybackDevice(id: id, name: name, type: type, is_restricted: restricted)
        }
        let mac = device("mac", "My Mac")
        let other = device("other", "Other computer")
        let phone = device("phone", "My Mac", type: "smartphone")
        let restricted = device("restricted", "My Mac", restricted: true)
        let noID = device(nil, "My Mac")
        assert(SpotifyPlaybackDevice.thisMac(in: [other, phone, restricted, noID, mac], preferredID: "", hostNames: ["my mac"])?.id == "mac")
        assert(SpotifyPlaybackDevice.thisMac(in: [other], preferredID: "", hostNames: ["My Mac"]) == nil, "Never fall back to an unrelated active computer")
        assert(SpotifyPlaybackDevice.thisMac(in: [mac, device("duplicate", "My Mac")], preferredID: "", hostNames: ["My Mac"]) == nil, "Ambiguous names require explicit selection")
        assert(SpotifyPlaybackDevice.thisMac(in: [mac], preferredID: "stale", hostNames: ["My Mac"]) == nil, "Stale selection cannot redirect playback")
        assert(SpotifyPlaybackDevice.thisMac(in: [phone], preferredID: "phone", hostNames: []) == nil, "Phone is never a Mac fallback")
        assert(SpotifyPlaybackDevice.thisMac(in: [other], preferredID: "other", hostNames: [])?.id == "other", "Explicit computer override supported")
        print("Spotify playback checks passed: URI/body validation, album context, explicit Mac device selection, ambiguity/stale-device rejection, and bounded pause/resume transport (no live sends).")
    }
}
