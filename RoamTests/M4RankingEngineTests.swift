import Foundation
import XCTest
@testable import Roam

private struct RankingGoldenEntry: Decodable {
    let ratingID: UUID
    let experienceID: UUID
    let name: String
    let firstRatedAtSeconds: Double

    var entry: RankedEntry {
        RankedEntry(ratingID: ratingID, experienceID: experienceID, name: name, locality: "Golden city",
                    firstRatedAt: Date(timeIntervalSince1970: firstRatedAtSeconds))
    }
}

private struct RankingGoldenGroups: Decodable {
    let liked: [[RankingGoldenEntry]]
    let fine: [[RankingGoldenEntry]]
    let disliked: [[RankingGoldenEntry]]

    func ranking(_ category: ExperienceCategory) -> CategoryRanking {
        CategoryRanking(category: category, liked: liked.map { TieGroup(entries: $0.map(\.entry)) },
                        fine: fine.map { TieGroup(entries: $0.map(\.entry)) },
                        disliked: disliked.map { TieGroup(entries: $0.map(\.entry)) })
    }
}

private struct RankingGoldenPlacement: Decodable, Equatable {
    let ratingID: UUID
    let sentiment: Sentiment
    let scoreTenths: Int
    let rank: Int
    let groupSize: Int

    init(_ placement: Placement) {
        ratingID = placement.entry.ratingID
        sentiment = placement.sentiment
        scoreTenths = placement.score.tenths
        rank = placement.rank
        groupSize = placement.groupSize
    }
}

private enum RankingGoldenError: Error { case unknownOutcome, unknownReplayError }

private struct RankingGoldenOutcome: Decodable {
    let kind: String
    let position: Int
    let approximate: Bool

    func outcome() throws -> InsertionOutcome {
        switch kind {
        case "new_group": return .newGroup(slot: position, approximate: approximate)
        case "join_group": return .joinGroup(index: position)
        default: throw RankingGoldenError.unknownOutcome
        }
    }
}

private struct RankingScoreGolden: Decodable {
    let name: String
    let category: ExperienceCategory
    let groups: RankingGoldenGroups
    let expectedPlacements: [RankingGoldenPlacement]
}

private struct RankingInsertionGolden: Decodable {
    let name: String
    let category: ExperienceCategory
    let sentiment: Sentiment
    let groups: RankingGoldenGroups
    let newEntry: RankingGoldenEntry
    let removingExperienceID: UUID?
    let answers: [ComparisonAnswer]
    let expectedOutcome: RankingGoldenOutcome
    let expectedPlacements: [RankingGoldenPlacement]
}

private struct RankingRejectionGolden: Decodable {
    let name: String
    let sentiment: Sentiment
    let groups: [[RankingGoldenEntry]]
    let answers: [ComparisonAnswer]
    let expectedError: String
    let expectedStep: Int?

    func replayError() throws -> InsertionReplayError {
        switch expectedError {
        case "incomplete": return .incomplete
        case "extra_answers": return .extraAnswers
        case "answer_mismatch": return .answerMismatch(step: try XCTUnwrap(expectedStep))
        default: throw RankingGoldenError.unknownReplayError
        }
    }
}

private struct RankingGoldenDocument: Decodable {
    let schemaVersion: Int
    let formulaVersion: String
    let scoringCases: [RankingScoreGolden]
    let insertionCases: [RankingInsertionGolden]
    let rejectionCases: [RankingRejectionGolden]
}

/// M4 coverage of the pure engine and the same stable inputs used by server parity checks.
final class M4RankingEngineTests: XCTestCase {
    private func entry(_ index: Int, firstRatedAt: Double? = nil) -> RankedEntry {
        RankedEntry(ratingID: UUID(uuidString: String(format: "30000000-0000-4000-8000-%012d", index))!,
                    experienceID: UUID(uuidString: String(format: "40000000-0000-4000-8000-%012d", index))!,
                    name: "Place \(index)", locality: "Test city",
                    firstRatedAt: Date(timeIntervalSince1970: firstRatedAt ?? Double(index)))
    }

    private func groups(_ count: Int) -> [TieGroup] {
        (0..<count).map { TieGroup(entries: [entry($0 + 1)]) }
    }

