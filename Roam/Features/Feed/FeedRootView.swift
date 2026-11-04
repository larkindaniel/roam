import SwiftUI

/// The Friends tab: one card per person and country, newest update first.
struct FeedRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var cards: LoadPhase<[CountryFeedCard]> = .idle
    @State private var unreadCount = 0

    var body: some View {
        ScrollView { content.padding(.horizontal, Theme.Spacing.l).padding(.vertical, Theme.Spacing.m) }
            .background(Roam.paper)
            .navigationTitle("Friends")
            .toolbar {
                LogPlaceToolbarButton()
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let me = session.userID { router.push(.followGraph(me, .friends)) }
                    } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Friends and requests")
                    .accessibilityIdentifier("open-friends")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { router.push(.notifications) } label: {
                        Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell").symbolRenderingMode(.hierarchical)
                    }
                    .accessibilityLabel(unreadCount > 0 ? "Notifications, \(unreadCount) unread" : "Notifications")
                    .accessibilityIdentifier("open-notifications")
                }
                ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
            }
            .navigationBarTitleDisplayMode(.large)
            .task { await load() }
            .refreshable { await load() }
            .onChange(of: changes.revision) { _, _ in Task { await load() } }
            .screenIdentifier("feed-root")
    }

    @ViewBuilder private var content: some View {
        switch cards {
        case .idle, .loading:
            SkeletonList(rows: 4).accessibilityIdentifier("feed-loading")
        case .failed(let message):
            EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load your friends' places", message: message,
                           primaryTitle: "Try again", primaryAction: { Task { await load() } })
        case .loaded(let value) where value.isEmpty:
            EmptyStateView(systemImage: "person.2", title: "Nothing from friends yet",
                           message: "Add friends to follow their places here.",
                           primaryTitle: "Find people", primaryAction: { router.showFindPeople() })
                .accessibilityIdentifier("feed-empty")
        case .loaded(let value):
            LazyVStack(spacing: Theme.Spacing.l) {
                ForEach(value) { card in
                    CountryFeedCardView(card: card) {
                        router.push(.countryUpdates(ownerID: card.author.id, countryCode: card.countryCode, title: card.title, byline: card.author.displayName))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("feed-list")
        }
    }

    private func load() async {
        if cards.value == nil { cards = .loading }
        do {
            // Newest trip first, by when they were there (not when they posted); undated ones last.
            cards = .loaded(try await services.plans.countryFeed().filter { !$0.isOwn }.sorted { left, right in
                switch (left.lastVisit, right.lastVisit) {
                case let (l?, r?): return l > r
                case (nil, nil): return left.latestAt > right.latestAt
                case (nil, _): return false
                case (_, nil): return true
                }
            })
        } catch {
            if cards.value == nil { cards = .failed(session.handle(error)) }
        }
        if let count = try? await services.notifications.unreadCount() { unreadCount = count }
    }
}

struct CountryFeedCardView: View {
    let card: CountryFeedCard
    let onOpen: () -> Void

    private var pictured: [TripFeedEntry] { card.entries.filter { !$0.media.isEmpty || $0.experience.photoURL != nil } }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.s) {
                    AvatarView(member: card.author, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.isOwn ? "You" : card.author.displayName).font(.subheadline.weight(.semibold))
                        Text(MyTimeline.range(card.firstVisit, card.lastVisit) ?? "Updated \(card.latestAt.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(Roam.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
                Text(card.title).font(.roamTitle()).multilineTextAlignment(.leading)
                if card.entries.contains(where: { !$0.media.isEmpty || $0.experience.photoURL != nil }) { photoStrip }
                if let latest = card.entries.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.experience.name).font(.headline)
                        if !latest.publicNote.isEmpty {
                            Text(latest.publicNote).font(.subheadline).foregroundStyle(Roam.inkMuted).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                }
                Text(card.placeCount == 1 ? "1 place" : "\(card.placeCount) places").font(.footnote.weight(.semibold))
            }
            .foregroundStyle(Roam.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-card-\(card.author.handle)-\(card.title)")
    }

    private var photoStrip: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(pictured.prefix(3)) { entry in
                PlacePhotoView(path: entry.media.first?.path, url: entry.experience.photoURL, credit: nil,
                               label: "Photo of \(entry.experience.name)", height: pictured.count == 1 ? 180 : 110)
            }
        }
    }
}

