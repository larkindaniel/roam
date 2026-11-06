import SwiftUI

/// Your Lists tab: the signed-in member's Been and Want to Go.
struct ListsRootView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsCoachmark = false

    var body: some View {
        Group {
            if let userID = session.userID {
                PersonalListsView(ownerID: userID, initialKind: .been, isRoot: true)
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
