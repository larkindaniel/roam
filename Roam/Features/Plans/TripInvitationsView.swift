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
                        // One card of standard rows, with the usual lines between them, like Sent to you and Lists.
                        VStack(spacing: 0) {
                            ForEach(invitations) { invitation in
                                row(invitation)
                                if invitation.id != invitations.last?.id { RowSeparator() }
                            }
                        }
                        .roamCard(padding: Theme.Spacing.m)
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

    /// Their picture, the trip's name, who it's from and when, then Accept and a small × to decline.
    private func row(_ invitation: TripInvitation) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            AvatarView(member: invitation.owner, size: 48)
            VStack(alignment: .leading, spacing: -2) {
                Text(invitation.name).font(.headline).lineLimit(1).truncationMode(.tail)
                Text([("From " + invitation.owner.displayName), MyTimeline.range(invitation.startDate, invitation.endDate)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if pending == invitation.id {
                ProgressView()
            } else {
                Button("Accept") { Task { await respond(.accept, to: invitation) } }
                    .buttonStyle(PillButtonStyle(isSelected: true))
                    .tapID("accept-trip-invitation")
                Button { Task { await respond(.decline, to: invitation) } } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Roam.inkMuted)
                        .frame(width: 32, height: 32).background(Circle().fill(Roam.fill))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decline")
                .tapID("decline-trip-invitation")
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .disabled(pending != nil)
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
