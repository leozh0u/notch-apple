// Notch Apple additions, 15 October 2026. GPL-3.0.
import Defaults
import SwiftUI

struct NotchAppleControls: View {
    @ObservedObject private var timer = FocusTimer.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach([15, 25, 45], id: \.self) { minutes in
                    Button("\(minutes) minutes") { timer.reset(minutes: minutes) }
                }
            } label: {
                Label("Focus", systemImage: timer.countdown.isFinished ? "checkmark.circle" : "timer")
                    .foregroundStyle(timer.countdown.isFinished ? Color.green : Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(timer.countdown.isRunning)
            .help("Choose a focus duration")

            Text(timer.displayTime)
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: 47, alignment: .leading)
                .accessibilityLabel("Focus timer, \(timer.displayTime)")

            Button {
                timer.toggle()
            } label: {
                Image(systemName: timer.countdown.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .help(timer.countdown.isRunning ? "Pause focus timer" : "Start focus timer")
            .accessibilityLabel(timer.countdown.isRunning ? "Pause focus timer" : "Start focus timer")

            Button {
                timer.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .help("Reset focus timer")
            .accessibilityLabel("Reset focus timer")

            Spacer(minLength: 8)

            Button {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Calendar", systemImage: "calendar")
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .help("Open Calendar")

            if Defaults[.boringShelf] {
                Button {
                    coordinator.currentView = .shelf
                } label: {
                    Label("Shelf", systemImage: "tray")
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .padding(.leading, 8)
                .help("Open file shelf")
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.horizontal, 5)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 0.5)
        }
    }
}
