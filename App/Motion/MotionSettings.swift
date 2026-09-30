import SwiftUI

// MARK: - MotionSettings
//
// Reduce Motion is a single live fact for the whole app, so it is read in one
// place and handed to the view tree through the environment instead of being
// re-queried (or worse, captured once) inside every effect.
//
// Two reasons this is an object rather than a computed property:
//
//   1. **It updates while the app is running.** iOS posts a notification when
//      the user flips Reduce Motion in Settings and then returns to the app. A
//      `@Published` change invalidates every view that read it, so effects that
//      were mid-flight collapse to their static variant without a relaunch.
//   2. **It is testable without a device.** `MotionSettings(reduceMotion:)` takes
//      the flags by hand, so a unit test — or a SwiftUI preview — can force
//      either flag on and assert the static variant renders. The UIKit
//      notification plumbing is only installed on `.shared`.
//
// The seam is deliberately dumb: two booleans in, two booleans out. No policy
// lives here.

/// The live accessibility state that every effect in `App/Motion` reacts to.
///
/// Inject it with `.environment(\.motionSettings, MotionSettings(reduceMotion: true))`
/// to force the reduced variants in a preview or a test.
final class MotionSettings: ObservableObject {

    /// `true` when the user has asked the system to reduce motion.
    ///
    /// Every effect in this folder collapses to a non-moving (or opacity-only)
    /// variant when this is `true`. There is no per-effect opt-out: an effect
    /// that cannot honour it does not ship.
    @Published private(set) var reduceMotion: Bool

    /// `true` when the user has asked the system to avoid translucency.
    ///
    /// Only the effects that draw with alpha — the ambient backdrop, the XP
    /// bar's sheen, the skeleton shimmer — need to care. Effects drawn in
    /// fully opaque semantic colours are unaffected.
    @Published private(set) var reduceTransparency: Bool

    /// The app-wide instance. Observes the UIKit change notifications.
    ///
    /// @MainActor because it is read during view body evaluation and because
    /// `@Published` updates are delivered on the main actor here.
    @MainActor
    static let shared = MotionSettings(observeSystem: true)

    /// The live flags, read straight from UIKit.
    ///
    /// This is the honest source of truth and the right answer for code outside
    /// the view tree. Inside a view, prefer `@Environment(\.motionSettings)` so
    /// the value participates in observation and a mid-flight change re-renders.
    static var isReduceMotionEnabled: Bool { UIAccessibility.isReduceMotionEnabled }
    static var isReduceTransparencyEnabled: Bool { UIAccessibility.isReduceTransparencyEnabled }

    private var tokens: [NSObjectProtocol] = []

    /// A settings object with the flags set by hand, for tests and previews.
    ///
    /// Deliberately takes plain `Bool`s and never reads UIKit, so a test can
    /// exercise both settings paths on any host. `observeSystem` defaults to
    /// `false` so no notification observer is installed and nothing can
    /// overwrite the values passed in.
    init(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        observeSystem: Bool = false
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        if observeSystem {
            observeSystemSettings()
        }
    }

    deinit {
        // The observer tokens are the only things that outlive this object.
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    /// Sets the flags directly. The test seam, and the only way to simulate a
    /// mid-session accessibility change in a test.
    func set(reduceMotion: Bool? = nil, reduceTransparency: Bool? = nil) {
        if let reduceMotion { self.reduceMotion = reduceMotion }
        if let reduceTransparency { self.reduceTransparency = reduceTransparency }
    }

    private func observeSystemSettings() {
        let center = NotificationCenter.default
        // Both switches are observed, not just the one a given effect happens
        // to use, so a single instance can serve every effect in the app.
        tokens.append(
            center.addObserver(
                forName: UIAccessibility.reduceMotionStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // Re-read rather than trusting the payload: the notification
                // carries no value, it only says "look again".
                self?.reduceMotion = UIAccessibility.isReduceMotionEnabled
            }
        )
        tokens.append(
            center.addObserver(
                forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
            }
        )
    }
}

// MARK: - Environment

private struct MotionSettingsKey: EnvironmentKey {
    /// The app-wide live settings, so a view that is never handed an explicit
    /// value still tracks the system setting.
    static var defaultValue: MotionSettings { MainActor.assumeIsolated { .shared } }
}

extension EnvironmentValues {
    /// The accessibility state every motion effect in `App/Motion` reads.
    ///
    /// Force the reduced variants in a preview or a test:
    ///
    /// ```swift
    /// MotionSettings(reduceMotion: true)
    ///     .environment(\.motionSettings)
    /// ```
    var motionSettings: MotionSettings {
        get { self[MotionSettingsKey.self] }
        set { self[MotionSettingsKey.self] = newValue }
    }
}