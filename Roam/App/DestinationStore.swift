import Foundation
import Observation

/// Search/Explore context destinations. Choosing one changes search context only — never the home
/// city or visited counts. Default is the last selected destination, then the home city.
@MainActor
@Observable
final class DestinationStore {
    var search: Destination?
    var explore: Destination?
    /// Result of a home-city pick, consumed by the profile editor or setup flow.
    var pickedHomeCity: Destination?
    private(set) var lastSelected: Destination?

    private let storage: AccountStorage
    private var userID: UUID?

    init(storage: AccountStorage) {
        self.storage = storage
    }

    func load(userID: UUID, home: Destination?) {
        self.userID = userID
        lastSelected = storage.read(Destination.self, name: "last-destination", userID: userID)
        let initial = lastSelected ?? home
        if search == nil { search = initial }
        if explore == nil { explore = initial }
    }

    func reset() {
        search = nil
        explore = nil
        pickedHomeCity = nil
        lastSelected = nil
        userID = nil
    }

    func select(_ destination: Destination, for purpose: DestinationPickerPurpose) {
        switch purpose {
        case .search: search = destination
        case .explore: explore = destination
        case .homeCity:
            pickedHomeCity = destination
            return
        }
        lastSelected = destination
        if let userID { try? storage.write(destination, name: "last-destination", userID: userID) }
    }
}