    private func goldens() throws -> RankingGoldenDocument {
        let url = try XCTUnwrap(Bundle(for: M4RankingEngineTests.self).url(forResource: "m4-ranking-golden", withExtension: "json"),
                                "The shared golden JSON must be a RoamTests resource")
        let document = try JSONDecoder().decode(RankingGoldenDocument.self, from: Data(contentsOf: url))
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertEqual(document.formulaVersion, ScoreMath.formulaVersion)
        XCTAssertFalse(document.scoringCases.isEmpty)
        XCTAssertFalse(document.insertionCases.isEmpty)
        XCTAssertFalse(document.rejectionCases.isEmpty)
        return document
    }

    func testSharedScoringGoldensMatchScoresCompetitionRanksAndStableTieOrder() throws {
        for fixture in try goldens().scoringCases {
            let ranking = fixture.groups.ranking(fixture.category)
            XCTAssertEqual(ranking.placements().map(RankingGoldenPlacement.init), fixture.expectedPlacements, fixture.name)
            XCTAssertEqual(ranking.entryCount, fixture.expectedPlacements.count, fixture.name)
        }
    }

    func testSharedInsertionGoldensReplayThenApplyIncludingRerankAndApproximateSkip() throws {
        for fixture in try goldens().insertionCases {
            let original = fixture.groups.ranking(fixture.category)
            let base = fixture.removingExperienceID.map { original.removing(experienceID: $0) } ?? original
            let outcome = try InsertionSession.replay(sentiment: fixture.sentiment, groups: base.groups(for: fixture.sentiment), answers: fixture.answers)
            XCTAssertEqual(outcome, try fixture.expectedOutcome.outcome(), fixture.name)
            let updated = base.applying(outcome, entry: fixture.newEntry.entry, sentiment: fixture.sentiment)
            XCTAssertEqual(updated.placements().map(RankingGoldenPlacement.init), fixture.expectedPlacements, fixture.name)
            XCTAssertEqual(updated.placements().filter { $0.entry.experienceID == fixture.newEntry.experienceID }.count, 1, fixture.name)
            XCTAssertEqual(updated.category, fixture.category)
            if let removed = fixture.removingExperienceID {
                XCTAssertTrue(original.contains(experienceID: removed), "Draft rerank must leave the original value intact: \(fixture.name)")
                XCTAssertFalse(base.contains(experienceID: removed), "Old item must be absent before comparisons: \(fixture.name)")
                XCTAssertFalse(fixture.answers.contains { $0.comparedRatingID == fixture.newEntry.ratingID }, fixture.name)
            }
        }
    }

    func testSharedReplayRejectionsIdentifyMismatchIncompleteAndExtraAnswers() throws {
        for fixture in try goldens().rejectionCases {
            let expected = try fixture.replayError()
            let input = fixture.groups.map { TieGroup(entries: $0.map(\.entry)) }
            XCTAssertThrowsError(try InsertionSession.replay(sentiment: fixture.sentiment, groups: input, answers: fixture.answers), fixture.name) {
                XCTAssertEqual($0 as? InsertionReplayError, expected, fixture.name)
            }
        }
    }

    func testEveryCategoryAndSentimentCanPlaceItsFirstItemWithoutAComparison() throws {
        let firstScores: [Sentiment: Int] = [.liked: 84, .fine: 50, .disliked: 17]
        for (categoryIndex, category) in ExperienceCategory.allCases.enumerated() {
            for (sentimentIndex, sentiment) in Sentiment.allCases.enumerated() {
                let original = CategoryRanking.empty(category)
                var session = InsertionSession(sentiment: sentiment, groups: original.groups(for: sentiment))
                XCTAssertTrue(session.isComplete)
                XCTAssertNil(session.currentComparison)
                XCTAssertNil(session.currentGroupIndex)
                XCTAssertFalse(session.canUndo)
                XCTAssertEqual(session.remainingComparisonsEstimate, 0)
                session.choose(.tooTough)
                session.undo()
                XCTAssertTrue(session.answers.isEmpty, "No phantom comparison for an empty partition")
                let outcome = try XCTUnwrap(session.outcome)
                let updated = original.applying(outcome, entry: entry(categoryIndex * 3 + sentimentIndex + 1), sentiment: sentiment)
                let result = try XCTUnwrap(updated.placements().first)
                XCTAssertEqual(result.score.tenths, firstScores[sentiment])
                XCTAssertEqual(result.rank, 1)
                XCTAssertEqual(result.groupSize, 1)
                XCTAssertEqual(updated.category, category)
                XCTAssertTrue(original.isEmpty)
            }
        }
    }

