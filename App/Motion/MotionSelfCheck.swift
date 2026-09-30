import SwiftUI

/// Runs every self-check in `App/Motion`.
///
/// There is no Swift toolchain on the host this folder was written on, so these
/// assertions were verified by reading rather than by running. They are here so
/// that claim is no longer true: call `MotionSelfCheck.run()` from a debug build,
/// a unit test target, or a `#Preview`, and every non-trivial piece of arithmetic
/// in this folder — the roll plan, the shake curve, the bar's clock policy, the
/// streak→flame mapping, the ring geometry, the checkmark's draw, the burst
/// seeds, the waveform's height policy — is verified in one call.
///
/// Each `check()` is a pure function of literals: no view is built, no clock is
/// read, no device state is touched, so this runs in a plain unit test as
/// happily as in a simulator.
enum MotionSelfCheck {

    /// Runs every check. Crashes on the first failure via `assert`, which is the
    /// point — these are invariants, not diagnostics.
    static func run() {
        CountUpNumber.check()
        XPProgressBar.check()
        ErrorShake.check()
        StrokeCheckmark.check()
        StreakEmber.check()
        LiveWaveform.check()
        RingSweep.check()
        SparkleBurst.check()
        BreathingRecorder.check()
    }

    /// The names of the checks that ran, for a test to report on. Useful when one
    /// of them fails and you want to know which without a breakpoint.
    static var checkNames: [String] {
        [
            "CountUpNumber", "XPProgressBar", "ErrorShake", "StrokeCheckmark",
            "StreakEmber", "LiveWaveform", "RingSweep", "SparkleBurst",
            "BreathingRecorder",
        ]
    }
}

#if DEBUG
/// A body view that runs every check when it is built, for a SwiftUI preview
/// that should fail loudly if an invariant breaks:
///
/// ```swift
/// #Preview { MotionSelfCheckPreview() }
/// ```
struct MotionSelfCheckPreview: View {
    var body: some View {
        // Run once, on the first body evaluation.
        let _ = MotionSelfCheck.run()
        Text("Motion self-checks passed: \(MotionSelfCheck.checkNames.joined(separator: ", "))")
            .font(AppFont.body(.footnote))
            .foregroundStyle(Palette.textSecondary)
            .padding(Spacing.md)
    }
}
#endif