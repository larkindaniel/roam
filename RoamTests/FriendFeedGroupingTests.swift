import XCTest
@testable import Roam

/// The Friends tab: one card per friend and city, newest visit first, and nothing undated.
final class FriendFeedGroupingTests: XCTestCase {
    private let maya = MemberSummary(id: UUID(), handle: "maya", displayName: "Maya", avatarPath: nil)
    private let theo = MemberSummary(id: UUID(), handle: "theo", displayName: "Theo", avatarPath: nil)

    private func visit(_ author: MemberSummary, _ place: String, city: String?, country: String = "PT",
                       date: String?, placeID: UUID = UUID(), logged: TimeInterval = 0) -> FriendFeedVisit {
        let experience = ExperienceSummary(id: placeID, placeID: UUID(), name: place, category: .foodDrink, locality: city, region: nil,
                                           countryCode: country, countryName: "Portugal", latitude: 38.7, longitude: -9.1,
                                           providerPlaceID: nil, followingScore: nil, followingCount: 0, viewer: .none)
        let entry = TripFeedEntry(id: UUID(), experience: experience, publicNote: "",
                                  visitDate: VisitDate(date: date.flatMap { LocalDate(isoString: $0) }, timeZoneIdentifier: nil),
                                  media: [], createdAt: Date(timeIntervalSince1970: logged), score: nil, activityID: nil)
        return FriendFeedVisit(author: maya.id == author.id ? maya : theo, entry: entry)
    }

    func testOneCardPerFriendAndCityNewestVisitFirst() {
        let groups = FriendFeedGrouping.groups([
            visit(maya, "Pastelaria", city: "Lisbon", date: "2026-05-02"),
            visit(maya, "Livraria", city: "Porto", date: "2026-05-10"),
            visit(theo, "Miradouro", city: "Lisbon", date: "2026-03-01"),
            visit(maya, "Tasca", city: "Lisbon", date: "2026-05-01"),
        ])
        XCTAssertEqual(groups.map { "\($0.author.handle) \($0.city)" }, ["maya Porto", "maya Lisbon", "theo Lisbon"])
        XCTAssertEqual(groups[1].places.map(\.experience.name), ["Pastelaria", "Tasca"])
        XCTAssertEqual(groups[1].firstVisit, LocalDate(isoString: "2026-05-01"))
        XCTAssertEqual(groups[1].lastVisit, LocalDate(isoString: "2026-05-02"))
    }

    func testUndatedVisitsAreLeftOutAndRepeatVisitsShowAPlaceOnce() {
        let cafe = UUID()
        let groups = FriendFeedGrouping.groups([
            visit(maya, "Café", city: "Lisbon", date: "2026-05-02", placeID: cafe),
            visit(maya, "Café", city: "Lisbon", date: "2026-04-02", placeID: cafe),
            visit(maya, "Undated", city: "Sintra", date: nil),
        ])
        XCTAssertEqual(groups.count, 1, "A city with only undated visits gets no card")
        XCTAssertEqual(groups[0].places.count, 1)
        XCTAssertEqual(groups[0].entries.count, 2)
    }
}
