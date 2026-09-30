import SwiftUI
import UIKit

/// The app's haptics, in four named intents.
///
/// Wrapping `UINotificationFeedbackGenerator` in a function rather than calling
/// it inline keeps two things true: a generator is prepared immediately before
/// use, so the first tap is not late, and the same intent always feels the
/// same. A correct answer that buzzes differently from a wrong one teaches the
/// grading model before the learner has read a word of it.
///
/// Calls are no-ops where the hardware has no haptic engine, which is what
/// `UIImpactFeedbackGenerator` already handles.
enum Haptics {
    /// Something was right. A light, short confirmation.
    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Something is wrong but recoverable — a skipped step, a soft nudge.
    static func warning() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }

    /// Something was wrong and the learner should notice now.
    static func failure() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }

    /// A value changed: a chip toggled, a counter stepped, a segment moved.
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }
}
