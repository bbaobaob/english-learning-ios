import SwiftUI
import EnglishCore
import EnglishStore

// One word in full: pronunciation, meaning, example, the related-word chips, the
// word family, and the learner's own history with this word.
//
// Every related word chip jumps into the same deck, so the whole screen is a
// navigable neighbourhood rather than a dead-end page.

/// The detail screen for a single vocabulary word.
struct WordDetailView: View {
    @Environment(AppState.self) private var appState

    /// The word being shown.
    let wordID: String

    @State private var addedForms: Set<String> = []
    @State private var path: [VocabRoute] = []

    // MARK: - Data

    private var word: VocabWord? { appState.library.vocabWord(wordID) }

    private var state: VocabState? { appState.store.vocabularyStates()[wordID] }

    /// The persisted schedule, due or not.
    ///
    /// One row, read directly. This used to load the whole vocabulary schedule
    /// and index into it, which also meant asking for a *far-future* date to get
    /// a word that is weeks from being due — see ``VocabSchedule/all(from:)``.
    private var scheduleItem: ReviewItem? {
        appState.store.reviewItem(forWordID: wordID)
    }

    /// Word ids in the deck for every synonym and antonym that actually exists.
    ///
    /// A synonym is a plain English string, not an id, so it is matched against
    /// the deck by looking for a headword. The `lowercased()` keys here are
    /// dictionary lookups for navigation, not answer checking — this screen
    /// never grades anything.
    private var relatedWords: [RelatedWord] {
        guard let word else { return [] }
        let byHeadword = Dictionary(
            appState.library.allVocabulary.map { ($0.word.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var seen: Set<String> = [wordID]
        var result: [RelatedWord] = []
        for synonym in word.synonyms {
            guard let match = byHeadword[synonym.lowercased()], !seen.contains(match.id) else { continue }
            seen.insert(match.id)
            result.append(RelatedWord(title: synonym, wordID: match.id, kind: .synonym))
        }
        for antonym in word.antonyms {
            guard let match = byHeadword[antonym.lowercased()], !seen.contains(match.id) else { continue }
            seen.insert(match.id)
            result.append(RelatedWord(title: antonym, wordID: match.id, kind: .antonym))
        }
        return result
    }

    /// The word family, as speakable rows.
    private var family: [FormRow] {
        guard let formation = word?.wordFormation else { return [] }
        return [
            FormRow(part: "noun", form: formation.noun),
            FormRow(part: "verb", form: formation.verb),
            FormRow(part: "adjective", form: formation.adjective),
            FormRow(part: "adverb", form: formation.adverb)
        ].compactMap { $0 }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let word {
                content(for: word)
            } else {
                EmptyStateView(
                    symbol: "questionmark.square.dashed",
                    title: "Word not found",
                    message: "This word is not in the current deck. It may have been removed from the course. Use the back button to return to the list.",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
        .navigationTitle(word?.word ?? "Word")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: VocabRoute.self) { route in
            switch route {
            case .detail(let nextID):
                WordDetailView(wordID: nextID)
            case .review:
                FlashcardView()
            case .hearType(let wordIDs):
                HearTypeView(words: appState.library.allVocabulary.filter { wordIDs.contains($0.id) }, title: "Hear → Type")
            case .freeHearType:
                HearTypeView(
                    words: Array(appState.library.allVocabulary.shuffled().prefix(VocabPace.freePracticeLimit)),
                    title: "Free practice"
                )
            case .focusedReview(let wordIDs):
                FlashcardView(focusWordIDs: wordIDs)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarFavourite
            }
        }
    }

    private func content(for word: VocabWord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                headword(word)
                meaningBlock(word)
                exampleBlock(word)
                if !relatedWords.isEmpty { relatedBlock }
                collocationsBlock(word)
                if !family.isEmpty { familyBlock }
                historyBlock
                actionBlock
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .vocabAurora()
        .accessibilityAction(named: "Practice this word") { path.append(.focusedReview([wordID])) }
    }

    // MARK: - Headword

    private func headword(_ word: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VocabWordText(text: word.word)
                    .multilineTextAlignment(.leading)
                VocabSpeakButton(
                    text: word.audio?.text ?? word.word,
                    rate: word.audio?.speakingRate ?? 0.5,
                    accessibilityLabel: "Hear \(word.word)"
                )
            }

            if let ipa = word.ipa {
                VocabIPAText(ipa: ipa)
            }

            HStack(spacing: Spacing.sm) {
                if let level = word.level {
                    LevelPill(text: level.rawValue)
                }
                if let topic = word.topic {
                    VocabTagText(text: topic.split(separator: "-").joined(separator: " "))
                }
            }

            HStack(spacing: Spacing.sm) {
                VocabSpeakButton(
                    text: word.word,
                    rate: SpeechRate.example,
                    accessibilityLabel: "Hear \(word.word) slowly",
                    size: 34
                )
                Text("Slow").font(AppFont.body(.footnote))
                    .foregroundStyle(.secondary)
                Spacer()
                VocabMasteryBar(mastery: state?.mastery ?? 0)
            }
        }
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Meaning

    private func meaningBlock(_ word: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Meaning", subtitle: nil, actionTitle: nil, action: nil)
            Text(word.meaning)
                .font(AppFont.display(.title2, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Example

    private func exampleBlock(_ word: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "In a sentence", subtitle: nil, actionTitle: nil, action: nil)
            if let example = word.example {
                // The whole sentence is one button: tapping the text speaks it.
                // A separate speaker button would be a second VoiceOver stop
                // for the same action.
                Button {
                    Haptics.selection()
                    appState.speech.speak(example, rate: SpeechRate.example, completion: nil)
                } label: {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(example)
                                .font(AppFont.display(.body, weight: .regular))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            if let vi = word.exampleVI {
                                Text(vi).font(AppFont.body(.subheadline))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "speaker.wave.2")
                            .foregroundStyle(Color.brand)
                            .padding(.top, 2)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Play the example: \(example)")
                .accessibilityHint(word.exampleVI ?? "")

                HStack(spacing: Spacing.sm) {
                    VocabSpeakButton(
                        text: example,
                        rate: SpeechRate.example,
                        accessibilityLabel: "Hear the example slowly",
                        size: 34
                    )
                    Text("Slow").font(AppFont.body(.footnote))
                        .foregroundStyle(.secondary)
                    Spacer()
                    VocabSpeakButton(
                        text: word.word,
                        rate: SpeechRate.normalSpeed,
                        accessibilityLabel: "Hear the word again",
                        size: 34
                    )
                }
            } else {
                Text("This word has no example sentence in the deck yet.").font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Related words

    private var relatedBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Related words", subtitle: "Tap to jump to the word in the deck", actionTitle: nil, action: nil)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.sm)], alignment: .leading, spacing: Spacing.sm) {
                ForEach(relatedWords) { related in
                    VocabRelatedChip(text: related.title, isCurrent: false) {
                        path.append(.detail(related.wordID))
                    }
                    .accessibilityHint(related.kind == .synonym ? "Synonym" : "Antonym")
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private func collocationsBlock(_ word: VocabWord) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Collocations", subtitle: "How the word is actually used", actionTitle: nil, action: nil)
            if word.collocations.isEmpty {
                Text("No collocations recorded for this word.").font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm)], alignment: .leading, spacing: Spacing.sm) {
                    ForEach(word.collocations, id: \.self) { phrase in
                        VocabRelatedChip(text: phrase, isCurrent: false) {
                            Haptics.selection()
                            appState.speech.speak(phrase, rate: SpeechRate.example, completion: nil)
                        }
                        .accessibilityHint("Speaks the phrase")
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    // MARK: - Word family

    private var familyBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(
                title: "Word family",
                subtitle: "Derived forms you can add to your own vocabulary",
                actionTitle: nil,
                action: nil
            )
            VStack(spacing: Spacing.sm) {
                ForEach(family) { row in
                    HStack(spacing: Spacing.md) {
                        VocabTagText(text: row.part)
                            .frame(width: 84, alignment: .leading)
                        Text(row.form)
                            .font(AppFont.display(.body, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: Spacing.xs)
                        VocabSpeakButton(
                            text: row.form,
                            rate: SpeechRate.example,
                            accessibilityLabel: "Hear the \(row.part) \(row.form)",
                            size: 32
                        )
                        addFormButton(row)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    /// Adds one derived form to the learner's own review queue.
    ///
    /// Creates a real `ReviewItem` through the store so the word behaves like
    /// any other: due immediately, and it will come back after the learner
    /// rates it. The id is namespaced by form so two different words' families
    /// never collide.
    private func addFormButton(_ row: FormRow) -> some View {
        let isAdded = addedForms.contains(row.form)
        return Button {
            Haptics.success()
            let refID = "w-form-\(wordID)-\(row.form.split(separator: "-").joined(separator: "-"))"
            let item = SpacedRepetition.makeItem(source: .vocabulary, refID: refID, topicID: word?.topic, now: Date())
            appState.store.upsertReview(item)
            addedForms.insert(row.form)
        } label: {
            Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isAdded ? Color.success : Color.brand).font(AppFont.body(.title3))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityLabel(isAdded ? "\(row.form) added to your vocabulary" : "Add \(row.form) to your vocabulary")
    }

    // MARK: - History

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Your history", subtitle: "What the scheduler knows about this word", actionTitle: nil, action: nil)

            if let item = scheduleItem {
                VStack(spacing: Spacing.sm) {
                    historyRow(
                        label: "Reviews done",
                        value: "\(state?.reviewCount ?? 0)",
                        symbol: "arrow.triangle.2.circlepath"
                    )
                    historyRow(
                        label: "Last result",
                        value: lastResultText(item),
                        symbol: item.lastResultCorrect ? "checkmark.circle.fill" : "xmark.circle.fill",
                        tint: item.lastResultCorrect ? .success : .danger
                    )
                    historyRow(
                        label: "Next due",
                        value: item.dueDate.formatted(date: .abbreviated, time: .omitted),
                        symbol: "calendar.badge.clock"
                    )
                    historyRow(
                        label: "Current interval",
                        value: item.intervalDays == 0 ? "today" : "\(item.intervalDays) day\(item.intervalDays == 1 ? "" : "s")",
                        symbol: "chart.line.uptrend.xyaxis"
                    )
                    historyRow(
                        label: "Lapses",
                        value: "\(item.lapses)",
                        symbol: "arrow.uturn.backward.circle"
                    )
                }
            } else {
                Text("You have not studied this word yet. Rate it once and it joins your spaced-repetition schedule.").font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    private func lastResultText(_ item: ReviewItem) -> String {
        guard item.repetitions > 0 || item.lapses > 0 else { return "Not graded yet" }
        return item.lastResultCorrect ? "Remembered" : "Forgotten"
    }

    private func historyRow(label: String, value: String, symbol: String, tint: Color = .brand) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(tint).font(AppFont.body(.subheadline))
                .frame(width: 24)
            Text(label).font(AppFont.body(.subheadline))
                .foregroundStyle(.secondary)
            Spacer(minLength: Spacing.sm)
            Text(value).font(AppFont.body(.subheadline, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private var actionBlock: some View {
        VStack(spacing: Spacing.md) {
            PrimaryButton(title: "Practice this word", symbol: "rectangle.stack", isEnabled: true) {
                path.append(.focusedReview([wordID]))
            }
            SecondaryButton(title: "Hear → Type this word", symbol: "ear") {
                path.append(.hearType([wordID]))
            }
            favouriteToggle
        }
    }

    private var toolbarFavourite: some View {
        let isFavourite = state?.favorite ?? false
        return Button {
            toggleFavourite()
        } label: {
            Image(systemName: isFavourite ? "star.fill" : "star")
                .foregroundStyle(isFavourite ? Color.xp : Color.accentColor)
        }
        .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
    }

    private func toggleFavourite() {
        appState.store.setFavorite(wordID, !(state?.favorite ?? false))
        Haptics.selection()
    }

    private var favouriteToggle: some View {
        let isFavourite = state?.favorite ?? false
        return Button {
            toggleFavourite()
        } label: {
            Label(
                isFavourite ? "Remove from favourites" : "Add to favourites",
                systemImage: isFavourite ? "star.fill" : "star"
            ).font(AppFont.body(.subheadline, weight: .semibold))
            .foregroundStyle(isFavourite ? Color.xp : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small value types

/// A synonym or antonym that exists in the deck, with the word id to jump to.
private struct RelatedWord: Identifiable {
    enum Kind {
        case synonym
        case antonym
    }

    let title: String
    let wordID: String
    let kind: Kind

    var id: String { wordID }
}

/// One derived form in the word family.
private struct FormRow: Identifiable {
    let part: String
    let form: String

    var id: String { "\(part)-\(form)" }

    /// Drops the nil cases so the family list never shows an empty row.
    init?(part: String, form: String?) {
        guard let form, !form.isEmpty else { return nil }
        self.part = part
        self.form = form
    }
}
