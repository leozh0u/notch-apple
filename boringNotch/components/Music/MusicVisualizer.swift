//
//  MusicVisualizer.swift
//  Created by Harsh Vardhan Goswami on 02/08/24.
//  Modified for Notch Apple, 15 October 2026. GPL-3.0.
//
import Defaults
import SwiftUI

/// A playback animation, not an audio spectrum or microphone recording.
struct AudioSpectrumView: View {
    @Binding var isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.gentleMotion) private var gentleMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying || reduceMotion || !gentleMotion)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let moving = isPlaying && !reduceMotion && gentleMotion
                let count = 5
                let gap: CGFloat = 1.5
                let width = max(1, (size.width - CGFloat(count - 1) * gap) / CGFloat(count))
                for index in 0..<count {
                    let phase = Double(index) * 1.35
                    let wave = (sin(time * 5 + phase) + sin(time * 3.1 + phase * 0.7) + 2) / 4
                    let height = max(2, size.height * (moving ? 0.22 + 0.78 * wave : 0.24))
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: (size.height - height) / 2, width: width, height: height)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(.white))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
