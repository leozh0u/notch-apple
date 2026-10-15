# Notch Apple

My personal Mac notch app, based on [Boring Notch](https://github.com/TheBoredTeam/boring.notch). Music comes first, with a black shell that blends into the camera notch and small animations around it.

This is a personal build under development. It is not affiliated with Apple or TheBoredTeam.

## What changed

- Separate app identity, name and icon.
- Smooth five-bar playback animation, a small blinking idle companion and a clearer play/pause button.
- Album-art colours inside the notch, with a quieter background effect.
- Focus timer with 15, 25 and 45 minute presets, pause, reset and a completion sound. The timer accounts for sleep; it resets when the app quits.
- Keep island open from the menu or with Command-Shift-N while the app is active.
- Quick access to Calendar and the file shelf. The existing music providers, calendar widget, gestures and keyboard shortcuts remain available.
- New music and companion animations respect Reduce Motion and the Gentle music animation preference.
- Upstream automatic updates are disabled. Install this version's updates manually.

The bars animate while playback is active; they do not measure the audio waveform or use the microphone. Some upstream capabilities, including Spotify's favourite action, are unsupported by their provider.

## Build and run

Use macOS with Xcode 26 or later installed. The app targets macOS 14 or later; the upstream build instructions require macOS 15.6 or later. This checkout was developed using Xcode 27 on macOS 26.6.2.

```sh
./scripts/test.sh
./scripts/build-local.sh
open "build/Build/Products/Debug/Notch Apple.app"
```

The first build resolves the existing Swift package dependencies. The build script uses local ad-hoc signing. Internal Xcode targets and source directories retain upstream names to keep future merges manageable.

Hover over the notch to expand it. Choose a music provider during onboarding, and grant access only for features you want. Appearance settings include Gentle music animation and Focus timer and quick controls. Calendar, Shelf and Shortcuts have their own settings.

## Origin and licence

Derived from TheBoredTeam/boring.notch, initially checked out at `64b545929cf31681e09b5c375859c1eceeb733eb`. Notch Apple modifications began on 15 October 2026. Original authorship and history are retained; the original README is in [README.upstream.md](README.upstream.md).

The project remains under [GNU GPL v3](LICENSE). Keep copyright, licence and [third-party notices](THIRD_PARTY_LICENSES) when redistributing it. A distributed modified app must be accompanied by the corresponding source through a GPL-compliant method. Original upstream release and translation workflows are preserved in `.github/upstream-workflows`, where GitHub will not execute them.
