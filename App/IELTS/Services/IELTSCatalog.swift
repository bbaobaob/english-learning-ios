import Foundation
import EnglishCore

// MARK: - View model
//
// These types are *not* a second copy of the content model. `EnglishCore` owns
// what the content says; these own how a paper is *presented* — printed question
// numbers, the `Questions 1–4` banner each question sits under, a passage split
// into paragraphs. `IELTSCatalog.papers(from:)` derives them from the real
// `IELTSModule` values, so there is one reader of the content and no hand-written
// decoder that can fall out of step with the model.

/// One question, numbered the way the paper numbers it.
struct IELTSPaperQuestion: Identifiable, Hashable {
    let id: String
    /// Printed question number, 1-based in file order.
    let number: Int
    /// The range banner this question sits under, e.g. `1...4`.
    let range: ClosedRange<Int>
    /// The full-range label the content uses, e.g. "Questions 1–4".
    let rangeLabel: String
    let exercise: Exercise
}

/// One lesson, flattened into everything the UI needs.
struct IELTSPaperLesson: Identifiable, Hashable {
    let id: String
    let skill: IELTSSkill
    let title: String
    let band: String?
    let minutes: Int?
    /// The task text (writing) or the examiner's brief (speaking). Empty for listening/reading.
    let prompt: String
    /// The Vietnamese version of `prompt`, when the content has one.
    let translation: String?
    let transcript: [String]
    let audio: AudioClip?
    let items: [Exercise]
    let review: [String]
    /// Reading passages, split into paragraphs. Empty unless this lesson has one.
    let passage: [String]
    /// Numbered questions with their range banner resolved.
    let questions: [IELTSPaperQuestion]

    var questionCount: Int { questions.count }

    var targetMinutes: Int { minutes ?? 20 }

    /// Question groups in printed order, for the navigator.
    var groups: [IELTSPaperGroup] {
        var order: [ClosedRange<Int>] = []
        var buckets: [ClosedRange<Int>: [IELTSPaperQuestion]] = [:]
        for question in questions {
            if buckets[question.range] == nil { order.append(question.range) }
            buckets[question.range, default: []].append(question)
        }
        return order.compactMap { range in
            guard let items = buckets[range], !items.isEmpty else { return nil }
            return IELTSPaperGroup(
                id: "\(range.lowerBound)-\(range.upperBound)",
                label: items.first?.rangeLabel ?? "",
                range: range,
                questions: items
            )
        }
    }

    var isReading: Bool { skill == .reading }
    var hasTranscript: Bool { !transcript.isEmpty }
}

/// A `Questions 1–4` banner and the questions under it.
struct IELTSPaperGroup: Identifiable, Hashable {
    let id: String
    let label: String
    let range: ClosedRange<Int>
    let questions: [IELTSPaperQuestion]
}

/// One paper's lessons.
struct IELTSPaper: Identifiable, Hashable {
    let id: String
    let skill: IELTSSkill
    let title: String
    let lessons: [IELTSPaperLesson]
}

extension IELTSPaperLesson {
    // MARK: Writing

    /// True for an Academic or General Training Task 1.
    var isTask1: Bool { !title.contains("Task 2") }

    var isAcademic: Bool { title.contains("Academic") }

    /// Minimum word count. Parsed from "Write at least 150 words." when the content states it,
    /// otherwise the real exam's default for the task.
    var minimumWords: Int {
        let pattern = "at least\\s+(\\d+)\\s+words"
        if let match = prompt.range(of: pattern, options: .regularExpression),
           let value = Int(prompt[match].split(separator: " ")[2]) {
            return value
        }
        return isTask1 ? 150 : 250
    }

    /// Optional-drill items: the language items that belong to this task.
    var helperExercises: [Exercise] {
        items.filter {
            [.wordFormation, .grammarCorrection, .errorCorrection, .matching].contains($0.kind)
        }
    }

    /// The model answers shipped with the lesson, playable on demand.
    var modelAnswers: [Exercise] { items.filter { $0.kind == .listening && $0.audio != nil } }

    var isCueCard: Bool { prompt.contains("Cue card") }
}

extension IELTSPaperLesson {
    // MARK: Speaking

