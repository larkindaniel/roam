import SwiftUI

enum MyPlacesSection: String, CaseIterable, Identifiable, Hashable {
    case wishlist
    case upcoming
    case past

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .upcoming: return "Upcoming trips"
        case .past: return "Past trips"
        }
    }
}

/// My Places tab: Wishlist, Upcoming trips and Past trips under one segmented control.
struct MyPlacesRootView: View {
    @Environment(SessionStore.self) private var session
    @State private var section: MyPlacesSection = .wishlist
    @State private var showsCoachmark = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $section) {
                ForEach(MyPlacesSection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.s)
            .accessibilityIdentifier("myplaces-section")
            Group {
                if section == .upcoming {
                    TripsListView(timing: .upcoming)
                } else if section == .past {
                    TripsListView(timing: .past)
                } else if let userID = session.userID {
                    PersonalListsView(ownerID: userID, initialKind: .want, isRoot: true, externalKind: .want)
                } else {
                    ProgressView()
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Roam.paper)
        .navigationTitle("My Places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
            LogPlaceToolbarFallback()
        }
        .overlay {
            if session.profile?.hasSeenBeenIntro == false {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BeenIntroCard {
                        Task {
                            await session.markBeenIntroSeen()
                            showsCoachmark = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsCoachmark {
                LogCoachmark { showsCoachmark = false }
            }
        }
    }
}
