import Foundation

/// Derived forms of a vocabulary word.
public struct WordFormation: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity: the noun, else the verb, else the word form itself.
    public var id: String {
        noun ?? verb ?? adjective ?? adverb ?? ""
    }
    /// Noun form.
    public var noun: String?
    /// Verb form.
    public var verb: String?
    /// Adjective form.
    public var adjective: String?
    /// Adverb form.
    public var adverb: String?

    public init(noun: String? = nil, verb: String? = nil, adjective: String? = nil, adverb: String? = nil) {
        self.noun = noun
        self.verb = verb
        self.adjective = adjective
        self.adverb = adverb
    }
}

/// A vocabulary entry.
public struct VocabWord: Codable, Sendable, Hashable, Identifiable {
    /// Stable id, e.g. `w-achieve`.
    public let id: String
    /// The headword.
    public var word: String
    /// Phonemic transcription.
    public var ipa: String?
    /// Difficulty tier.
    public var level: Level?
    /// Free-form topic tag, e.g. `education`.
    public var topic: String?
    /// Vietnamese meaning.
    public var meaning: String
    /// English example sentence.
    public var example: String?
    /// Vietnamese translation of the example.
    public var exampleVI: String?
    /// Speech clip, usually synthesized from `word`.
    public var audio: AudioClip?
    /// Synonyms.
    public var synonyms: [String] = []
    /// Antonyms.
    public var antonyms: [String] = []
    /// Common collocations.
    public var collocations: [String] = []
    /// Derived forms.
    public var wordFormation: WordFormation?

    public init(
        id: String,
        word: String,
        ipa: String? = nil,
        level: Level? = nil,
        topic: String? = nil,
        meaning: String,
        example: String? = nil,
        exampleVI: String? = nil,
        audio: AudioClip? = nil,
        synonyms: [String] = [],
        antonyms: [String] = [],
        collocations: [String] = [],
        wordFormation: WordFormation? = nil
    ) {
        self.id = id
        self.word = word
        self.ipa = ipa
        self.level = level
        self.topic = topic
        self.meaning = meaning
        self.example = example
        self.exampleVI = exampleVI
        self.audio = audio
        self.synonyms = synonyms
        self.antonyms = antonyms
        self.collocations = collocations
        self.wordFormation = wordFormation
    }
}

/// A named collection of vocabulary words.
public struct VocabDeck: Codable, Sendable, Hashable, Identifiable {
    /// Stable deck id, e.g. `vocab-core`.
    public let id: String
    /// Display title.
    public var title: String
    /// Words in study order.
    public var words: [VocabWord] = []
    /// Optional Vietnamese subtitle shown on the deck header.
    public var subtitle: String?

    public init(id: String, title: String, words: [VocabWord] = [], subtitle: String? = nil) {
        self.id = id
        self.title = title
        self.words = words
        self.subtitle = subtitle
    }
}