    enum SpeakingPart: Int, CaseIterable, Hashable {
        case one = 1, two = 2, three = 3
    }

    /// The part, read off the title. Titles are the authored source of truth.
    var speakingPart: SpeakingPart? {
        for part in SpeakingPart.allCases where title.contains("Part \(part.rawValue)") {
            return part
        }
        return nil
    }

    /// The cue card's topic line and its bullets, when this is a long turn.
    var cueCard: (topic: String, bullets: [String])? {
        guard isCueCard else { return nil }
        var body = prompt
        if let start = body.range(of: "Cue card:") {
            body = String(body[start.upperBound...])
        }
        if let end = body.range(of: "Follow-up question:") {
            body = String(body[body.startIndex..<end.lowerBound])
        }
        var topic = ""
        var bullets: [String] = []
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("•") {
                bullets.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if !trimmed.isEmpty && !trimmed.hasSuffix(":") && bullets.isEmpty {
                // "You should say:" is a label, not the topic.
                topic = trimmed
            }
        }
        return bullets.isEmpty ? nil : (topic, bullets)
    }

    /// The follow-up question, when the content gives one.
    var followUpQuestion: String? {
        guard let range = prompt.range(of: "Follow-up question:") else { return nil }
        let text = String(prompt[range.upperBound...])
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.trimmingCharacters(in: .whitespaces)
    }

    /// The examiner's questions, pulled out of the brief. Handles both the numbered
    /// style ("1. What sort of place…") and the topic-block style ("Hometown: What is…?").
    ///
    /// Only sentences that actually end in a question mark are kept, so the paragraph
    /// of instructions above the list never turns into one giant "question".
    var speakingQuestions: [String] {
        var text = prompt
        if let start = text.range(of: "Cue card:") { text = String(text[text.startIndex..<start.lowerBound]) }
        if let end = text.range(of: "Follow-up question:") { text = String(text[..<end.lowerBound]) }

        var found: [String] = []
        // One sentence per match, terminator included.
        guard let regex = try? NSRegularExpression(pattern: "[^.?!\\n]+[.?!]") else { return [] }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var sentence = ns.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sentence.hasSuffix("?") else { continue }
            // Strip "1. " numbering and a "Hometown: " block label.
            if let numbered = sentence.range(of: "^\\s*\\d+\\.\\s*", options: .regularExpression) {
                sentence.removeSubrange(numbered)
            }
            if let labelled = sentence.range(of: "^[^?:]{1,40}:\\s*", options: .regularExpression) {
                sentence.removeSubrange(labelled)
            }
            sentence = sentence.trimmingCharacters(in: .whitespaces)
            guard sentence.count > 4 else { continue }
            found.append(sentence)
        }
        return found
    }
}

// MARK: - Loading

/// Builds the IELTS view model from the real content library.
///
/// **This used to decode the bundled JSON by hand.** It was a workaround for a
/// model that could not read the shipped files: `IELTSQuestion` was a dedicated
/// enum whose `Kind` did not match the `ExerciseKind` values the content
/// actually used, and `IELTSLesson` had no `prompt`/`translation`/`skill`. Both
/// are fixed in `EnglishCore` — `IELTSQuestion` is now `typealias Exercise` and
/// the lesson carries the three missing fields — so `library.allIELTSModules`
/// decodes the real content and every hand-written `Codable` mirror below is
/// gone. One reader of the content, one place it can disagree with the model.
///
/// What survives is the *view model*, not the parsing: the paper shapes carry
/// things `IELTSModule` does not model — printed question numbers, the
/// `Questions 1–4` banners a paper groups them under, a passage split into
/// paragraphs. Those are presentation concerns derived from the content, and
/// deriving them here keeps `EnglishCore` free of exam furniture.
enum IELTSCatalog {

