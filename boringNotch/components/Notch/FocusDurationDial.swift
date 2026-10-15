// Notch Apple additions, 15 October 2026. GPL-3.0.
import SwiftUI

struct FocusDurationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: String
    @State private var seconds: String
    private let initialSeconds: Int
    let onApply: (Int) -> Void

    init(seconds: Int, onApply: @escaping (Int) -> Void) {
        initialSeconds = seconds
        _minutes = State(initialValue: String(seconds / 60))
        _seconds = State(initialValue: String(format: "%02d", seconds % 60))
        self.onApply = onApply
    }

    private var duration: Int? {
        guard let minutes = Int(minutes), let seconds = Int(seconds),
              (0...720).contains(minutes), (0...59).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return (1...43_200).contains(total) ? total : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("Focus duration")
                .font(.headline)
            FocusDurationDial(seconds: Binding(
                get: { duration ?? initialSeconds },
                set: {
                    minutes = String($0 / 60)
                    seconds = String(format: "%02d", $0 % 60)
                }
            ))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minutes").font(.caption)
                    TextField("Minutes", text: $minutes)
                        .accessibilityLabel("Focus minutes")
                }
                Text(":").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Seconds").font(.caption)
                    TextField("Seconds", text: $seconds)
                        .accessibilityLabel("Focus seconds")
                }
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()

            Text(duration == nil ? "Enter 1 second to 12 hours; seconds 0–59." : "Dial 1–120 minutes; enter any time up to 12 hours.")
                .font(.caption2)
                .foregroundStyle(duration == nil ? Color.red : Color.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 30)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Set duration") {
                    if let duration { onApply(duration) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duration == nil)
                .tint(Color.effectiveAccent)
            }
        }
        .padding(18)
        .frame(width: 260)
    }
}

struct FocusDurationDial: View {
    @Binding var seconds: Int
    private let radius: CGFloat = 64

    private var minutes: Int { min(120, max(1, Int((Double(seconds) / 60).rounded()))) }
    private var progress: Double { Double(minutes - 1) / 119 }
    private var angle: Double { (126 + progress * 288) * .pi / 180 }

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: 0.8)
                .stroke(.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(126))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .trim(from: 0, to: progress * 0.8)
                .stroke(Color.effectiveAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(126))
                .frame(width: radius * 2, height: radius * 2)
            VStack(spacing: 0) {
                Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text("min : sec").font(.caption).foregroundStyle(.secondary)
            }
            Circle()
                .fill(Color.effectiveAccent)
                .frame(width: 14, height: 14)
                .offset(x: cos(angle) * radius, y: sin(angle) * radius)
        }
        .frame(width: 156, height: 156)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            let x = value.location.x - 78
            let y = value.location.y - 78
            guard hypot(x, y) > 24 else { return }
            var degrees = atan2(y, x) * 180 / .pi - 126
            if degrees < 0 { degrees += 360 }
            if degrees > 288 { degrees = degrees < 324 ? 288 : 0 }
            seconds = (1 + Int((degrees / 288 * 119).rounded())) * 60
        })
        .focusable()
        .onMoveCommand { direction in
            switch direction {
            case .up, .right: adjust(by: 1)
            case .down, .left: adjust(by: -1)
            default: break
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus duration dial")
        .accessibilityValue("\(seconds / 60) minutes, \(seconds % 60) seconds")
        .accessibilityHint("Adjust from 1 to 120 minutes, or use the exact minutes and seconds fields")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: 1)
            case .decrement: adjust(by: -1)
            @unknown default: break
            }
        }
        .help("Drag around the circle or use arrow keys to set minutes.")
    }

    private func adjust(by amount: Int) {
        seconds = min(120, max(1, minutes + amount)) * 60
    }
}