/// Everything someone has done in one country, newest first.
struct CountryUpdatesView: View {
    let ownerID: UUID
    let countryCode: String?
    let title: String
    var byline: String? = nil

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @State private var entries: LoadPhase<[TripFeedEntry]> = .idle

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let byline {
                    Text("\(byline)\u{2019}s places").font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .accessibilityIdentifier("country-updates-byline")
                }
                switch entries {
                case .idle, .loading:
                    SkeletonList(rows: 3)
                case .failed(let message):
                    InlineRetryView(message: message) { Task { await load() } }
                case .loaded(let value) where value.isEmpty:
                    Text("Nothing here that you can see yet.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                case .loaded(let value):
                    ForEach(value) { entry($0) }
                }
            }
            .padding(Theme.Spacing.l)
        }
        .background(Roam.paper)
        .navigationTitle(title)
        .task { await load() }
        .refreshable { await load() }
        .screenIdentifier("country-updates")
    }

    private func entry(_ entry: TripFeedEntry) -> some View {
        Button { router.push(.experience(entry.experience.id)) } label: {
            PhotoCard(path: entry.media.first?.path, url: entry.experience.photoURL, credit: entry.experience.photoCredit,
                      label: "Photo of \(entry.experience.name)", placeholderSymbol: entry.experience.iconName, height: 200, location: entry.experience.coordinate) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.experience.name).font(.headline).multilineTextAlignment(.leading)
                    Spacer(minLength: Theme.Spacing.s)
                    if Score.isShown, let score = entry.score {
                        Text(score.formatted).font(.system(.title3, design: .rounded).bold()).monospacedDigit()
                    }
                }
                Text([entry.experience.category?.title, entry.experience.locality, entry.visitDate.date?.displayString].compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Roam.inkMuted)
                if !entry.publicNote.isEmpty {
                    Text(entry.publicNote).font(.body).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Roam.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("country-entry-\(entry.experience.name)")
    }

    private func load() async {
        if entries.value == nil { entries = .loading }
        do { entries = .loaded(try await services.plans.countryUpdates(ownerID: ownerID, countryCode: countryCode)) }
        catch { if entries.value == nil { entries = .failed(error.roamMessage) } }
    }
}

/// A feed post: author, action, place, score when posted, visit date, note/photos, likes,
/// comments and the viewer's own Save/Log actions for the place.
struct FeedCard: View {
    let item: ActivityItem
    var likePending = false
    let onLike: (Bool) -> Void

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ActivityCardView(item: item, compact: true, onOpenAuthor: { router.push(.member(item.author.id)) },
                             onOpen: { router.push(.activity(item.id)) })
            Divider()
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                                                      : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
            layout {
                LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: likePending) { onLike(!item.likedByViewer) }
                Button { router.push(.activity(item.id)) } label: {
                    Label("\(item.commentCount)", systemImage: "bubble.left").monospacedDigit()
                        .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
                }
                .accessibilityLabel(item.commentCount == 1 ? "1 comment" : "\(item.commentCount) comments")
                .accessibilityIdentifier("feed-comments-\(item.id.uuidString)")
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                saveButton
                Button { openLog() } label: {
                    PillLabel(title: library.ratedCategory(item.experience.id) == nil ? "Log" : "Add visit", systemImage: "plus.circle")
                }
                .buttonStyle(PillButtonStyle(isSelected: true))
                .accessibilityIdentifier("feed-log-\(item.id.uuidString)")
            }
            .buttonStyle(.borderless)
        }
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed-card-\(item.id.uuidString)")
    }

    @ViewBuilder private var saveButton: some View {
        let id = item.experience.id
        switch library.saveState(for: id) {
        case .alreadyBeen:
            EmptyView()
        case .pending(let target):
            Button {} label: { HStack { ProgressView().controlSize(.small); Text(target ? "Saving" : "Removing") } }
                .buttonStyle(PillButtonStyle(isSelected: target)).disabled(true)
        case .saved:
            Button { Task { await library.setBookmark(id, saved: false) } } label: { PillLabel(title: "Saved", systemImage: "bookmark.fill") }
                .buttonStyle(PillButtonStyle(isSelected: true))
                .accessibilityLabel("Saved to Wishlist. Remove")
                .accessibilityIdentifier("feed-save-\(item.id.uuidString)")
        case .notSaved:
            Button { Task { await library.setBookmark(id, saved: true) } } label: { PillLabel(title: "Save", systemImage: "bookmark") }
                .buttonStyle(PillButtonStyle())
                .accessibilityLabel("Save \(item.experience.name) to Wishlist")
                .accessibilityIdentifier("feed-save-\(item.id.uuidString)")
        }
    }

    private func openLog() {
        Task {
            do { router.sheet = .log(try await services.makeLogRequest(experienceID: item.experience.id)) }
            catch { _ = session.handle(error) }
        }
    }
}

struct LikeButton: View {
    let liked: Bool
    let count: Int
    var pending = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(count)", systemImage: liked ? "heart.fill" : "heart")
                .monospacedDigit()
                .foregroundStyle(Roam.ink)
                .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
        }
        .disabled(pending)
        .roamHaptic(.impact(weight: .light), trigger: liked)
        .accessibilityLabel(liked ? "Liked, \(count) \(count == 1 ? "like" : "likes"). Unlike" : "Like, \(count) \(count == 1 ? "like" : "likes")")
        .accessibilityIdentifier("like-button")
    }
}
