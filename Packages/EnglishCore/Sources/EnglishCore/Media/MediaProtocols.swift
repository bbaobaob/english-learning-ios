import Foundation

/// Speaks text aloud. The app target implements this with AVSpeechSynthesizer; Core never links it.
public protocol SpeechPlaying: AnyObject, Sendable {
    @MainActor func speak(_ text: String, rate: Float, completion: (() -> Void)?)
    @MainActor func stop()
    @MainActor var isSpeaking: Bool { get }
}

/// Turns a content clip into something the player can open. Implemented by the app target.
public protocol MediaResolving: Sendable {
    /// Local URL for a bundled or already-downloaded audio clip; `nil` for speech and missing files.
    func localURL(for clip: AudioClip) -> URL?
    /// URL a video player can play; `nil` when the clip has no source.
    func playableURL(for clip: VideoClip) -> URL?
}

// `AudioClipKind` is declared in `Content/Media.swift` alongside `AudioClip`, which is where the
// content lane put it per §1. It is not redeclared here.