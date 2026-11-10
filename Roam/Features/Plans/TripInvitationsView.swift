import SwiftUI

struct TripInvitationsView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var phase: LoadPhase<[TripInvitation]> = .idle
    @State private var pending: UUID?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                switch phase {
                case .idle, .loading: SkeletonList(rows: 3)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let invitations):
                    if invitations.isEmpty {
                        EmptyStateView(systemImage: "airplane", title: "No trip invitations",
                                       message: "Invitations from friends appear here.")
                    } else {
                        ForEach(invitations) { invitation in card(invitation) }
                    }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .contentMargins(.bottom, RoamTabBar.reservedHeight, for: .scrollContent)
        .background(Roam.paper)
        .navigationTitle("Trip invitations")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("trip-invitations")
    }

    private func card(_ invitation: TripInvitation) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(member: invitation.owner, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.name).font(.headline)
                    Text("From \(invitation.owner.displayName)").font(.footnote).foregroundStyle(Roam.inkMuted)
                    if let dates = MyTimeline.range(invitation.startDate, invitation.endDate) {
                        Text(dates).font(.footnote).foregroundStyle(Roam.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Accept") { Task { await respond(.accept, to: invitation) } }
                    .buttonStyle(PillButtonStyle(isSelected: true))
                    .accessibilityIdentifier("accept-trip-invitation")
                Button("Decline") { Task { await respond(.decline, to: invitation) } }
                    .buttonStyle(PillButtonStyle())
                if pending == invitation.id { ProgressView() }
            }
            .disabled(pending != nil)
        }
        .roamCard()
    }

    private func load() async {
        if phase.value == nil { phase = .loading }
        do { phase = .loaded(try await services.plans.tripInvitations()) }
        catch { phase = .failed(session.handle(error)) }
    }

    private func respond(_ action: TripMembershipAction, to invitation: TripInvitation) async {
        guard pending == nil, let me = session.userID else { return }
        pending = invitation.id
        error = nil
        defer { pending = nil }
        do {
            try await services.plans.setTripMembership(tripID: invitation.id, memberID: me, action: action)
            await load()
            library.noteChanged()
            if action == .accept { router.push(.trip(invitation.id)) }
        } catch { self.error = session.handle(error) }
    }
}
