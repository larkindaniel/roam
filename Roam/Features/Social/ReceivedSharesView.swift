import SwiftUI

struct SocialNavigationRow: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    var place: ExperienceSummary? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                if let place {
                    PlaceThumbnail(id: place.id.uuidString, path: nil, url: place.photoURL,
                                   coordinate: place.coordinate, symbol: place.iconName, size: 48)
                } else {
                    Image(systemName: symbol)
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Roam.fill, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .foregroundStyle(Roam.ink)
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ReceivedShareRow: View {
    let share: DirectShare
    @Environment(AppRouter.self) private var router

    var body: some View {
        let sender = "From \(share.sender.displayName)"
        let context = share.message.isEmpty ? sender : "\(sender) · \(share.message)"
        SocialNavigationRow(title: share.title, symbol: share.list != nil ? "list.bullet" : "airplane",
                            subtitle: context, place: share.experience) {
            if let place = share.experience { router.push(.experience(place.id)) }
            else if let list = share.list { router.push(.list(list.id)) }
            else if let trip = share.trip { router.push(.trip(trip.id)) }
        }
        .accessibilityIdentifier("foryou-pick-open-\(share.title)")
    }
}

struct ReceivedSharesView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @State private var phase: LoadPhase<[DirectShare]> = .idle

    var body: some View {
        ScrollView {
            Group {
                switch phase {
                case .idle, .loading: SkeletonList(rows: 3)
                case .failed(let error):
                    InlineRetryView(message: error) { Task { await load() } }
                case .loaded(let shares):
                    if shares.isEmpty {
                        EmptyStateView(systemImage: "paperplane", title: "Nothing sent yet",
                                       message: "Places and lists from friends will appear here.")
                    } else {
                        VStack(spacing: 0) {
                            ForEach(shares) { share in
                                ReceivedShareRow(share: share)
                                if share.id != shares.last?.id { RowSeparator() }
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
        .navigationTitle("Sent to you")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("received-shares")
    }

    private func load() async {
        if phase.value == nil { phase = .loading }
        do { phase = .loaded(try await services.plans.sharedWithMe()) }
        catch { phase = .failed(session.handle(error)) }
    }
}
