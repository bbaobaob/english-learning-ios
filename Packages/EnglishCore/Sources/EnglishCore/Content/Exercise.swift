import Foundation

/// The grading interaction an exercise uses.
public enum ExerciseKind: String, Codable, Sendable, Hashable, CaseIterable {
    case multipleChoice
    case multiSelect
    case fillInTheBlank
    case dictation
    case listening
    case typeTheAnswer
    case trueFalse
    case matching
    case rearrangeWords
    case sentenceCompletion
    case errorCorrection
    case wordFormation
    case translation
    case reading
    case listeningComprehension
    case grammarCorrection
}

/// One selectable, hintable, or draggable option inside an exercise.
public struct ExerciseItem: Codable, Sendable, Hashable, Identifiable {
    /// Item id, referenced by ``Answer`` values.
    public let id: String
    /// Item label.
    public var text: String?
    /// Whether the item is a correct option; `nil` when the kind does not grade items.
    public var isCorrect: Bool?
    /// Group key for matching and map/diagram labelling.
    public var matchKey: String?

    public init(id: String, text: String? = nil, isCorrect: Bool? = nil, matchKey: String? = nil) {
        self.id = id
        self.text = text
        self.isCorrect = isCorrect
        self.matchKey = matchKey
    }
}

/// The expected answer payload for an exercise.
///
/// Not `Codable` on its own: the case is implied by ``Answer/type``, so
/// ``Answer`` does the encoding in one pass instead of two nested decoders.
public enum AnswerValue: Sendable, Hashable {
    /// Free-text answers, first value is the canonical one.
    case text([String])
    /// Selected item ids.
    case choice([String])
    /// Correct token order.
    case order([String])
    /// Item id to match key.
    case pairs([String: String])
    /// A true/false result.
    case boolean(Bool)
    /// No answer payload.
    case none
}

/// The expected answer to an exercise, discriminated by `type`.
public struct Answer: Codable, Sendable, Hashable, Identifiable {
    /// The `type` discriminator values.
    public enum Kind: String, Codable, Sendable, Hashable, CaseIterable {
        case text
        case choice
        case pairs
        case order
        case boolean
        case none
    }

    /// Which answer shape this is.
    public let type: Kind
    /// The payload matching `type`.
    public let values: AnswerValue

    /// Stable identity derived from the answer payload, for diffing and `ForEach`.
    public var id: String {
        switch values {
        case .text(let list), .choice(let list), .order(let list): "\(type.rawValue):\(list.joined(separator: "|"))"
        case .pairs(let map): "\(type.rawValue):\(map.keys.sorted().map { "\($0)=\(map[$0] ?? "")" }.joined(separator: "|"))"
        case .boolean(let flag): "\(type.rawValue):\(flag)"
        case .none: type.rawValue
        }
    }

    public init(type: Kind, values: AnswerValue) {
        self.type = type
        self.values = values
    }

    /// A free-text answer whose first value is canonical.
    public static func text(_ values: [String]) -> Answer {
        Answer(type: .text, values: .text(values))
    }

    /// A selection of item ids.
    public static func choice(_ ids: [String]) -> Answer {
        Answer(type: .choice, values: .choice(ids))
    }

    /// A token ordering.
    public static func order(_ tokens: [String]) -> Answer {
        Answer(type: .order, values: .order(tokens))
    }

    /// An item-id to match-key mapping.
    public static func pairs(_ map: [String: String]) -> Answer {
        Answer(type: .pairs, values: .pairs(map))
    }

    /// A true/false answer.
    public static func boolean(_ flag: Bool) -> Answer {
        Answer(type: .boolean, values: .boolean(flag))
    }

