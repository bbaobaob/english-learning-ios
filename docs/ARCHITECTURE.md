# Architecture Contract (frozen)

> This file is the **single seam** every parallel lane codes against. Do not rename types or
> change signatures here. If a lane needs a change, it reports it instead of editing this file.

## 0. Module layout

```
Packages/EnglishCore/     SPM. Foundation ONLY (no SwiftUI, no SwiftData, no AVFoundation).
                          Portable → unit-tested on Linux + macOS CI in milliseconds.
                          Sources/EnglishCore/Content/     JSON-backed content models + ContentLibrary
                          Sources/EnglishCore/Engine/     AnswerNormalizer, DictationEngine, ExerciseEngine
                          Sources/EnglishCore/Session/    LearnSession (@MainActor @Observable flow driver)
                          Sources/EnglishCore/Review/     SpacedRepetition (SM-2 lite) + ReviewQueueBuilder
                          Sources/EnglishCore/Progress/   StreakCalculator, XPEngine, AchievementEngine
                          Sources/EnglishCore/Media/      protocols only (SpeechPlaying, MediaResolving)
                          Resources/content/*.json       seed content (bundle resource)
                          Tests/EnglishCoreTests/         XCTest-free, uses swift-testing

Packages/EnglishStore/    SPM. SwiftData. Darwin only (iOS 17+, macOS 14+).
                          @Model schemas + ProgressStore facade + persistence tests.

App/                      SwiftUI app target. Depends on both packages.
                          Zero business logic: no grading, no streak math, no date logic,
                          no direct ModelContext access outside Views/Store.
```

Dependency direction: `App → EnglishStore → EnglishCore`. Never the reverse.

**Why split SwiftData out of the core:** SwiftData does not exist on Linux. Keeping it in its own
package means the whole engine surface is provable with `swift test` on a cheap runner.

## 1. Content JSON schema

All content is JSON under `Packages/EnglishCore/Resources/content/`. Loaded by `ContentLibrary`.
Two kinds of files:

- `content.json` — index: course + topic id list (optional; ContentLibrary also globs the dir)
- `topics/<topic-id>.json` — one `Topic`
- `vocabulary.json` — one `VocabularyDeck`
- `ielts.json` — one `IELTSModule`

### Topic file

```jsonc
{
  "id": "tenses",                    // kebab-case, stable, used as SwiftData FK
  "title": "Tenses",
  "kind": "grammar",                 // grammar | alphabet | methods | listening | speaking
                                    // | reading | writing | ielts | vocabulary
  "level": "beginner",               // beginner | intermediate | advanced
  "summary": "One or two sentences shown on the topic card.",
  "icon": "clock",                   // SF Symbol name
  "estimatedMinutes": 25,
  "lessons": [ /* Lesson[] — required, min 1 */ ]
}
```

### Lesson

```jsonc
{
  "id": "tenses-present-simple",
  "title": "Present Simple",
  "summary": "Habits, facts, timetables.",
  "level": "beginner",               // optional, inherited from topic when omitted
  "xp": 40,                          // optional, default 30
  "steps": [ /* LessonStep[] — required, non-empty */ ]
}
```

### LessonStep — a tagged union, `type` selects the shape

Every step has a unique `id` inside its lesson and a `type`.

| `type` | Payload fields | Renders as |
|---|---|---|
| `theory` | `heading`, `body`, `rules: [{title, statement, formula?, examples:[Example]}]` | scrollable theory card |
| `video` | `video: VideoClip` | `VideoLessonView` (play/pause/seek/speed/subtitle/transcript/resume) |
| `audio` | `audio: AudioClip`, `title` | full audio player (play/pause/replay/loop/shuffle/speed/background) |
| `examples` | `examples: [Example]` | tappable example list; tap → speak |
| `practice` | `title?`, `exerciseIDs: [String]` | runs the referenced exercises through `LearnSession` |
| `exercises` | `exercises: [Exercise]` | inline exercises (self-contained) |
| `dictation` | `title?`, `items: [DictationItem]` | Dictation Engine UI |
| `listening` | `title?`, `exercises: [Exercise]` | listening comprehension set (audio required) |
| `quiz` | `title?`, `questions: [Exercise]`, `passPercent: 70` | timed-free quiz with score screen |
| `summary` | `takeaways: [String]`, `nextLessonID?: String` | lesson summary + completion gate |

