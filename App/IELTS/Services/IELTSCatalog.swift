import Foundation
import EnglishCore

// MARK: - View model
//
// `IELTSLesson` in EnglishCore cannot decode the shipped JSON: the files use
// `ExerciseKind` raw values (`typeTheAnswer`, `trueFalse`, `listening`, …) while
// `IELTSQuestion.Kind` only knows the thirteen paper formats, and the lessons carry
// `prompt` / `translation` fields that `IELTSLesson` does not declare. So the whole
// module currently fails to decode and `library.allIELTSModules` comes back empty.
//
// TODO(content-lane): add `prompt`/`translation` to `IELTSLesson` and let `IELTSQuestion.Kind`
// accept the `ExerciseKind` values the content actually uses. These types then disappear
// and `IELTSCatalog.load()` reads from `library.allIELTSModules` instead.
//
// Until then we decode the same bundled files ourselves. Nothing is duplicated in
// content — only in shape.

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
           let digits = match, let value = Int(prompt[digits]) {
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
            } else if !trimmed.isEmpty && bullets.isEmpty {
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
    var speakingQuestions: [String] {
        var text = prompt
        if let start = text.range(of: "Cue card:") { text = String(text[text.startIndex..<start.lowerBound]) }
        var found: [String] = []
        for line in text.split(separator: "\n") {
            var line = String(line)
            // Strip "1. " numbering and a "Hometown: " block label.
            if let match = line.range(of: "^\\s*\\d+\\.\\s*", options: .regularExpression) {
                line.removeSubrange(match)
            }
            if let match = line.range(of: "^[^?:]{1,40}:\\s*", options: .regularExpression) {
                line.removeSubrange(match)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            // A single line can hold several questions.
            for piece in line.split(separator: "?") {
                let question = piece.trimmingCharacters(in: .whitespaces)
                guard !question.isEmpty else { continue }
                found.append(question + "?")
            }
        }
        return found
    }
}

// MARK: - Loading

enum IELTSCatalog {
    /// Every paper, grouped by skill, in the order the files ship.
    static func load() -> [IELTSPaper] {
        var papers: [IELTSPaper] = []
        for url in contentURLs() {
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(ModuleFile.self, from: data) else { continue }
            papers.append(IELTSPaper(
                id: file.id,
                skill: file.skill ?? .listening,
                title: file.title,
                lessons: file.lessons.map(makeLesson)
            ))
        }
        return papers.sorted { lhs, rhs in
            IELTSPaper.skillOrder(lhs.skill) < IELTSPaper.skillOrder(rhs.skill)
        }
    }

    /// Loads once and caches. The content does not change at runtime.
    private static let papers: [IELTSPaper] = load()

    static var all: [IELTSPaper] { papers }

    static func lessons(for skill: IELTSSkill) -> [IELTSPaperLesson] {
        all.filter { $0.skill == skill }.flatMap(\.lessons)
    }

    static func lesson(_ id: String) -> IELTSPaperLesson? {
        all.lazy.flatMap(\.lessons).first { $0.id == id }
    }

    /// The two shipped content files, wherever the resource bundle landed.
    private static func contentURLs() -> [URL] {
        let names = ["ielts-listening-reading", "ielts-writing-speaking"]
        var bundles: [Bundle] = [Bundle.main]
        // EnglishCore ships its resources as `EnglishCore_EnglishCore.bundle`.
        if let url = Bundle.main.url(forResource: "EnglishCore_EnglishCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            bundles.append(bundle)
        }
        var found: [URL] = []
        for name in names {
            for bundle in bundles {
                let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "content")
                    ?? bundle.url(forResource: name, withExtension: "json")
                if let url, !found.contains(url) { found.append(url) }
            }
        }
        return found
    }

    // MARK: Mapping

    private static func makeLesson(_ file: LessonFile) -> IELTSPaperLesson {
        let skill = skill(forLessonID: file.id)
        let paragraphs = (file.items.first?.prompt ?? "")
            .split(separator: "\n\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // A reading passage is the one prompt that is several real paragraphs long;
        // every other first prompt is a form heading or a single statement.
        let passage = paragraphs.count >= 3 ? paragraphs : []

        let questions = numberQuestions(file.makeItems())

        return IELTSPaperLesson(
            id: file.id,
            skill: skill,
            title: file.title,
            band: file.band,
            minutes: file.minutes,
            prompt: file.prompt ?? "",
            translation: file.translation,
            transcript: file.transcript ?? [],
            audio: file.audio.map { clip in
                AudioClip(id: "\(file.id)-audio", kind: clip.kind, text: clip.text,
                          rate: clip.rate, title: file.title)
            },
            items: file.items,
            review: file.review ?? [],
            passage: passage,
            questions: questions
        )
    }

    /// `ielts-l-…`, `ielts-r-…`, `ielts-w-…`, `ielts-s-…`.
    ///
    /// The shipped files put listening *and* reading in one module and writing *and*
    /// speaking in another, so `IELTSModule.skill` only describes the first half. The
    /// id prefix is the only field that actually distinguishes the four papers.
    private static func skill(forLessonID id: String) -> IELTSSkill {
        switch id.split(separator: "-").dropFirst().first.map(String.init) {
        case "r": return .reading
        case "w": return .writing
        case "s": return .speaking
        default: return .listening
        }
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
        case .listening: return "Listening"
        case .reading: return "Reading"
        case .writing: return "Writing"
        case .speaking: return "Speaking"
        }
    }
}

