import SwiftUI

/// My Places tab: Wishlist, Been there and Trips under one segmented control.
struct MyPlacesRootView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsCoachmark = false

    var body: some View {
        Group {
            if let userID = session.userID {
                PersonalListsView(ownerID: userID, initialKind: .want, isRoot: true)
            } else {
                ProgressView()
            }
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