```jsonc
// Example (used inside theory rules and examples steps)
{ "id": "ex-1", "en": "She works at night.", "vi": "Cô ấy làm việc vào ban đêm.", "note": "no -s with she/he/it in present simple" }
```

### AudioClip

```jsonc
{
  "id": "a-1",
  "kind": "speech",                  // speech (iOS TTS) | file (bundled resource) | remote (URL)
  "text": "The boy is playing football.",   // required when kind == "speech"
  "fileName": null,                  // required when kind == "file"  e.g. "a-1.mp3"
  "url": null,                       // required when kind == "remote"
  "rate": 0.5,                       // AVSpeechUtterance defaultSpeakingRate for speech; 0.3 slow
  "voiceID": null,                   // optional AVSpeechSynthesisVoice override
  "title": null                      // optional, shown in player
}
```

`speech` is the default and requires **no bundled assets** — it is real audio via
`AVSpeechSynthesizer`, works offline, and supports slow replay natively. `file`/`remote` exist so
recorded or licensed audio can be dropped in later **without touching UI**.

### VideoClip

```jsonc
{
  "id": "v-1",
  "title": "Present Simple — form and use",
  "source": { "type": "remote", "url": "https://archive.org/download/<id>/<file>.mp4" },
                                    // type: remote (url required) | bundled (name required) | none
  "transcript": ["Line one.", "Line two."],   // shown in the transcript sheet
  "subtitles": [ { "start": 0.0, "end": 3.2, "text": "Present simple..." } ],
  "durationSeconds": 214.0
}
```

`source.type == "none"` is a legal, complete state: the lesson renders a "no video" placeholder and
the rest of the lesson still works. **No dead or invented URLs may be committed** — a broken link is
worse than `none`.

### Exercise

```jsonc
{
  "id": "ex-tenses-ps-1",
  "kind": "fillInTheBlank",          // see ExerciseKind below
  "topicID": "tenses",               // required — powers weak-area stats
  "lessonID": "tenses-present-simple",
  "difficulty": "beginner",          // beginner | intermediate | advanced
  "prompt": "He ___ (go) to school by bus.",
  "instruction": "Write the correct verb form.",   // optional; UI has sensible defaults per kind
  "audio": { "kind": "speech", "text": "He goes to school by bus." },  // optional
  "video": null,                     // optional VideoClip
  "items": [                         // kind-dependent, see table
    { "id": "a", "text": "every day", "isCorrect": true,  "matchKey": null }
  ],
  "answer": { "type": "text", "values": ["goes"] },
  "explanation": "Third person singular takes -s in the present simple.",
  "xp": 10,
  "translation": null                // optional Vietnamese prompt for translation exercises
}
```

`answer.type` and `items` shape per exercise kind:

| kind | `items` | `answer.type` |
|---|---|---|
| `multipleChoice` | options, one `isCorrect: true` | `choice` → `values: ["<item id>"]` |
| `multiSelect` | options, several `isCorrect: true` | `choice` → values = sorted ids |
| `trueFalse` | one option | `boolean` |
| `fillInTheBlank` | optional hint items | `text` |
| `typeTheAnswer` | — | `text` |
| `dictation` | — | `text` (single canonical sentence) |
| `matching` | options, `matchKey` groups | `pairs` → `values: {"a":"x","b":"y"}` |
| `rearrangeWords` | all tokens, `isCorrect: null` | `order` → `values: ["in","the","morning"]` |
| `sentenceCompletion` | optional word-bank items | `text` |
| `errorCorrection` | the faulty sentence in `prompt` | `text` |
| `wordFormation` | base word in `prompt` | `text` |
| `translation` | — | `text` |
| `reading` / `listeningComprehension` | options | `choice` |
| `grammarCorrection` | faulty sentence in `prompt` | `text` |

