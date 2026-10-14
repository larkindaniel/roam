import Foundation

/// One rated experience inside a member's category ranking.
struct RankedEntry: Identifiable, Hashable, Codable, Sendable {
    let ratingID: UUID
    let experienceID: UUID
    var name: String
    var locality: String?
    let firstRatedAt: Date

    var id: UUID { ratingID }

    /// Stable within-tie display order: first rated, then UUID.
    static func stableOrder(_ lhs: RankedEntry, _ rhs: RankedEntry) -> Bool {
        if lhs.firstRatedAt != rhs.firstRatedAt { return lhs.firstRatedAt < rhs.firstRatedAt }
        return lhs.ratingID.uuidString.lowercased() < rhs.ratingID.uuidString.lowercased()
    }
}

/// Members that share one score and rank ("Too tough").
struct TieGroup: Hashable, Codable, Sendable {
    var entries: [RankedEntry]

    init(entries: [RankedEntry]) {
        self.entries = entries.sorted(by: RankedEntry.stableOrder)
    }

    /// Deterministic comparison representative: the oldest rating, UUID tie-break.
    var representative: RankedEntry { entries[0] }
}

/// A computed position of one entry in its category.
struct Placement: Hashable, Sendable {
    let entry: RankedEntry
    let sentiment: Sentiment
    let groupIndex: Int
    let groupCount: Int
    let score: Score
    /// Competition rank across all partitions: 1 + number of higher-ranked items.
    let rank: Int
    let groupSize: Int

    var isTied: Bool { groupSize > 1 }
}

/// Ordered tie groups for one member and category, split into sentiment partitions.
struct CategoryRanking: Hashable, Codable, Sendable {
    let category: ExperienceCategory
    var revision: Int
    private(set) var liked: [TieGroup]
    private(set) var fine: [TieGroup]
    private(set) var disliked: [TieGroup]

    init(category: ExperienceCategory, revision: Int = 0, liked: [TieGroup] = [], fine: [TieGroup] = [], disliked: [TieGroup] = []) {
        self.category = category
        self.revision = revision
        self.liked = liked
        self.fine = fine
        self.disliked = disliked
    }

    static func empty(_ category: ExperienceCategory) -> CategoryRanking { CategoryRanking(category: category) }

    func groups(for sentiment: Sentiment) -> [TieGroup] {
        switch sentiment {
        case .liked: return liked
        case .fine: return fine
        case .disliked: return disliked
        }
    }

    mutating func setGroups(_ groups: [TieGroup], for sentiment: Sentiment) {
        let cleaned = groups.filter { !$0.entries.isEmpty }
        switch sentiment {
        case .liked: liked = cleaned
        case .fine: fine = cleaned
        case .disliked: disliked = cleaned
        }
    }

    var entryCount: Int { Sentiment.partitionOrder.reduce(0) { $0 + groups(for: $1).reduce(0) { $0 + $1.entries.count } } }

    var isEmpty: Bool { entryCount == 0 }

    /// Every entry with its score and competition rank, best first.
    func placements() -> [Placement] {
        var result: [Placement] = []
        var higherCount = 0
        for sentiment in Sentiment.partitionOrder {
            let partition = groups(for: sentiment)
            for (index, group) in partition.enumerated() {
                let score = ScoreMath.score(groupIndex: index, groupCount: partition.count, sentiment: sentiment)
                for entry in group.entries {
                    result.append(Placement(entry: entry, sentiment: sentiment, groupIndex: index, groupCount: partition.count,
                                            score: score, rank: higherCount + 1, groupSize: group.entries.count))
                }
                higherCount += group.entries.count
            }
        }
        return result
    }

    func placement(forExperience experienceID: UUID) -> Placement? {
        placements().first { $0.entry.experienceID == experienceID }
    }

    func contains(experienceID: UUID) -> Bool {
        Sentiment.partitionOrder.contains { groups(for: $0).contains { $0.entries.contains { $0.experienceID == experienceID } } }
    }

    /// Removes an experience (rerank or rating removal); empty tie groups disappear.
    func removing(experienceID: UUID) -> CategoryRanking {
        var copy = self
        for sentiment in Sentiment.partitionOrder {
            let updated = groups(for: sentiment).map { group in
                TieGroup(entries: group.entries.filter { $0.experienceID != experienceID })
            }
            copy.setGroups(updated, for: sentiment)
        }
        return copy
    }