// MARK: - Wire shapes

/// Decoded with `decodeIfPresent` throughout: the shipped files omit `items`,
/// `audio`, `translation` and `explanation` on plenty of questions, and a
/// synthesised decoder would throw `keyNotFound` on every one of them.
private struct ModuleFile: Decodable {
    let id: String
    let title: String
    let skill: IELTSSkill?
    let lessons: [LessonFile]
}

private struct LessonFile: Decodable {
    let id: String
    let title: String
    let band: String?
    let minutes: Int?
    let prompt: String?
    let translation: String?
    let transcript: [String]?
    let audio: AudioFile?
    let items: [QuestionFile]
    let review: [String]?

    enum CodingKeys: String, CodingKey {
        case id, title, band, minutes, prompt, translation, transcript, audio, items, review
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        band = try container.decodeIfPresent(String.self, forKey: .band)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes)
        prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
        transcript = try container.decodeIfPresent([String].self, forKey: .transcript)
        audio = try container.decodeIfPresent(AudioFile.self, forKey: .audio)
        items = try container.decodeIfPresent([QuestionFile].self, forKey: .items) ?? []
        review = try container.decodeIfPresent([String].self, forKey: .review)
    }

    /// Builds the `Exercise` the session engine grades, from the file's wire shape.
    fileprivate func makeItems() -> [Exercise] {
        items.map { $0.exercise(lessonID: id) }
    }
}

private struct AudioFile: Decodable {
    let kind: AudioClipKind
    let text: String?
    let rate: Double?

    enum CodingKeys: String, CodingKey {
        case kind, text, rate
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(AudioClipKind.self, forKey: .kind) ?? .speech
        text = try container.decodeIfPresent(String.self, forKey: .text)
        rate = try container.decodeIfPresent(Double.self, forKey: .rate)
    }
}

private struct QuestionFile: Decodable {
    let id: String
    let kind: ExerciseKind
    let topicID: String
    let difficulty: Level
    let prompt: String
    let instruction: String?
    let audio: AudioFile?
    let items: [ExerciseItem]
    let answer: Answer
    let explanation: String
    let xp: Int
    let translation: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, topicID, difficulty, prompt, instruction, audio, items, answer
        case explanation, xp, translation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try container.decode(ExerciseKind.self, forKey: .kind)
        topicID = try container.decodeIfPresent(String.self, forKey: .topicID) ?? "ielts"
        difficulty = try container.decodeIfPresent(Level.self, forKey: .difficulty) ?? .intermediate
        prompt = try container.decode(String.self, forKey: .prompt)
        instruction = try container.decodeIfPresent(String.self, forKey: .instruction)
        audio = try container.decodeIfPresent(AudioFile.self, forKey: .audio)
        items = try container.decodeIfPresent([ExerciseItem].self, forKey: .items) ?? []
        answer = try container.decodeIfPresent(Answer.self, forKey: .answer) ?? .none
        explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        xp = try container.decodeIfPresent(Int.self, forKey: .xp) ?? 10
        translation = try container.decodeIfPresent(String.self, forKey: .translation)
    }

    fileprivate func exercise(lessonID: String) -> Exercise {
        Exercise(
            id: id,
            kind: kind,
            topicID: topicID,
            lessonID: lessonID,
            difficulty: difficulty,
            prompt: prompt,
            instruction: instruction,
            audio: audio.map { AudioClip(id: "\(id)-audio", kind: $0.kind, text: $0.text, rate: $0.rate) },
            items: items,
            answer: answer,
            explanation: explanation,
            xp: xp,
            translation: translation
        )
    }
}