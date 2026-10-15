// Notch Apple additions, 15 October 2026. GPL-3.0.
import AppKit
import Combine
import Foundation

/// Uses a deadline so sleep and delayed callbacks cannot make the timer drift.
struct FocusCountdown {
    private(set) var duration: TimeInterval = 25 * 60
    private(set) var remaining: TimeInterval = 25 * 60
    private(set) var deadline: Date?

    var isRunning: Bool { deadline != nil }
    var isFinished: Bool { remaining == 0 && deadline == nil }

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        if remaining <= 0 { remaining = duration }
        deadline = now.addingTimeInterval(remaining)
    }

    mutating func tick(at now: Date) {
        guard let deadline else { return }
        remaining = max(0, deadline.timeIntervalSince(now))
        if remaining == 0 { self.deadline = nil }
    }

    mutating func pause(at now: Date) {
        tick(at: now)
        deadline = nil
    }

    mutating func reset(minutes: Int? = nil) {
        if let minutes, (1...720).contains(minutes) {
            reset(seconds: minutes * 60)
            return
        }
        remaining = duration
        deadline = nil
    }

    mutating func reset(seconds: Int) {
        guard (1...43_200).contains(seconds) else { return }
        duration = TimeInterval(seconds)
        remaining = duration
        deadline = nil
    }
}

@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    @Published private(set) var countdown = FocusCountdown()
    private var ticker: Timer?

    var displayTime: String {
        if countdown.isFinished { return "Done" }
        let seconds = Int(ceil(countdown.remaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggle() {
        if countdown.isRunning {
            countdown.pause(at: Date())
            stopTicker()
        } else {
            countdown.start(at: Date())
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.update() }
            }
            RunLoop.main.add(timer, forMode: .common)
            ticker = timer
        }
    }

    func reset(minutes: Int? = nil) {
        stopTicker()
        countdown.reset(minutes: minutes)
    }

    func reset(seconds: Int) {
        guard (1...43_200).contains(seconds) else { return }
        stopTicker()
        countdown.reset(seconds: seconds)
    }

    private func update() {
        countdown.tick(at: Date())
        if countdown.isFinished {
            stopTicker()
            NSSound(named: "Glass")?.play()
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}