`ExerciseKind` (exact cases): `multipleChoice`, `multiSelect`, `fillInTheBlank`, `dictation`,
`listening`, `typeTheAnswer`, `trueFalse`, `matching`, `rearrangeWords`, `sentenceCompletion`,
`errorCorrection`, `wordFormation`, `translation`, `reading`, `listeningComprehension`,
`grammarCorrection`.

### DictationItem

```jsonc
{ "id": "d-1", "audio": { "kind": "speech", "text": "The boy is playing football." },
  "acceptedAnswers": ["The boy is playing football."],   // optional extras; all go through the normalizer
  "hint": "past continuous", "translation": "Cậu bé đang chơi bóng đá.", "xp": 15 }
```

### VocabularyDeck

```jsonc
{
  "id": "vocab-core",
  "title": "Core Vocabulary",
  "words": [ {
    "id": "w-achieve", "word": "achieve", "ipa": "/əˈtʃiːv/", "level": "intermediate",
    "topic": "education", "meaning": "Đạt được, thành tựu",
    "example": "She achieved her goal.", "exampleVI": "Cô ấy đã đạt được mục tiêu.",
    "audio": { "kind": "speech", "text": "achieve" },
    "synonyms": ["accomplish","attain"], "antonyms": ["fail"],
    "collocations": ["achieve a goal","achieve success"],
    "wordFormation": { "noun": "achievement", "verb": "achieve", "adjective": "achievable" }
  } ]
}
```

### IELTSModule

```jsonc
{
  "id": "ielts-listening",
  "skill": "listening",              // listening | reading | writing | speaking
  "title": "IELTS Listening",
  "lessons": [ { "id": "ielts-l-sec1", "title": "Section 1 — Campus Tour",
                 "band": "5.5", "minutes": 12,
                 "transcript": ["Speaker A: ..."],
                 "audio": { "kind": "speech", "text": "Welcome to the campus..." },
                 "items": [ /* IELTSQuestion — same as Exercise but kind from the
                              IELTS set: multipleChoice | matching | formCompletion |
                              noteCompletion | sentenceCompletion | mapLabeling | dictation |
                              trueFalseNotGiven | yesNoNotGiven | matchingHeadings |
                              matchingInformation | summaryCompletion */ ],
                 "review": ["Point 1 the listener should check."] } ]
}
```

`mapLabeling` / `diagramLabeling` reuse `items` + `answer.type == "pairs"`.

## 2. Swift API (exact signatures)

### EnglishCore — Content

```swift
public struct ContentLibrary: Sendable {
    public init(bundle: Bundle) throws
    public init(topics: [Topic], vocabulary: [VocabWord], ielts: [IELTSModule])  // tests
    public var allTopics: [Topic]
    public var allLessons: [Lesson]
    public func topic(_ id: String) -> Topic?
    public func lesson(_ id: String) -> Lesson?
    public func lesson(_ id: String, in topicID: String) -> Lesson?
    public func vocabWord(_ id: String) -> VocabWord?
    public func ieltsLesson(_ id: String) -> IELTSLesson?
    public func nextLesson(after lessonID: String) -> Lesson?
}
```

All content types: `Codable, Sendable, Hashable, Identifiable`. Manual `Codable` for
`LessonStep` / `Answer` tagged unions — one JSON object each, `type` discriminator.

### EnglishCore — Engine