    /// An empty answer.
    public static var none: Answer {
        Answer(type: .none, values: .none)
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case values
        /// Accepted only as a tolerated alias for ``values`` when decoding a boolean.
        case value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Kind.self, forKey: .type)
        self.type = type
        switch type {
        case .text:
            values = .text(try container.decodeIfPresent([String].self, forKey: .values) ?? [])
        case .choice:
            values = .choice(try container.decodeIfPresent([String].self, forKey: .values) ?? [])
        case .order:
            values = .order(try container.decodeIfPresent([String].self, forKey: .values) ?? [])
        case .pairs:
            values = .pairs(try container.decodeIfPresent([String: String].self, forKey: .values) ?? [:])
        case .boolean:
            values = .boolean(Self.decodeBoolean(from: container))
        case .none:
            values = AnswerValue.none
        }
    }

    /// Decodes a boolean answer tolerantly.
    ///
    /// The authored shape is `{"type": "boolean", "values": true}`. A renamed key
    /// (`value`) and a string or single-element array form are accepted too,
    /// because the alternative failure mode is silent: a strict
    /// `decodeIfPresent(Bool.self, forKey: .values) ?? false` turns every
    /// True/False question into "the answer was False", and a `["true"]` array
    /// throws a type mismatch that removes the whole file — and therefore the
    /// whole topic — from the library without any visible error.
    private static func decodeBoolean(from container: KeyedDecodingContainer<CodingKeys>) -> Bool {
        let truthy = ["true", "1", "yes", "correct"]
        for key in [CodingKeys.values, .value] where container.contains(key) {
            if let flag = try? container.decode(Bool.self, forKey: key) { return flag }
            if let text = try? container.decode(String.self, forKey: key) {
                return truthy.contains(text.trimmingCharacters(in: .whitespaces).lowercased())
            }
            if let list = try? container.decode([String].self, forKey: key), let first = list.first {
                return truthy.contains(first.trimmingCharacters(in: .whitespaces).lowercased())
            }
        }
        return false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        switch values {
        case .text(let list): try container.encode(list, forKey: .values)
        case .choice(let list): try container.encode(list, forKey: .values)
        case .order(let list): try container.encode(list, forKey: .values)
        case .pairs(let map): try container.encode(map, forKey: .values)
        case .boolean(let flag): try container.encode(flag, forKey: .values)
        case .none: try container.encodeNil(forKey: .values)
        }
    }
}

/// A single graded question.
public struct Exercise: Codable, Sendable, Hashable, Identifiable {
    /// Stable id used as the progress foreign key.
    public let id: String
    /// The grading interaction.
    public var kind: ExerciseKind
    /// Owning topic id; required for weak-area stats.
    public var topicID: String
    /// Owning lesson id, when the exercise is inline.
    public var lessonID: String?
    /// Difficulty tier.
    public var difficulty: Level = .beginner
    /// The question text.
    public var prompt: String
    /// Optional instruction override; the UI has sensible defaults per kind.
    public var instruction: String?
    /// Optional audio stimulus.
    public var audio: AudioClip?
    /// Optional video stimulus.
    public var video: VideoClip?
    /// Kind-dependent options, hints, word bank, or tokens.
    public var items: [ExerciseItem] = []
    /// The expected answer.
    public var answer: Answer
    /// Shown after grading.
    public var explanation: String = ""
    /// XP awarded for a correct answer.
    public var xp: Int = 10
    /// Optional Vietnamese prompt, for translation exercises.
    public var translation: String?

    public init(
        id: String,
        kind: ExerciseKind,
        topicID: String,
        lessonID: String? = nil,
        difficulty: Level = .beginner,
        prompt: String,
        instruction: String? = nil,
        audio: AudioClip? = nil,
        video: VideoClip? = nil,
        items: [ExerciseItem] = [],
        answer: Answer = .none,
        explanation: String = "",
        xp: Int = 10,
        translation: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.topicID = topicID
        self.lessonID = lessonID
        self.difficulty = difficulty
        self.prompt = prompt
        self.instruction = instruction
        self.audio = audio
        self.video = video
        self.items = items
        self.answer = answer
        self.explanation = explanation
        self.xp = xp
        self.translation = translation
    }
}