    func testEmptySelectedPartitionNeedsNoComparisonEvenWithOtherSentimentsRanked() throws {
        let original = CategoryRanking(category: .culture, liked: [TieGroup(entries: [entry(1), entry(2)])], fine: [TieGroup(entries: [entry(3)])])
        let new = entry(10)
        let session = InsertionSession(sentiment: .disliked, groups: original.groups(for: .disliked))
        XCTAssertTrue(session.isComplete)
        let updated = original.applying(try XCTUnwrap(session.outcome), entry: new, sentiment: .disliked)
        let result = try XCTUnwrap(updated.placement(forExperience: new.experienceID))
        XCTAssertEqual(result.score.tenths, 17)
        XCTAssertEqual(result.rank, 4, "Other partitions affect rank, never the selected partition's comparisons or score")
        XCTAssertEqual(updated.groups(for: .liked), original.groups(for: .liked))
        XCTAssertEqual(updated.groups(for: .fine), original.groups(for: .fine))
    }

    func testBinaryInsertionFindsEverySlotWithShrinkingBoundsAndFiniteQuestions() throws {
        // Exhaust all insertion slots for small and large ordered partitions, not random paths.
        for count in [0, 1, 2, 3, 4, 7, 8, 16, 31, 64, 255, 1_024] {
            let input = groups(count)
            var maximumQuestions = 0
            var distinguishableSlots = 1
            while distinguishableSlots < count + 1 { distinguishableSlots *= 2; maximumQuestions += 1 }
            for sentiment in Sentiment.allCases {
                for expectedSlot in 0...count {
                    var session = InsertionSession(sentiment: sentiment, groups: input)
                    let originalEstimate = session.remainingComparisonsEstimate
                    var steps = 0
                    while !session.isComplete && steps <= maximumQuestions {
                        let lo = session.lo, hi = session.hi
                        let middle = try XCTUnwrap(session.currentGroupIndex)
                        XCTAssertTrue((lo..<hi).contains(middle))
                        XCTAssertEqual(session.currentComparison?.ratingID, input[middle].representative.ratingID)
                        session.choose(expectedSlot <= middle ? .preferNew : .preferExisting)
                        XCTAssertGreaterThanOrEqual(session.lo, 0)
                        XCTAssertLessThanOrEqual(session.hi, count)
                        XCTAssertLessThanOrEqual(session.lo, session.hi)
                        XCTAssertLessThan(session.hi - session.lo, hi - lo)
                        XCTAssertTrue(session.lo <= expectedSlot && expectedSlot <= session.hi)
                        steps += 1
                    }
                    XCTAssertTrue(session.isComplete, "count \(count), slot \(expectedSlot), \(sentiment)")
                    XCTAssertLessThanOrEqual(steps, maximumQuestions)
                    XCTAssertLessThanOrEqual(steps, originalEstimate)
                    XCTAssertEqual(session.outcome, .newGroup(slot: expectedSlot, approximate: false))
                    XCTAssertEqual(try InsertionSession.replay(sentiment: sentiment, groups: input, answers: session.answers), session.outcome)
                }
            }
        }
    }

    func testSkipAfterNarrowingUsesRemainingMidpointAndCreatesANewGroup() throws {
        let original = CategoryRanking(category: .outdoors, liked: groups(7))
        var session = InsertionSession(sentiment: .liked, groups: original.liked)
        session.choose(.preferExisting) // [4, 7]
        session.choose(.preferNew) // [4, 5]
        XCTAssertEqual(session.lo, 4)
        XCTAssertEqual(session.hi, 5)
        session.choose(.skip)
        XCTAssertEqual(session.outcome, .newGroup(slot: 4, approximate: true))
        let new = entry(50)
        let updated = original.applying(try XCTUnwrap(session.outcome), entry: new, sentiment: .liked)
        XCTAssertEqual(updated.liked.count, 8)
        XCTAssertEqual(updated.liked[4].entries.map(\.ratingID), [new.ratingID])
        XCTAssertEqual(updated.placement(forExperience: new.experienceID)?.groupSize, 1, "Skip is not a tie")
        let completed = session
        session.choose(.preferNew)
        XCTAssertEqual(session, completed, "Completion cannot record extra client decisions")
    }