```swift
public struct AnswerNormalizer: Sendable {
    public init()
    public func normalize(_ text: String) -> String        // fold + lowercase + strip punctuation + collapse spaces
    public func tokens(_ text: String) -> [String]
    public func isEquivalent(_ a: String, _ b: String) -> Bool
}

public struct TokenDiff: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case missing, extra, substituted }
    public let id: Int
    public let kind: Kind
    public let index: Int
    public let user: String?
    public let expected: String?
}

public struct DictationResult: Sendable, Equatable {
    public let isCorrect: Bool
    public let accuracy: Double          // 0...1, word-level
    public let diffs: [TokenDiff]
    public let firstErrorIndex: Int?
    public let expected: String
    public var firstErrorSummary: String?   // e.g. "“is play” → should be “is playing”"
}

public struct DictationEngine: Sendable {
    public init(normalizer: AnswerNormalizer = AnswerNormalizer())
    public func evaluate(userInput: String, expected: String, accepted: [String] = []) -> DictationResult
}

public enum UserResponse: Sendable, Equatable {
    case text(String)
    case choice([String])
    case order([String])
    case pairs([String: String])
    case boolean(Bool)
}

public struct ExerciseResult: Sendable, Equatable {
    public let exerciseID: String
    public let isCorrect: Bool
    public let accuracy: Double
    public let correctAnswer: Answer
    public let explanation: String
    public let diffs: [TokenDiff]
    public let xpAwarded: Int
}

public struct ExerciseEngine: Sendable {
    public init(normalizer: AnswerNormalizer = AnswerNormalizer())
    public func check(_ exercise: Exercise, response: UserResponse) -> ExerciseResult
    public func checkDictation(_ exercise: Exercise, userInput: String) -> ExerciseResult
}
```

**Dictation algorithm (normative — implement exactly):**
1. Normalize both sides (case-fold, Unicode NFKD + diacritic strip, drop `.,!?;:()"“”` but keep
   internal `'` in contractions, collapse runs of whitespace, trim).
2. Tokenize on whitespace.
3. If normalized strings are byte-equal → `isCorrect = true`, `accuracy = 1`, no diffs.
4. Otherwise align with a longest-common-subsequence diff. Aligned equal tokens → match.
   Unmatched expected token adjacent to exactly one unmatched user token → `substituted`.
   Unmatched expected with no user token → `missing`. Unmatched user with no expected → `extra`.
   A `missing` immediately followed by an `extra` at the same position → `substituted`
   (this is what turns "is play" into "is playing" with a substitution, not two separate errors).
5. `accuracy = matched / max(expectedCount, userCount)`.
6. `isCorrect = accuracy == 1.0`.
7. Also accept any of `accepted` answers (all normalized) — if one matches, `isCorrect = true`.

Required behaviours (must be covered by tests):
- `"The boy is playing football."` ≡ `"the boy is playing football"` ≡ `"The boy is playing football"` → correct
- `"The boy play football."` → **incorrect** (substitution `play` → `playing`)
- `"The boy is play football."` → **incorrect**, `firstErrorSummary` mentions "is playing"
- Missing word: `"The boy football."` → incorrect, `missing` diff
- Extra word: `"The boy is playing a football."` → incorrect, `extra` diff
- Whitespace/case/punctuation-only differences → correct

### EnglishCore — Review / Progress

```swift
public struct ReviewItem: Sendable, Codable, Identifiable, Hashable {
    public enum Source: String, Codable, Sendable { case exercise, vocabulary, lesson }
    public let id: String                 // "<source>:<refID>"
    public var source: Source
    public var refID: String
    public var topicID: String?
    public var ease: Double               // 2.5 default
    public var intervalDays: Int
    public var repetitions: Int
    public var dueDate: Date
    public var lastResultCorrect: Bool
    public var lapses: Int
    public var createdAt: Date
}

public struct SpacedRepetition: Sendable {
    public enum Grade: Int, Sendable { case again = 0, hard = 3, good = 4, easy = 5 }
    public init(now: @escaping @Sendable () -> Date = Date.init)
    public func schedule(_ item: ReviewItem, grade: Grade) -> ReviewItem
    public func isDue(_ item: ReviewItem, on date: Date) -> Bool
}
```

