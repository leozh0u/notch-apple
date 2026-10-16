---
name: Notch Apple
description: A personal native Mac notch utility centred on music.
colors:
  notch-black: "#000000"
  control-white: "#ffffff"
  apple-gold: "color(srgb 1 0.79 0.31)"
---

# Notch Apple design

## Overview

Confirmed brief and refinement, 15 October 2026: Leo wants a personal Dynamic Island-style Mac utility called Notch Apple. Prioritise playful appearance and music, retain useful widgets and shortcuts, and make everything blend well. Preserve the original compact notch attached directly to the screen's top edge.

Keep the established native SwiftUI/AppKit interface, with black behind and around the physical camera notch, system typography and familiar controls. Music is the main content, with its original artwork and control proportions. Album artwork supplies colour; decorative glow stays local to the artwork. A white circular play button is the strongest control. The small playback bars, optional idle eyes and subtle golden apple identity provide personality.

This extends Boring Notch's existing interface. Personal development comes first. Keep upstream attribution, independent bundle identifiers and manual updates. Public preview distribution is authorised, with source and licence notices retained.

## Colors

- Use `notch-black` for the outer notch surface and its top seam, and `control-white` for primary music text, the play button and playback bars.
- Keep secondary text and utility controls in native `.secondary` or `.gray`. Settings uses `NSColor.windowBackgroundColor` and standard macOS selection and control colours. Preserve these adaptive values rather than copying screenshot colours.
- Use `apple-gold` sparingly for the enchanted theme's effective accent, including the focus dial and selected shuffle control. Preserve the custom accent override and native accent when that theme is disabled. Keep the golden apple icon's colour local to the identity.
- Album-art tinting remains configurable. The artist and time labels use the existing minimum-brightness adjustment (factor 0.6); selected repeat controls and an artwork-coloured slider use factor 0.8.
- The completed focus timer uses native `.green` and a checkmark. Its text changes to `Done`, so colour is not the only completion cue.

## Typography

Use the macOS system font and SF Symbols. Music titles use `.headline`, artists use `.subheadline` with medium weight, and elapsed/duration labels use `.caption` with medium weight. Preserve native text styles rather than assigning guessed point sizes.

The focus footer uses system medium type (11 pt). Its duration control uses monospaced digits in a fixed 76 by 26 pt area, including the dial icon. Start/Pause and End/Reset keep fixed widths (62 and 58 pt). The main music play/pause symbol uses system semibold type (17 pt). The duration editor's central time uses rounded system medium type (30 pt).

## Layout

The nominal expanded notch is 640 by 235 pt. The window reserves 20 pt below for shadow. The original `NotchShape` attaches directly to the screen's top edge, without a top spacer, gap, stem or cutout. Closed geometry comes from the selected screen's camera areas, safe-area inset and notch-height settings; do not replace it with one universal size.

Keep one Home/Shelf tab row in the header. Music and optional Calendar/camera content share the upper area. The Home stack leaves 12 pt between this content and the focus-only footer. The footer contains the Focus label, duration dial button, Start/Pause and End/Reset. It uses 8 pt between items, 5 pt horizontal inset and 8 pt top inset. Calendar and Shelf shortcuts do not repeat in this footer. The battery indicator is off by default; it remains available as an optional setting. Preserve user-configurable music slots.

The Spotify browser replaces the Home content inside the same shell. Hide the focus footer while browsing, and keep the outer Home/Shelf navigation unchanged. Return to the player through Now Playing.

The closed state places small artwork and five rounded playback bars on opposite sides of the camera. Preserve the central camera clearance. The player artwork dimensions are 90 by 90 pt expanded and 20 by 20 pt closed.

## Elevation & Depth

The notch is an opaque black surface. Its optional shadow appears while open or hovered, using black at 0.7 opacity and a radius of 6 pt with corner scaling or 4 pt without it. The artwork lighting effect uses blurred artwork (40 pt blur, 0.18 opacity while playing). Keep that effect local to the artwork and preserve the clean outer edge.

Settings retains native layered surfaces. The focus footer uses one subtle top divider, white at 0.12 opacity with a height of 0.5 pt. Both window implementations retain the `.mainMenu + 3` level used by the placement and hover hotfix below.

## Shapes

Preserve the existing notch silhouette. With corner scaling enabled, the expanded top/bottom radii are 19/24 pt and the closed radii are 6/14 pt. Artwork radii are 13 pt expanded and 4 pt closed, with the existing setting controlling scaling. The main play button is a circle (38 pt diameter). Shelf drop areas retain rounded dashed outlines (16 pt radius).

## Components

### Music controls

The white play/pause circle contains a black symbol, with plain previous/next and configurable companion controls. Keep provider-dependent availability, disabled states and permissions. Playback progress uses a rounded track, 5 pt high at rest and 9 pt while dragging, inside a 10 pt layout height. The slider's existing spring has response 0.35 and damping fraction 0.7.

### Native Spotify browser

Keep the browser native SwiftUI, with no WebView. Artwork and the browse button open it from the player. Its toolbar contains a Spotify/back action, a rounded-border search field, a mini Songs/Albums segmented picker, loading state, playback control and Now Playing. Search submits on Return. Albums, Liked Songs and Playlists use one underlined section row, with the effective accent on the selected underline.

Album and playlist shelves scroll horizontally. Tiles use 66 pt square artwork in an 82 pt column, medium 11 pt names and secondary 10 pt subtitles. Collection detail uses a 185 pt identity column with 50 pt artwork and a Play all capsule beside a vertical song list. Song rows retain the title, artist and monospaced duration. The actual active Spotify URI makes the song title and play/pause icon green. A playing current song offers Pause; a paused current song offers Resume. The pending song has a fixed-width spinner and cannot be started twice while pending; other songs stay selectable. Pending alone never marks a song as playing. Names truncate within their allocated space; help and accessibility labels keep the full identity.

