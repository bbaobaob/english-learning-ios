import SwiftUI
import EnglishCore
import EnglishStore

// The Vocabulary tab root: real numbers, today's review as the primary action,
// a searchable and filterable list of the 180 words, and a weak-words shelf.
//
// Search and filter state lives in `@SceneStorage` so it survives tab switches
// and relaunches — the tab is meant to be left mid-search and come back to.

/// The sort orders offered by the list's toolbar menu.
enum VocabSortOrder: String, CaseIterable, Identifiable {
    case alphabetical
    case mastery
    case dueSoonest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: "A – Z"
        case .mastery: "Weakest first"
        case .dueSoonest: "Due soonest"
        }
    }

    var symbol: String {
        switch self {
        case .alphabetical: "textformat.abc"
        case .mastery: "chart.bar.fill"
        case .dueSoonest: "clock.badge"
        }
    }
}

/// The Vocabulary tab.
struct VocabularyHomeView: View {
    @Environment(AppState.self) private var appState

    @SceneStorage("vocab.search") private var searchText = ""
    @SceneStorage("vocab.level") private var levelRaw = ""
    @SceneStorage("vocab.topic") private var topicRaw = ""
    @SceneStorage("vocab.favouritesOnly") private var favouritesOnly = false
    @SceneStorage("vocab.sort") private var sortRaw = VocabSortOrder.alphabetical.rawValue

    @State private var path: [VocabRoute] = []

    // MARK: - Derived numbers

    private var words: [VocabWord] { appState.library?.allVocabulary ?? [] }

    private var states: [String: VocabState] { appState.store.vocabularyStates() }

    private var schedule: [String: ReviewItem] { VocabSchedule.all(from: appState.store) }

    private var dueToday: [ReviewItem] { VocabSchedule.dueToday(from: appState.store) }

    private var favourites: Int { states.values.filter(\.favorite).count }

    private var mastered: Int { states.values.filter { $0.mastery >= 1 }.count }

    private var weakWords: [ReviewItem] { VocabSchedule.weakWords(from: appState.store, limit: 6) }

    /// The ten words offered when nothing is due and the learner wants to practise anyway.
    private var freePracticeWords: [VocabWord] {
        Array(words.shuffled().prefix(VocabPace.freePracticeLimit))
    }