SM-2 lite: `again` → `interval = 0` (due today), `repetitions = 0`, `ease = max(1.3, ease - 0.2)`,
`lapses += 1`. `good/easy` → `repetitions += 1`;
`interval = repetitions == 1 ? 1 : repetitions == 2 ? 3 : round(previous * ease)`, capped at 180.
`hard` → `interval = max(1, round(previous * 1.2))`, `ease -= 0.15` (floor 1.3). `easy` → `ease += 0.15`.
`mastered` = `intervalDays >= 21 && repetitions >= 4`.

```swift
public struct StreakState: Sendable, Codable, Equatable {
    public var current: Int
    public var longest: Int
    public var lastStudyDay: Date?     // startOfDay in the injected calendar's zone
    public var totalDays: Int
}

public struct StreakCalculator: Sendable {
    public init(calendar: Calendar = .current, now: @escaping @Sendable () -> Date = Date.init)
    public func registeringStudy(on date: Date, state: StreakState) -> StreakState
    public func state(after dates: [Date], from initial: StreakState) -> StreakState
}
```

Rules: same calendar day → unchanged. Previous calendar day → `current += 1`. Any earlier or none
→ `current = 1`. `longest = max(longest, current)`. `totalDays += 1` only on a *new* day.
Never resets to 0 on its own, never mutates on plain app launch.

```swift
public struct XPEngine: Sendable {
    public init(dailyGoal: Int = 50)
    public func award(base: Int, streakDays: Int, accuracy: Double) -> Int   // + streak bonus, 1.5x if accuracy >= 0.9
    public func isDailyGoalMet(xp: Int, goal: Int) -> Bool
}

public struct Achievement: Sendable, Identifiable, Codable { id, title, detail, symbol, threshold, metric }
public struct AchievementEngine: Sendable {
    public static let catalogue: [Achievement]     // ≥12 entries across streak/xp/accuracy/vocab/dictation
    public static func evaluate(stats: LearnerStats, unlocked: Set<String>) -> [Achievement]
}
public struct LearnerStats: Sendable, Codable { totalXP, streak, lessonsCompleted, accuracy, wordsMastered,
                                                 dictationsPassed, reviewsDone, studyMinutes, ieltsCompleted }
```

### EnglishCore — Session (shared flow driver, `@MainActor @Observable`)

Every exercise-bearing screen uses this. Designers do **not** re-implement grading or flow.

```swift
@MainActor @Observable public final class LearnSession {
    public private(set) var items: [SessionItem]      // resolved, ordered
    public var index: Int
    public private(set) var results: [ExerciseResult]
    public private(set) var isFinished: Bool
    public var current: SessionItem?
    public init(items: [SessionItem], onComplete: ((SessionOutcome) -> Void)? = nil)
    public func submit(_ response: UserResponse) -> ExerciseResult
    public func submitDictation(_ text: String) -> ExerciseResult
    public func retry()                                 // re-ask current item, keep earlier results
    public func next() -> Bool                          // false when finished
    public var outcome: SessionOutcome                   // accuracy, xpEarned, wrongIDs
}
public enum SessionItem: Sendable, Identifiable {
    case exercise(Exercise)
    case dictation(DictationItem)
    case theory(LessonStep)          // read-only, counts as a step
    case video(VideoClip)
    case audio(AudioClip)
    case examples([Example])
    case summary(takeaways: [String])
}
```

### EnglishCore — Media protocols (App implements; Core never imports AVFoundation)

```swift
public protocol SpeechPlaying: AnyObject, Sendable {
    @MainActor func speak(_ text: String, rate: Float, completion: (() -> Void)?)
    @MainActor func stop()
    @MainActor var isSpeaking: Bool { get }
}
public protocol MediaResolving: Sendable {
    func localURL(for clip: AudioClip) -> URL?
    func playableURL(for clip: VideoClip) -> URL?
}
public struct AudioClipKind: String, Sendable { case speech, file, remote }
```

### EnglishStore — persistence

