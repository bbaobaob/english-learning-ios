import Foundation
import SwiftUI

/// A countdown that ticks in the background, pauses, and never nags.
///
/// Deliberately not persisted: an exam clock that survives a relaunch would be a lie
/// about time actually spent. The learner's *draft* persists; the clock does not.
@MainActor
@Observable
final class ExamTimer {
    /// Wall-clock seconds left.
    private(set) var remaining: Int
    /// Total seconds the timer started from, for the progress ring.
    let total: Int
    private(set) var isRunning = false
    /// Set once the countdown reaches zero.
    private(set) var didFinish = false

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let label: String

    init(seconds: Int, label: String) {
        total = max(seconds, 1)
        remaining = max(seconds, 1)
        self.label = label
    }

    /// `mm:ss`, or `h:mm:ss` past an hour. VoiceOver reads this via `accessibilityValue`.
    var display: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var spokenLabel: String {
        let minutes = remaining / 60
        let seconds = remaining % 60
        let time = minutes == 0 ? "\(seconds) seconds" : "\(minutes) minutes"
        return "\(label), \(time) remaining"
    }

    /// `0...1`, 1 when untouched. Turns red under two minutes.
    var fraction: Double { Double(remaining) / Double(total) }

    var isUrgent: Bool { remaining <= 120 && remaining > 0 }

    /// Seconds already spent. Used when a learner comes back to a saved draft:
    /// the clock starts from where it was, never from zero.
    var elapsed: Int { total - remaining }

    /// Restores an elapsed position. Never resurrects a finished clock.
    func adopt(elapsed seconds: Int) {
        guard !isRunning, !didFinish, seconds > 0, seconds < total else { return }
        remaining = total - seconds
    }

    func start() {
        guard !isRunning, !didFinish else { return }
        isRunning = true
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.tick()
            }
        }
    }

    func pause() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        remaining = total
        didFinish = false
    }

    private func tick() {
        guard isRunning else { return }
        if remaining <= 1 {
            remaining = 0
            didFinish = true
            pause()
        } else {
            remaining -= 1
        }
    }
}