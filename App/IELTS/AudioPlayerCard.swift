import AVFoundation
import EnglishCore
import SwiftUI

/// A small player for the shipped `AudioClip`s (all of which are `speech`).
///
/// Driving goes through `AppState.speech`, which is the `SpeechPlaying` protocol from
/// EnglishCore — so this is not a second audio engine, it is a view of one.
///
/// This is *not* a duplicate of `App/Audio`'s player and is not scheduled to be
/// deleted as one. `AudioPlayerView` and `QuickAudioControls` are themed for the
/// rest of the app; a paper wants a didone/ink treatment and a speed menu, and
/// folding that in would mean the generic player grows an `isExam: Bool`. The two
/// share one engine (`AppState.speech`) and one rate vocabulary (`SpeechRate`), so
/// there is still no second audio engine — only a second skin.
///
/// If the exam treatment is ever retired, this is the one to delete, and the
/// call sites in Listening/Reading/Writing/Speaking are the four to change.
struct AudioPlayerCard: View {
    let clip: AudioClip

    @Environment(AppState.self) private var appState
    @State private var isPlaying = false
    /// Read through `SpeechRate` rather than the framework global, so the
    /// default cannot drift from what the speed menu offers.
    @State private var rate: Float = SpeechRate.normal
    @State private var showRates = false

    private var text: String { clip.text ?? clip.title ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if clip.kind != .speech {
                // No bundled file ships with the content today. Saying so beats
                // showing a button that cannot do anything.
                Label("No audio file is bundled for this clip.", systemImage: "waveform.slash")
                    .font(.examBody(12))
                    .foregroundStyle(Color.examInkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else if text.isEmpty {
                Label("This clip has no spoken text.", systemImage: "text.quote")
                    .font(.examBody(12))
                    .foregroundStyle(Color.examInkSoft)
            } else {
                controls
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.sm)
        .background(Color.examPaperSunk, in: .rect(cornerRadius: Radius.card))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Button {
                    play()
                } label: {
                    Label(isPlaying ? "Playing" : "Play", systemImage: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                        .font(.examBody(14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.examRed, in: .rect(cornerRadius: Radius.chip))
                        .foregroundStyle(.white)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? "Stop the recording" : "Play the recording")
                .accessibilityHint(clip.title ?? "The audio for this question")

                Button {
                    appState.speech.stop()
                    isPlaying = false
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.examBody(14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color.examPaper, in: .rect(cornerRadius: Radius.chip))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.examInk)
                .accessibilityLabel("Stop playback")

                Button {
                    withAnimation(ExamMotion.tick) { showRates.toggle() }
                } label: {
                    Text(String(format: "%.2f×", rate))
                        .font(.examMono(12, weight: .semibold))
                        .frame(width: 48, height: 44)
                        .background(Color.examPaper, in: .rect(cornerRadius: Radius.chip))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.examInk)
                .accessibilityLabel("Playback speed, \(String(format: "%.1f", rate)) times")
                .accessibilityHint("Reveals the speed options")
            }

            if showRates {
                HStack(spacing: Spacing.sm) {
                    ForEach(Self.rates, id: \.self) { candidate in
                        Button {
                            rate = candidate
                            Haptics.selection()
                        } label: {
                            Text(String(format: "%.2f×", candidate))
                                .font(.examMono(12, weight: .semibold))
                                .foregroundStyle(candidate == rate ? .white : Color.examInk)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(candidate == rate ? Color.examRed : Color.examPaper, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Speed \(String(format: "%.1f", candidate))")
                        .accessibilityAddTraits(candidate == rate ? [.isButton, .isSelected] : .isButton)
                    }
                }
                .transition(.opacity)
            }
        }
        .onDisappear { appState.speech.stop() }
    }

    private func play() {
        guard !text.isEmpty else { return }
        appState.speech.speak(text, rate: rate) { [weak self] in
            // The protocol's completion is not documented as main-actor; hop explicitly.
            Task { @MainActor in self?.isPlaying = false }
        }
        isPlaying = true
        Haptics.selection()
    }

    /// Real listening practice needs slow replay. 0.5 is the exam's slow setting.
    private static let rates: [Float] = [0.5, 0.75, 1.0, 1.25]
}