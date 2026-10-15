// Notch Apple additions, 15 October 2026. GPL-3.0.
import SwiftUI

struct NotchAppleControls: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var timer = FocusTimer.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

    private var hasSession: Bool {
        timer.countdown.isRunning || timer.countdown.remaining < timer.countdown.duration
    }

    var body: some View {
        HStack(spacing: 8) {
            Label("Focus", systemImage: timer.countdown.isFinished ? "checkmark.circle" : "timer")
                .foregroundStyle(timer.countdown.isFinished ? Color.green : Color.secondary)

            Button {
                vm.isFocusEditorPresented = true
            } label: {
                HStack(spacing: 5) {
                    Text(timer.displayTime)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Image(systemName: "dial.low")
                        .foregroundStyle(Color.effectiveAccent)
                }
                .frame(width: 76, height: 26)
                .contentShape(Rectangle())
            }
            .disabled(timer.countdown.isRunning)
            .help("Set an exact focus duration")
            .accessibilityLabel("Focus duration, \(timer.displayTime)")
            .accessibilityHint("Open the duration dial and minutes and seconds editor")
            .popover(isPresented: $vm.isFocusEditorPresented, arrowEdge: .bottom) {
                FocusDurationEditor(seconds: Int(timer.countdown.duration)) { seconds in
                    timer.reset(seconds: seconds)
                    vm.isFocusEditorPresented = false
                }
            }

            Button {
                let starting = !timer.countdown.isRunning
                timer.toggle()
                if starting {
                    vm.isFocusEditorPresented = false
                    coordinator.isIslandPinned = false
                    NotificationCenter.default.post(name: Notification.Name("notchAppleFocusStarted"), object: nil)
                }
            } label: {
                Label(timer.countdown.isRunning ? "Pause" : "Start",
                      systemImage: timer.countdown.isRunning ? "pause.fill" : "play.fill")
                    .frame(width: 62, height: 26)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(.white)
            .help(timer.countdown.isRunning ? "Pause focus timer" : "Start focus timer and close the island")
            .accessibilityLabel(timer.countdown.isRunning ? "Pause focus timer" : "Start focus timer")

            Button {
                timer.reset()
            } label: {
                Label(hasSession && !timer.countdown.isFinished ? "End" : "Reset",
                      systemImage: hasSession && !timer.countdown.isFinished ? "stop.fill" : "arrow.counterclockwise")
                    .frame(width: 58, height: 26)
                    .contentShape(Rectangle())
            }
            .help(hasSession && !timer.countdown.isFinished ? "End focus session" : "Reset focus timer")
            .accessibilityLabel(hasSession && !timer.countdown.isFinished ? "End focus session" : "Reset focus timer")

            Spacer(minLength: 0)
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