    /// Maps the library's modules into papers, ordered listening → speaking.
    ///
    /// - Parameter modules: Usually `library.allIELTSModules`.
    static func papers(from modules: [IELTSModule]) -> [IELTSPaper] {
        // One module can carry more than one paper — listening and reading ship
        // together — so a module is split by each lesson's own `skill` and the
        // result regrouped. Grouping by lesson (not by module) is what makes
        // "which lessons are in the Reading paper?" answerable.
        var bySkill: [IELTSSkill: [IELTSPaperLesson]] = [:]
        var moduleTitles: [IELTSSkill: String] = [:]

        for module in modules {
            for lesson in module.lessons {
                // A lesson with no skill of its own belongs to the paper the
                // module leads with.
                guard let skill = lesson.skill ?? module.skill else { continue }
                bySkill[skill, default: []].append(makeLesson(lesson, module: module))
                moduleTitles[skill] = module.title
            }
        }

        return IELTSSkill.allCases
            .sorted { skillOrder($0) < skillOrder($1) }
            .compactMap { skill in
                guard let lessons = bySkill[skill], !lessons.isEmpty else { return nil }
                return IELTSPaper(
                    id: "ielts-\(skill.rawValue)",
                    skill: skill,
                    title: moduleTitles[skill] ?? skillName(skill),
                    lessons: lessons
                )
            }
    }

    private static func skillOrder(_ skill: IELTSSkill) -> Int {
        switch skill {
        case .listening: return 0
        case .reading: return 1
        case .writing: return 2
        case .speaking: return 3
        }
    }

    private static func skillName(_ skill: IELTSSkill) -> String {
        switch skill {
        case .listening: "Listening"
        case .reading: "Reading"
        case .writing: "Writing"
        case .speaking: "Speaking"
        }
    }

    // MARK: - Mapping

    private static func makeLesson(_ lesson: IELTSLesson, module: IELTSModule) -> IELTSPaperLesson {
        // A reading passage is the one prompt that is several real paragraphs
        // long; every other first prompt is a form heading or a single statement.
        // The threshold is 3 because a passage paragraph that got merged into 2
        // is a one-line passage, not a real one.
        let paragraphs = (lesson.items.first?.prompt ?? "")
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let passage = paragraphs.count >= 3 ? paragraphs : []

        return IELTSPaperLesson(
            id: lesson.id,
            skill: lesson.skill ?? module.skill ?? .listening,
            title: lesson.title,
            band: lesson.band,
            minutes: lesson.minutes,
            prompt: lesson.prompt ?? "",
            translation: lesson.translation,
            transcript: lesson.transcript,
            audio: lesson.audio,
            items: lesson.items,
            review: lesson.review,
            passage: passage,
            questions: numberQuestions(lesson.items)
        )
    }

    /// Numbers the questions in file order and buckets each one under the
    /// `Questions n–m` banner its own instruction mentions.
    private static func numberQuestions(_ items: [Exercise]) -> [IELTSPaperQuestion] {
        var banners: [ClosedRange<Int>] = []
        for item in items {
            guard let label = item.instruction,
                  let range = Self.range(in: label), !banners.contains(range) else { continue }
            banners.append(range)
        }
        banners.sort { $0.lowerBound < $1.lowerBound }

        return items.enumerated().map { offset, exercise in
            let number = offset + 1
            let banner = banners.first { $0.contains(number) }
            let range = banner ?? number...number
            return IELTSPaperQuestion(
                id: exercise.id,
                number: number,
                range: range,
                rangeLabel: banner.map { "Questions \($0.lowerBound)–\($0.upperBound)" } ?? "Question \(number)",
                exercise: exercise
            )
        }
    }

    /// First `Questions 3–4` / `Question 3–4` in an instruction. Content uses an en dash.
    private static func range(in text: String) -> ClosedRange<Int>? {
        let pattern = "Questions?\\s+(\\d+)\\s*[–\\-—]\\s*(\\d+)"
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let numbers = text[match].components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard numbers.count == 2, numbers[0] <= numbers[1] else { return nil }
        return numbers[0]...numbers[1]
    }
}

extension IELTSPaper {
    static func skillOrder(_ skill: IELTSSkill) -> Int {
        switch skill {
        case .listening: return 0
        case .reading: return 1
        case .writing: return 2
        case .speaking: return 3
        }
    }
}

extension IELTSPaperLesson {
    /// Display name for a skill, used in headings and accessibility labels.
    static func skillName(_ skill: IELTSSkill) -> String {
        switch skill {
        case .listening: "Listening"
        case .reading: "Reading"
        case .writing: "Writing"
        case .speaking: "Speaking"
        }
    }
}