Previous page and Next page share a 20 pt footer. Their enabled states follow the current offset and page metadata. Keep metadata bounded to the current page (20 albums/playlists, 50 collection tracks or 10 search results). Show loading, empty, retry and connection states in the content area. Set up Spotify leads to Media settings; browser sign-in uses PKCE with Keychain tokens and library/playlist read scopes plus playback-state read/control scopes. Track and collection selection use the Spotify Web API with a specific computer device ID, never a Spotify URI-opening command. The installed Spotify app renders audio hidden in the background. Existing library connections can enable playback permission without losing browsing; ambiguous or renamed Macs use the Media settings device selector.

Connection progress names the current step: finish sign-in in the browser, connect to Spotify, then save sign-in. The browser step explains choosing Agree and includes Continue in browser. Cancel stops the attempt without disconnecting an existing account. Browser, network and Keychain waits have separate deadlines and retry messages.

This is a core music-library browser. Preserve its implemented scope: album, song and playlist browsing, Songs/Albums search and native playback. Queue editing, recommendations, podcasts, artist search and account management are outside this interface.

### Focus timer and duration dial

Clicking the duration opens a native popover with a circular dial and exact Minutes/Seconds fields. The dial covers 1 to 120 minutes in one-minute steps; the fields accept any total from 1 second to 12 hours, with seconds from 0 to 59. Invalid input disables Set duration and displays an error. The default is 25 minutes. Editing is disabled while running.

The editor is 260 pt wide with 18 pt padding. Its dial occupies 156 by 156 pt, with a 64 pt track radius, rounded 5 pt strokes and a 14 pt knob. Preserve native rounded-border fields, Cancel and Set duration buttons. The dial has arrow-key handling and an accessibility adjustable action in source; these do not establish a completed keyboard or VoiceOver audit.

Starting focus closes the editor, unpins the island and requests that it close. Pause keeps the remaining duration; End/Reset restores the selected duration. Actions have stable dimensions, help text and explicit accessibility labels. Appearance settings can hide the footer. The timer resets when the app quits.

### Optional Calendar

Calendar is off by default until the user chooses setup in Settings. Connect Calendar requests macOS Calendar access and enables upcoming events after full access is granted. Google accounts connect through macOS Calendar's Add Account flow. The optional upcoming-event area belongs beside music, with no Calendar shortcut in the focus footer.

Show only events from the selected calendars, including the chosen Google account's calendars exposed through macOS Calendar. The compact area is 205 by 140 pt and shows the date and next two events, with a native Calendar action. Keep permission, no-calendar, no-selection and no-event states distinct. Scheduled refresh at event boundaries runs only while the island is open; closing cancels that wake-up. This bridge has no separate Google app sign-in or Gmail message access.

### Playback bars and idle eyes

The five white bars use a 1.5 pt gap and rounded ends. They are a playback animation, not an audio spectrum. Their timeline runs at up to 24 frames per second and pauses when playback stops, Reduce Motion is enabled or Gentle music animation is disabled.

The optional idle face uses two white capsules at 0.85 opacity, each 4 pt wide and 6 pt high, separated by 5 pt. They blink every 4 seconds, contracting to 1.5 pt for 160 ms with 0.1-second ease-in-out transitions. Reduce Motion or disabling Gentle music animation leaves the eyes static; removing the view cancels its task. Both decorative views are hidden from accessibility.

### Native movement and settings

Retain the inherited opening spring (response 0.42, damping fraction 0.8), closing spring (0.45, 1.0) and interactive movement spring (0.38, 0.8). The new recurring-animation checks above do not establish Reduce Motion coverage for all inherited transitions. Appearance and About remain native settings pages, with the existing sidebar, grouped controls and upstream credit.

## Do's and Don'ts

- Do preserve pure black around the physical notch and keep album colour local to content.
- Do retain music as the strongest content and the white circular play button as its primary action.
- Do keep the focus controls compact and stable as their state changes.
- Do keep one Home/Shelf navigation row, the focus-only footer and optional Calendar setup in Settings.
- Do preserve native settings, provider support, feature permissions and upstream attribution.
- Don't add a border, coloured outline or decorative glow around the outer notch.
- Don't detach the notch from the screen edge or add a gap, stem, cutout or top spacer.
- Don't describe the animated bars as measured audio or microphone input.
- Don't claim all inherited motion or assistive-technology flows have been verified from screenshots alone.

## Native placement regression check

Version 0.2.1 restores the original `.mainMenu + 3` panel level and rectangular hover content shape. On this Mac, lowering the panel to `.floating` displaced the closed notch below the menu bar and broke normal hover. Keep the painted `NotchShape` unchanged. Verify closed placement and hover on the actual desktop; a cropped app capture cannot establish alignment with the screen edge. Leo confirmed the repaired build is flush and opens normally on 15 October 2026.

## Spotify interaction corrections

Search uses a native NSSearchField that explicitly accepts keyboard focus on click. Preserve the query during music updates and clear editing focus when the panel loses key status. Hovering alone must not activate the app or focus Search. Hide the Search for picker label while keeping its accessibility label.

Hide pagination for single-page collections. Longer collections show their current source range and working Previous/Next controls. Disable the island’s outer swipe gesture while browsing so two-finger list scrolling cannot move or close the shell. Playback feedback updates immediately and is reconciled with Spotify’s actual state; track selection uses non-interactive native playback events and hides Spotify afterward.