    func testUndoRestoresEveryPriorBoundsAnswersAndCompletionState() {
        var session = InsertionSession(sentiment: .liked, groups: groups(7))
        let start = session
        session.undo()
        XCTAssertEqual(session, start)
        session.choose(.preferExisting)
        let first = session
        session.choose(.preferNew)
        let second = session
        session.choose(.skip)
        XCTAssertTrue(session.isComplete)
        session.undo()
        XCTAssertEqual(session, second)
        session.choose(.tooTough)
        XCTAssertTrue(session.isComplete)
        session.undo()
        XCTAssertEqual(session, second)
        session.undo()
        XCTAssertEqual(session, first)
        session.undo()
        XCTAssertEqual(session, start)
        XCTAssertFalse(session.canUndo)
        XCTAssertTrue(session.answers.isEmpty)
    }

    func testUndoOfNormalCompletionRestoresTheComparisonForADifferentChoice() throws {
        var session = InsertionSession(sentiment: .fine, groups: groups(1))
        let start = session
        session.choose(.preferNew)
        XCTAssertEqual(session.outcome, .newGroup(slot: 0, approximate: false))
        session.undo()
        XCTAssertEqual(session, start)
        session.choose(.preferExisting)
        XCTAssertEqual(session.outcome, .newGroup(slot: 1, approximate: false))
        XCTAssertEqual(session.answers.map(\.choice), [.preferExisting])
        XCTAssertEqual(try InsertionSession.replay(sentiment: .fine, groups: session.groups, answers: session.answers), session.outcome)
    }

    func testRepeatedTooToughIsTransitiveAndScoresDependOnGroupsNotMembers() throws {
        var ranking = CategoryRanking(category: .activities, liked: [TieGroup(entries: [entry(1)])])
        for index in 2...32 {
            let old = ranking
            var session = InsertionSession(sentiment: .liked, groups: ranking.liked)
            XCTAssertEqual(session.currentComparison?.ratingID, entry(1).ratingID)
            session.choose(.tooTough)
            ranking = ranking.applying(try XCTUnwrap(session.outcome), entry: entry(index), sentiment: .liked)
            XCTAssertEqual(old.entryCount, index - 1, "The draft's original ranking is a value, not mutated storage")
            XCTAssertEqual(ranking.liked.count, 1)
            XCTAssertTrue(ranking.placements().allSatisfy { $0.score.tenths == 84 && $0.rank == 1 && $0.groupSize == index })
        }
        let updated = ranking.applying(.newGroup(slot: 1, approximate: false), entry: entry(99), sentiment: .liked)
        XCTAssertTrue(updated.placements().prefix(32).allSatisfy { $0.score.tenths == 100 && $0.rank == 1 })
        XCTAssertEqual(updated.placements().last?.score.tenths, 67)
        XCTAssertEqual(updated.placements().last?.rank, 33)
    }

    func testLargeTieUsesOldestTimestampThenUUIDAndOneComparison() throws {
        let entries = (1...1_024).map { entry($0, firstRatedAt: $0 % 2 == 0 ? 10 : 20) }
        let group = TieGroup(entries: Array(entries.reversed()))
        XCTAssertEqual(group.representative.ratingID, entry(2).ratingID)
        XCTAssertEqual(group.entries.prefix(3).map(\.ratingID), [entry(2).ratingID, entry(4).ratingID, entry(6).ratingID])
        var session = InsertionSession(sentiment: .liked, groups: [group])
        XCTAssertEqual(session.remainingComparisonsEstimate, 1)
        session.choose(.tooTough)
        let ranking = CategoryRanking(category: .stays, liked: [group])
            .applying(try XCTUnwrap(session.outcome), entry: entry(2_000, firstRatedAt: 0), sentiment: .liked)
        XCTAssertEqual(ranking.liked[0].representative.ratingID, entry(2_000).ratingID)
        XCTAssertTrue(ranking.placements().allSatisfy { $0.score.tenths == 84 && $0.rank == 1 && $0.groupSize == 1_025 })
        XCTAssertEqual(session.answers.count, 1)
    }