```swift
@Model final class UserProfile   { var name; var createdAt; var dailyGoalXP; var onboardedAt }
@Model final class TopicProgress  { var topicID; var accuracy; var exercisesDone; var correctCount; var completedAt }
@Model final class LessonProgress { var lessonID; var topicID; var currentStepIndex; var completed; var lastStepID; var updatedAt }
@Model final class AttemptRecord  { var exerciseID; var topicID; var isCorrect; var accuracy; var userText; var createdAt }
@Model final class ReviewState    { var itemID; var dueDate; var ease; var intervalDays; var repetitions; var lapses; var source; var refID; var topicID }
@Model final class VocabState     { var wordID; var favorite; var reviewCount; var nextReviewDate; var mastery }
@Model final class StudySessionRecord { var startedAt; var endedAt; var minutes; var xpEarned; var kind }
@Model final class StreakRecord   { var current; var longest; var totalDays; var lastStudyDay; var xpToday; var xpGoal }
@Model final class AchievementState { var achievementID; var unlockedAt; var progress }
@Model final class MediaBookmark  { var clipID; var positionSeconds; var updatedAt }
@Model final class NotificationPref { var kind; var enabled; var hour; var minute }

public struct NotificationKind: String, Codable, CaseIterable, Sendable {
    case dailyReminder, vocabularyReview, listeningPractice, ieltsPractice, streakReminder
}

@MainActor public final class ProgressStore {
    public init(container: ModelContainer) throws
    public func topicProgress() -> [String: TopicProgress]
    public func lessonProgress() -> [String: LessonProgress]
    public func resumePoint() -> (lessonID: String, stepIndex: Int)?     // Home "Continue Learning"
    public func recordAttempt(_ r: ExerciseResult, topicID: String, lessonID: String?) 
    public func completeLesson(_ lessonID: String, topicID: String, xp: Int)
    public func registerStudy(minutes: Int, xp: Int, kind: StudyKind) -> StreakRecord
    public func streak() -> StreakRecord
    public func reviewQueue(on date: Date) -> [ReviewItem]
    public func upsertReview(_ item: ReviewItem)
    public func setFavorite(_ wordID: String, _ isFavorite: Bool)
    public func vocabularyStates() -> [String: VocabState]
    public func unlockedAchievements() -> Set<String>
    public func unlock(_ ids: [String])
    public func learnerStats() -> LearnerStats
    public func bookmark(_ clipID: String) -> Double
    public func saveBookmark(_ clipID: String, position: Double)
    public func notificationPrefs() -> [NotificationKind: NotificationPref]
    public func setNotificationPref(_ kind: NotificationKind, enabled: Bool, hour: Int, minute: Int)
}
```

Notification service lives in `App/Services/NotificationService.swift` (wraps
`UNUserNotificationCenter`) and is called from the Profile → Notifications screen. The five kinds
map 1:1 to `NotificationKind`; rescheduling must be idempotent (remove pending, re-add).

## 3. Content rules

- IDs are stable kebab-case and never reused. Progress rows key off them.
- 19 topics total: `alphabet` + 18 grammar topics (`tenses`, `gerund-infinitive`, `modal-verbs`,
  `types-of-words`, `noun`, `verb`, `adjective`, `adverb`, `comparison`, `passive-voice`,
  `reported-speech`, `subject-verb-agreement`, `subjunctive`, `inversion`, `word-formation`,
  `collocations`, `clauses`, `types-of-condition`).
- Grammar topics progress beginner → intermediate → advanced across their lessons.
- Every lesson step set is ordered: theory → video → examples → listening → dictation → practice → quiz → summary.
- `summary` is the only step that can complete a lesson, and only after every other step is visited.
- No invented/placeholder English. No dead URLs. Vietnamese `vi` fields are welcome and encouraged.
- Exercises: minimum 8 per grammar topic, spread over ≥6 distinct `kind`s, including ≥2 dictation.
- No emoji in content text.

## 4. Testing

`swift test` must cover: normalizer, dictation (all seven cases in §2), every `ExerciseKind` check
path, SRS scheduling + due dates, streak (same day / consecutive / gap / longest / total), XP
award, achievement unlock, and — in `EnglishStore` — kill-and-reopen persistence (progress survives,
streak survives, resume point survives, bookmark survives).
