import SwiftUI
import EnglishCore

/// Every destination the Learn tab can push.
///
/// Topics and lessons are addressed by their stable content ids so a route
/// survives a relaunch: nothing here holds a live model reference.
enum LearnRoute: Hashable {
    case topic(String)
    case lesson(topicID: String, lessonID: String)
    case alphabet
    case alphabetListening
}

/// The horizontal level filter shown above the topic browser.
enum LevelFilter: String, CaseIterable, Identifiable {
    case all
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }

    /// The level this filter selects, or `nil` for "All".
    var level: Level? {
        self == .all ? nil : Level(rawValue: rawValue)
    }
}

/// Display metadata for the ten step types.
///
/// The rail, the lesson rows and the topic cards all read from here so a step
/// type never gets two different icons or two different names.
enum StepMeta {
    static func icon(_ type: LessonStep.StepType) -> String {
        switch type {
        case .theory: "text.book.closed"
        case .video: "play.rectangle"
        case .audio: "waveform"
        case .examples: "text.quote"
        case .practice: "pencil.and.outline"
        case .exercises: "checklist"
        case .dictation: "keyboard"
        case .listening: "ear"
        case .quiz: "list.number"
        case .summary: "flag.checkered"
        }
    }

    static func title(_ type: LessonStep.StepType) -> String {
        switch type {
        case .theory: "Theory"
        case .video: "Video"
        case .audio: "Audio"
        case .examples: "Examples"
        case .practice: "Practice"
        case .exercises: "Exercises"
        case .dictation: "Dictation"
        case .listening: "Listening"
        case .quiz: "Quiz"
        case .summary: "Summary"
        }
    }

    /// The verb on the button that finishes the step and moves the rail on.
    static func continueTitle(_ type: LessonStep.StepType) -> String {
        switch type {
        case .theory: "Mark as understood"
        case .examples: "I've read these"
        case .video, .audio: "Done listening"
        case .summary: "Finish lesson"
        case .practice, .exercises, .dictation, .listening, .quiz: "Continue"
        }
    }

    /// Steps whose content is finished by an exercise session rather than a tap.
    static func needsSession(_ type: LessonStep.StepType) -> Bool {
        switch type {
        case .practice, .exercises, .dictation, .listening, .quiz: true
        default: false
        }
    }
}

extension View {
    /// The floating treatment for the step rail and the primary action only.
    ///
    /// Applied after layout modifiers so the material hugs the laid-out frame.
    func floatingGlass() -> some View {
        if #available(iOS 26, *) {
            self.glassEffect()
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}

extension Level {
    /// Label used on pills, chips and section headers in this lane.
    var shortTitle: String {
        switch self {
        case .beginner: "Beginner"
        case .intermediate: "Intermediate"
        case .advanced: "Advanced"
        }
    }
}