    func testRerankExcludesTheOldItemPreservesIdentityAndLeavesOriginalUntilCommit() throws {
        let old = entry(1)
        let original = CategoryRanking(category: .foodDrink, revision: 12,
                                       liked: [TieGroup(entries: [old, entry(2)]), TieGroup(entries: [entry(3)])],
                                       fine: [TieGroup(entries: [entry(4)])])
        let base = original.removing(experienceID: old.experienceID)
        XCTAssertFalse(base.contains(experienceID: old.experienceID))
        XCTAssertEqual(base.liked[0].representative.ratingID, entry(2).ratingID)
        XCTAssertEqual(original.entryCount, 4)
        XCTAssertEqual(original.placement(forExperience: old.experienceID)?.score.tenths, 100)
        let session = InsertionSession(sentiment: .disliked, groups: base.disliked)
        XCTAssertTrue(session.isComplete)
        let updated = base.applying(try XCTUnwrap(session.outcome), entry: old, sentiment: .disliked)
        XCTAssertEqual(updated.entryCount, 4)
        let placed = try XCTUnwrap(updated.placement(forExperience: old.experienceID))
        XCTAssertEqual(placed.entry.ratingID, old.ratingID)
        XCTAssertEqual(placed.entry.firstRatedAt, old.firstRatedAt)
        XCTAssertEqual(placed.sentiment, .disliked)
        XCTAssertEqual(placed.score.tenths, 17)
        XCTAssertEqual(placed.rank, 4)
        XCTAssertEqual(updated.revision, 12, "Only the acknowledged service transaction increments the revision")
        XCTAssertEqual(original.groups(for: .disliked), [])
    }

    func testRemovingTieMembersAndLastGroupReflowsOnlyTheSelectedCategory() {
        var rankings = Dictionary(uniqueKeysWithValues: ExperienceCategory.allCases.map { category in
            (category, CategoryRanking(category: category, liked: [TieGroup(entries: [entry(1), entry(2)]), TieGroup(entries: [entry(3)])]))
        })
        let originals = rankings
        rankings[.outdoors] = rankings[.outdoors]?.removing(experienceID: entry(1).experienceID)
        XCTAssertEqual(rankings[.outdoors]?.placements().map(\.rank), [1, 2])
        XCTAssertEqual(rankings[.outdoors]?.placements().map { $0.score.tenths }, [100, 67])
        rankings[.outdoors] = rankings[.outdoors]?.removing(experienceID: entry(2).experienceID)
        XCTAssertEqual(rankings[.outdoors]?.liked.count, 1)
        XCTAssertEqual(rankings[.outdoors]?.placements().map { $0.score.tenths }, [84])
        for category in ExperienceCategory.allCases where category != .outdoors {
            XCTAssertEqual(rankings[category], originals[category], "Other categories must retain their groups, scores and revision")
        }
    }

