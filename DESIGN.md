---
name: Notch Apple
description: A personal native Mac notch utility centred on music.
colors:
  notch-black: "#000000"
  control-white: "#ffffff"
---

# Notch Apple design

## Overview

Confirmed brief, 15 October 2026: Leo wants a personal Dynamic Island-style Mac utility called Notch Apple. Prioritise playful appearance and music, retain useful widgets and shortcuts, and make everything blend well.

Keep the established native SwiftUI/AppKit interface, with black behind and around the physical camera notch, system typography and familiar controls. Music is the main content. Album artwork supplies colour; decorative glow stays local to the artwork. A white circular play button is the strongest control. The small playback bars and optional idle eyes provide personality.

This extends Boring Notch's existing interface. Personal development comes first. Keep upstream attribution, independent bundle identifiers and manual updates. Public release remains undecided.

## Colors

- Use `notch-black` for the outer notch surface and its top seam, and `control-white` for primary music text, the play button and playback bars.
- Keep secondary text and utility controls in native `.secondary` or `.gray`. Settings uses `NSColor.windowBackgroundColor` and standard macOS selection and control colours. Preserve these adaptive values rather than copying screenshot colours.
- Album-art tinting remains configurable. The artist and time labels use the existing minimum-brightness adjustment (factor 0.6); selected shuffle/repeat controls and an artwork-coloured slider use factor 0.8.
- The completed focus timer uses native `.green` and a checkmark. Its text changes to `Done`, so colour is not the only completion cue.

## Typography

Use the macOS system font and SF Symbols. Music titles use `.headline`, artists use `.subheadline` with medium weight, and elapsed/duration labels use `.caption` with medium weight. Preserve native text styles rather than assigning guessed point sizes.

The utility row uses system medium type (11 pt). Its countdown uses monospaced digits and a fixed width (47 pt) to keep adjacent actions stable. The main play/pause symbol uses system semibold type (17 pt).

## Layout

The nominal expanded notch is 640 by 235 pt. The window reserves 20 pt below for shadow. Closed geometry comes from the selected screen's camera areas, safe-area inset and notch-height settings; do not replace it with one universal size.

Music and optional Calendar/camera content share the upper area. The Home stack leaves 12 pt between this content and the utility row. The row contains focus duration, countdown, start/pause, reset, Calendar and an optional Shelf action. It uses 8 pt between items, 5 pt horizontal inset and 8 pt top inset. Keep the existing Home/Shelf navigation and user-configurable music slots.

The closed state places small artwork and five rounded playback bars on opposite sides of the camera. Preserve the central camera clearance. The player artwork dimensions are 90 by 90 pt expanded and 20 by 20 pt closed.

## Elevation & Depth

The notch is an opaque black surface. Its optional shadow appears while open or hovered, using black at 0.7 opacity and a radius of 6 pt with corner scaling or 4 pt without it. The artwork lighting effect uses blurred artwork (40 pt blur, 0.18 opacity while playing). Keep that effect local to the artwork and preserve the clean outer edge.

Settings retains native layered surfaces. The utility row uses one subtle top divider, white at 0.12 opacity with a height of 0.5 pt.

## Shapes

Preserve the existing notch silhouette. With corner scaling enabled, the expanded top/bottom radii are 19/24 pt and the closed radii are 6/14 pt. Artwork radii are 13 pt expanded and 4 pt closed, with the existing setting controlling scaling. The main play button is a circle (38 pt diameter). Shelf drop areas retain rounded dashed outlines (16 pt radius).

## Components

### Music controls

The white play/pause circle contains a black symbol, with plain previous/next and configurable companion controls. Keep provider-dependent availability, disabled states and permissions. Playback progress uses a rounded track, 5 pt high at rest and 9 pt while dragging, inside a 10 pt layout height. The slider's existing spring has response 0.35 and damping fraction 0.7.

### Focus timer and shortcuts

The duration menu offers 15, 25 and 45 minutes and is disabled while running. The default is 25 minutes. Start/pause and reset have 26 by 26 pt content areas, help text and explicit accessibility labels. Calendar opens the native app; Shelf appears when the inherited Shelf feature is enabled. Appearance settings can hide the whole row. The timer resets when the app quits.

### Playback bars and idle eyes

The five white bars use a 1.5 pt gap and rounded ends. They are a playback animation, not an audio spectrum. Their timeline runs at up to 24 frames per second and pauses when playback stops, Reduce Motion is enabled or Gentle music animation is disabled.

The optional idle face uses two white capsules at 0.85 opacity, each 4 pt wide and 6 pt high, separated by 5 pt. They blink every 4 seconds, contracting to 1.5 pt for 160 ms with 0.1-second ease-in-out transitions. Reduce Motion or disabling Gentle music animation leaves the eyes static; removing the view cancels its task. Both decorative views are hidden from accessibility.

### Native movement and settings

Retain the inherited opening spring (response 0.42, damping fraction 0.8), closing spring (0.45, 1.0) and interactive movement spring (0.38, 0.8). The new recurring-animation checks above do not establish Reduce Motion coverage for all inherited transitions. Appearance and About remain native settings pages, with the existing sidebar, grouped controls and upstream credit.

## Do's and Don'ts

- Do preserve pure black around the physical notch and keep album colour local to content.
- Do retain music as the strongest content and the white circular play button as its primary action.
- Do keep the timer and shortcut controls compact and stable as their state changes.
- Do preserve native settings, provider support, feature permissions and upstream attribution.
- Don't add a border, coloured outline or decorative glow around the outer notch.
- Don't describe the animated bars as measured audio or microphone input.
- Don't claim all inherited motion or assistive-technology flows have been verified from screenshots alone.