    private var availableTopics: [String] {
        Array(Set(words.compactMap(\.topic))).sorted()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    statsGrid
                    reviewCard
                    if let banner = libraryBanner { ErrorBanner(message: banner, retry: nil) }
                    weakShelf
                    wordList
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }
            .vocabAurora()
            .scrollDismissesKeyboard(.immediately)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search 180 words, meanings, topics")
            .navigationTitle("Vocabulary")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: VocabRoute.self) { route in
                switch route {
                case .detail(let wordID):
                    WordDetailView(wordID: wordID)
                case .review:
                    FlashcardView()
                case .hearType(let wordIDs):
                    HearTypeView(words: words.filter { wordIDs.contains($0.id) }, title: "Hear → Type")
                case .focusedReview(let wordIDs):
                    FlashcardView(focusWordIDs: wordIDs)
                case .freeHearType:
                    HearTypeView(words: freePracticeWords, title: "Free practice")
                }
            }
            .toolbar { toolbar }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your word bank")
                .font(AppFont.display(.largeTitle, weight: .bold))
                .foregroundStyle(.primary)
            Text("\(words.count) words across \(availableTopics.count) topics, spaced so you meet each one again just before you forget it.").font(AppFont.body(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)], spacing: Spacing.md) {
            StatCard(
                title: "In the deck",
                value: "\(words.count)",
                caption: "words to learn",
                symbol: "text.book.closed.fill",
                tint: .brand
            )
            StatCard(
                title: "Mastered",
                value: "\(mastered)",
                caption: mastered == 1 ? "word learned" : "words learned",
                symbol: "checkmark.seal.fill",
                tint: .success
            )
            StatCard(
                title: "Due today",
                value: "\(dueToday.count)",
                caption: dueToday.isEmpty ? "nothing waiting" : "\(VocabPace.estimate(wordCount: dueToday.count)) to review",
                symbol: "clock.badge.exclamationmark.fill",
                tint: dueToday.isEmpty ? .secondary : .warning
            )
            StatCard(
                title: "Favourites",
                value: "\(favourites)",
                caption: "starred by you",
                symbol: "star.fill",
                tint: .xp
            )
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Today's review

    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Today's review",
                subtitle: dueToday.isEmpty
                    ? "Nothing is due. The scheduler has you covered until tomorrow."
                    : "\(dueToday.count) words · about \(VocabPace.estimate(wordCount: dueToday.count))",
                actionTitle: nil,
                action: nil
            )

            if dueToday.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("You are caught up. Practice something anyway — extra reps on known words keep them strong.").font(AppFont.body(.subheadline))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Spacing.md) {
                        SecondaryButton(title: "Hear → Type", symbol: "ear") {
                            path.append(.freeHearType)
                        }
                        PrimaryButton(title: "Practise 10", symbol: "rectangle.stack", isEnabled: true) {
                            path.append(.review)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .center, spacing: Spacing.md) {
                        Text("\(dueToday.count)")
                            .font(AppFont.display(.largeTitle, weight: .bold))
                            .foregroundStyle(Color.brand)
                            .frame(width: 72, height: 72)
                            .background(Color.brandSoft.opacity(0.5), in: .circle)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("\(dueToday.count) words are waiting")
                                .font(AppFont.display(.title3, weight: .semibold))
                            Text(dueToday.count > 12
                                ? "A long one. Two sittings is fine — the schedule picks up where you left off."
                                : "Short and sharp. Rate each card honestly and the next one lands tomorrow.").font(AppFont.body(.footnote))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    PrimaryButton(title: "Start review", symbol: "play.fill", isEnabled: true) {
                        path.append(.review)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
    }

    /// The content loader's diagnostics, shown only when it found real problems.
    private var libraryBanner: String? {
        let problems = appState.library?.libraryDiagnostics ?? []
        guard !problems.isEmpty else { return nil }
        return problems.prefix(3).joined(separator: " ")
    }

    // MARK: - Weak words

    private var weakShelf: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "Weak words",
                subtitle: weakWords.isEmpty
                    ? "Nothing has slipped yet."
                    : "The words you have forgotten or got wrong most recently.",
                actionTitle: weakWords.isEmpty ? nil : "Review all",
                action: weakWords.isEmpty ? nil : { path.append(.review) }
            )

            if weakWords.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "No weak spots",
                    message: "Once you start rating cards, the words you struggle with gather here so you can drill exactly those.",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.md) {
                        ForEach(weakWords) { item in
                            if let word = appState.library?.vocabWord(item.refID) {
                                weakCard(item, word)
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.bottom, 4)
                }
                .scrollClipDisabled()
            }
        }
    }

    @ViewBuilder
    private func weakCard(_ item: ReviewItem, _ word: VocabWord) -> some View {
        NavigationLink(value: VocabRoute.detail(word.id)) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: item.lapses > 0 ? "arrow.uturn.backward.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(item.lapses > 0 ? Color.warning : Color.danger).font(AppFont.body(.caption))
                    Text(item.lapses > 0 ? "\(item.lapses) lapse\(item.lapses == 1 ? "" : "s")" : "Got wrong").font(AppFont.body(.caption2, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Text(word.word)
                    .font(AppFont.display(.headline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let ipa = word.ipa {
                    VocabIPAText(ipa: ipa, size: 12)
                        .lineLimit(1)
                }
                Text(word.meaning).font(AppFont.body(.caption))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 168, alignment: .leading)
            .padding(Spacing.md)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the word")
    }

    // MARK: - Word list

    private var wordList: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(
                title: "All words",
                subtitle: "\(visibleWords.count) shown of \(words.count)",
                actionTitle: nil,
                action: nil
            )
            .accessibilityAddTraits(.isHeader)

            filterBar
            if visibleWords.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "Nothing matches",
                    message: filtersAreActive
                        ? "No word fits these filters. Clear one to widen the search."
                        : "No word matches that spelling.",
                    actionTitle: filtersAreActive ? "Clear filters" : nil,
                    action: filtersAreActive ? clearFilters : nil
                )
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(visibleWords) { word in
                        NavigationLink(value: VocabRoute.detail(word.id)) {
                            WordRowView(
                                word: word,
                                state: states[word.id],
                                scheduleItem: schedule[word.id],
                                isFavouriteToggle: { toggleFavourite(word) }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filtersAreActive: Bool {
        !searchText.isEmpty || !levelRaw.isEmpty || !topicRaw.isEmpty || favouritesOnly
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                chip("Favourites", isOn: favouritesOnly, symbol: "star.fill") {
                    favouritesOnly.toggle()
                    Haptics.selection()
                }
                Divider().frame(height: 20)
                ForEach(Level.allCases, id: \.self) { level in
                    chip(level.rawValue.capitalized, isOn: levelRaw == level.rawValue) {
                        levelRaw = levelRaw == level.rawValue ? "" : level.rawValue
                        Haptics.selection()
                    }
                }
                Divider().frame(height: 20)
                ForEach(availableTopics, id: \.self) { topic in
                    chip(topic.split(separator: "-").joined(separator: " "), isOn: topicRaw == topic) {
                        topicRaw = topicRaw == topic ? "" : topic
                        Haptics.selection()
                    }
                }
                if filtersAreActive {
                    Button {
                        clearFilters()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill").font(AppFont.body(.footnote, weight: .semibold))
                            .foregroundStyle(Color.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Removes every filter and the search text")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func chip(_ text: String, isOn: Bool, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Chip(text: text, symbol: symbol, isSelected: isOn, action: action)
    }

    /// The filtered, sorted list. 180 words is small enough that this stays a
    /// plain computed pass — no index, no background actor, no lag.
    private var visibleWords: [VocabWord] {
        var result = words

        if !searchText.isEmpty {
            result = result.filter { word in
                word.word.localizedCaseInsensitiveContains(searchText)
                    || word.meaning.localizedCaseInsensitiveContains(searchText)
                    || (word.topic?.localizedCaseInsensitiveContains(searchText) ?? false)
                    || word.synonyms.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
        }
        if !levelRaw.isEmpty {
            result = result.filter { $0.level?.rawValue == levelRaw }
        }
        if !topicRaw.isEmpty {
            result = result.filter { $0.topic == topicRaw }
        }
        if favouritesOnly {
            result = result.filter { states[$0.id]?.favorite == true }
        }

        switch VocabSortOrder(rawValue: sortRaw) ?? .alphabetical {
        case .alphabetical:
            result.sort { $0.word < $1.word }
        case .mastery:
            result.sort { (states[$0.id]?.mastery ?? 0) < (states[$1.id]?.mastery ?? 0) }
        case .dueSoonest:
            // Words with no schedule yet sort last, which is what an empty due
            // date means; `nil` compares greater than any real date.
            result.sort { (schedule[$0.id]?.dueDate ?? .distantFuture) < (schedule[$1.id]?.dueDate ?? .distantFuture) }
        }
        return result
    }

    private func clearFilters() {
        searchText = ""
        levelRaw = ""
        topicRaw = ""
        favouritesOnly = false
        Haptics.selection()
    }

    private func toggleFavourite(_ word: VocabWord) {
        let next = !(states[word.id]?.favorite ?? false)
        appState.store.setFavorite(word.id, next)
        Haptics.selection()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort words", selection: $sortRaw) {
                    ForEach(VocabSortOrder.allCases) { order in
                        Label(order.title, systemImage: order.symbol).tag(order.rawValue)
                    }
                }
                Divider()
                Button {
                    path.append(.freeHearType)
                } label: {
                    Label("Hear → Type drill", systemImage: "ear")
                }
                Button {
                    path.append(.review)
                } label: {
                    Label(dueToday.isEmpty ? "Free practice" : "Today's review", systemImage: "rectangle.stack")
                }
                .disabled(dueToday.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Vocabulary options")
        }
    }
}

// MARK: - Row

/// One word in the list: the word, its IPA, a short gloss, a favourite toggle
/// and a mastery meter.
private struct WordRowView: View {
    let word: VocabWord
    let state: VocabState?
    let scheduleItem: ReviewItem?
    let isFavouriteToggle: () -> Void

    private var isFavourite: Bool { state?.favorite ?? false }

    var body: some View {
        HStack(spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(AppFont.display(.title3, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let ipa = word.ipa {
                    VocabIPAText(ipa: ipa, size: 13)
                        .lineLimit(1)
                }
                Text(word.meaning).font(AppFont.body(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: Spacing.sm)

            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Button(action: isFavouriteToggle) {
                    Image(systemName: isFavourite ? "star.fill" : "star")
                        .foregroundStyle(isFavourite ? Color.xp : Color.secondary).font(AppFont.body(.title3))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavourite ? "Remove \(word.word) from favourites" : "Add \(word.word) to favourites")
                if let scheduleItem {
                    VocabMasteryBar(mastery: mastery)
                    Text(statusText(for: scheduleItem)).font(AppFont.body(.caption2))
                        .foregroundStyle(.secondary)
                } else {
                    VocabMasteryBar(mastery: 0)
                    Text("New").font(AppFont.body(.caption2))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(Spacing.md)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    /// Mastery is stored by the store; a scheduled word with a low value is the
    /// honest source for this bar, and an unscheduled word has none.
    private var mastery: Double { state?.mastery ?? 0 }

    /// A one-word read on the schedule, so a glance says more than a number.
    private func statusText(for item: ReviewItem) -> String {
        if item.lastResultCorrect == false, item.intervalDays == 0 { return "Due now" }
        if item.isMastered { return "Mastered" }
        return "\(item.intervalDays)d"
    }
}