    func testDecodedGroupsCannotChangeTheDeterministicRepresentativeOrCreateEmptyComparisons() throws {
        var unsorted = TieGroup(entries: [entry(2, firstRatedAt: 10), entry(1, firstRatedAt: 10), entry(3, firstRatedAt: 0)])
        unsorted.entries.reverse()
        let decodedGroup = try JSONDecoder().decode(TieGroup.self, from: JSONEncoder().encode(unsorted))
        XCTAssertEqual(decodedGroup.entries.map(\.ratingID), [entry(3).ratingID, entry(1).ratingID, entry(2).ratingID])
        let original = CategoryRanking(category: .culture, revision: 4, liked: [decodedGroup])
        var document = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var wireGroups = try XCTUnwrap(document["liked"] as? [[String: Any]])
        wireGroups.insert(["entries": []], at: 0)
        document["liked"] = wireGroups
        let decoded = try JSONDecoder().decode(CategoryRanking.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertEqual(decoded, original)
        let session = InsertionSession(sentiment: .liked, groups: [TieGroup(entries: []), decodedGroup])
        XCTAssertEqual(session.hi, 1)
        XCTAssertEqual(session.currentComparison?.ratingID, entry(3).ratingID)
        XCTAssertTrue(InsertionSession(sentiment: .liked, groups: [TieGroup(entries: [])]).isComplete)
    }

    func testScoresMatchIndependentDecimalFormulaAcrossSmallAndLargeGroupCounts() throws {
        let bands: [(Sentiment, Int, Int)] = [(.liked, 67, 100), (.fine, 34, 66), (.disliked, 0, 33)]
        for (sentiment, low, high) in bands {
            for count in Array(1...64) + [127, 256, 1_025] {
                var previous = 101
                for index in 0..<count {
                    let actual = ScoreMath.score(groupIndex: index, groupCount: count, sentiment: sentiment)
                    var raw = count == 1 ? Decimal(high + low) / 2
                        : Decimal(high) - Decimal(index) * Decimal(high - low) / Decimal(count - 1)
                    var expected = Decimal()
                    NSDecimalRound(&expected, &raw, 0, .plain)
                    XCTAssertEqual(actual.tenths, NSDecimalNumber(decimal: expected).intValue)
                    XCTAssertTrue((low...high).contains(actual.tenths))
                    XCTAssertLessThanOrEqual(actual.tenths, previous)
                    previous = actual.tenths
                }
                if count > 1 {
                    XCTAssertEqual(ScoreMath.score(groupIndex: 0, groupCount: count, sentiment: sentiment).tenths, high)
                    XCTAssertEqual(ScoreMath.score(groupIndex: count - 1, groupCount: count, sentiment: sentiment).tenths, low)
                }
            }
        }
    }

    func testDistinctGroupsWithEqualRoundedScoresKeepDistinctRanks() {
        let ranking = CategoryRanking(category: .nightlife, liked: groups(100))
        let placements = ranking.placements()
        XCTAssertEqual(placements[0].score.tenths, 100)
        XCTAssertEqual(placements[1].score.tenths, 100)
        XCTAssertEqual(placements[0].rank, 1)
        XCTAssertEqual(placements[1].rank, 2)
        XCTAssertEqual(placements[0].groupSize, 1)
        XCTAssertEqual(placements[1].groupSize, 1, "Display rounding does not create a Too tough relationship")
    }

    func testScoreParsingAndMeanUseHalfUpIncludingZeroAndBandMidpoints() throws {
        for (raw, expected) in [("0.05", 1), ("1.65", 17), ("5.05", 51), ("8.35", 84), ("9.95", 100)] {
            XCTAssertEqual(Score(decimal: try XCTUnwrap(Decimal(string: raw)))?.tenths, expected, raw)
        }
        XCTAssertEqual(ScoreMath.mean(of: [Score(tenths: 0), Score(tenths: 1)])?.tenths, 1)
        XCTAssertEqual(ScoreMath.mean(of: [Score(tenths: 100), Score(tenths: 67)])?.tenths, 84)
        XCTAssertEqual(ScoreMath.mean(of: [Score(tenths: 0)])?.formattedOutOf10, "0.0", "A real zero score is not missing")
        XCTAssertNil(ScoreMath.mean(of: []))
    }

    func testScoresRoundTripEveryTenthAndRejectRawOutOfRangeOrNonNumbers() throws {
        for tenths in 0...100 {
            let score = Score(tenths: tenths)
            let encoded = try JSONEncoder().encode(score)
            XCTAssertEqual(try JSONDecoder().decode(Score.self, from: encoded), score)
            XCTAssertEqual(score.formattedOutOf10, String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), Double(tenths) / 10))
        }
        XCTAssertNil(Score(decimal: try XCTUnwrap(Decimal(string: "-0.04"))))
        XCTAssertNil(Score(decimal: try XCTUnwrap(Decimal(string: "10.04"))))
        XCTAssertNil(Score(decimal: .nan))
        for invalid in ["-0.04", "10.04", "null", "true", "\"NaN\"", "{}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(Score.self, from: Data(invalid.utf8)), invalid)
        }
    }
}