    /// Inserts an entry according to a finished insertion outcome.
    func applying(_ outcome: InsertionOutcome, entry: RankedEntry, sentiment: Sentiment) -> CategoryRanking {
        var copy = self
        var partition = groups(for: sentiment)
        switch outcome {
        case .newGroup(let slot, _):
            partition.insert(TieGroup(entries: [entry]), at: min(max(slot, 0), partition.count))
        case .joinGroup(let index):
            partition[index] = TieGroup(entries: partition[index].entries + [entry])
        }
        copy.setGroups(partition, for: sentiment)
        return copy
    }
}

enum ComparisonChoice: String, Codable, Hashable, Sendable, CaseIterable {
    case preferNew = "prefer_new"
    case preferExisting = "prefer_existing"
    case tooTough = "too_tough"
    case skip
}

struct ComparisonAnswer: Codable, Hashable, Sendable {
    let comparedRatingID: UUID
    let choice: ComparisonChoice

    enum CodingKeys: String, CodingKey {
        case comparedRatingID = "compared_rating_id"
        case choice
    }
}

enum InsertionOutcome: Hashable, Codable, Sendable {
    /// Insert a new tie group before the group currently at `slot` (slot == count appends).
    case newGroup(slot: Int, approximate: Bool)
    /// "Too tough": join the shown group and share its score.
    case joinGroup(index: Int)
}

enum InsertionReplayError: Error, Equatable {
    case answerMismatch(step: Int)
    case incomplete
    case extraAnswers
}

/// Binary insertion over tie groups of one sentiment partition (`roam-category-v1`).
struct InsertionSession: Hashable, Sendable {
    let sentiment: Sentiment
    let groups: [TieGroup]
    private(set) var lo: Int
    private(set) var hi: Int
    private(set) var answers: [ComparisonAnswer] = []
    private(set) var outcome: InsertionOutcome?
    private var history: [Checkpoint] = []

    private struct Checkpoint: Hashable, Sendable {
        let lo: Int
        let hi: Int
        let answerCount: Int
        let outcome: InsertionOutcome?
    }

    init(sentiment: Sentiment, groups: [TieGroup]) {
        self.sentiment = sentiment
        self.groups = groups
        self.lo = 0
        self.hi = groups.count
        resolveIfBoundsMet()
    }

    var isComplete: Bool { outcome != nil }
    var canUndo: Bool { !history.isEmpty }

    /// Group currently being compared against, while comparisons remain.
    var currentGroupIndex: Int? { outcome == nil && lo < hi ? (lo + hi) / 2 : nil }

    var currentComparison: RankedEntry? { currentGroupIndex.map { groups[$0].representative } }

    /// Upper bound on remaining questions for progress copy.
    var remainingComparisonsEstimate: Int {
        guard outcome == nil else { return 0 }
        var span = hi - lo
        var steps = 0
        while span > 0 { steps += 1; span /= 2 }
        return steps
    }

    mutating func choose(_ choice: ComparisonChoice) {
        guard outcome == nil, let mid = currentGroupIndex else { return }
        history.append(Checkpoint(lo: lo, hi: hi, answerCount: answers.count, outcome: outcome))
        answers.append(ComparisonAnswer(comparedRatingID: groups[mid].representative.ratingID, choice: choice))
        switch choice {
        case .preferNew:
            hi = mid
            resolveIfBoundsMet()
        case .preferExisting:
            lo = mid + 1
            resolveIfBoundsMet()
        case .tooTough:
            outcome = .joinGroup(index: mid)
        case .skip:
            outcome = .newGroup(slot: (lo + hi) / 2, approximate: true)
        }
    }

    /// Restores the previous uncommitted decision. Disabled before the first decision.
    mutating func undo() {
        guard let checkpoint = history.popLast() else { return }
        lo = checkpoint.lo
        hi = checkpoint.hi
        answers.removeLast(answers.count - checkpoint.answerCount)
        outcome = checkpoint.outcome
    }

    private mutating func resolveIfBoundsMet() {
        if lo >= hi { outcome = .newGroup(slot: lo, approximate: false) }
    }

    /// Server-equivalent validation: replays answers against the current groups and requires
    /// that each answer names the expected representative and that the sequence terminates exactly.
    static func replay(sentiment: Sentiment, groups: [TieGroup], answers: [ComparisonAnswer]) throws -> InsertionOutcome {
        var session = InsertionSession(sentiment: sentiment, groups: groups)
        for (step, answer) in answers.enumerated() {
            guard !session.isComplete else { throw InsertionReplayError.extraAnswers }
            guard session.currentComparison?.ratingID == answer.comparedRatingID else {
                throw InsertionReplayError.answerMismatch(step: step)
            }
            session.choose(answer.choice)
        }
        guard let outcome = session.outcome else { throw InsertionReplayError.incomplete }
        return outcome
    }
}
