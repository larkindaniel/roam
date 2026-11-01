import SwiftUI

enum MyPlacesSection: String, CaseIterable, Identifiable, Hashable {
    case wishlist
    case been
    case trips

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .been: return "Been there"
        case .trips: return "Trips"
        }
    }
}

/// My Places tab: Wishlist, Been there and Trips under one segmented control.
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
                if section == .trips {
                    TripsListView()
                } else if let userID = session.userID {
                    PersonalListsView(ownerID: userID, initialKind: section == .been ? .been : .want, isRoot: true,
                                      externalKind: section == .been ? .been : .want)
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
