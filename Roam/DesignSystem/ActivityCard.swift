import SwiftUI

/// A friend's log: a photo (theirs, square; else the place's Google photo) with a small "picture, name · date" line set
/// into its top, a slim card for the place under it, then their note.
struct ActivityCardView: View {
    /// Squarer corners for the photo and the place card than the app's usual cards.
    static let corner: CGFloat = 12

    let item: ActivityItem
    var compact = true
    /// Like and comment, set into the bottom right of the photo on a dark fade (white).
    var actions: AnyView? = nil
    /// Double-tapping the photo likes it.
    var onDoubleTap: (() -> Void)? = nil

    static func hasPhoto(_ item: ActivityItem) -> Bool { !item.media.isEmpty || item.experience.photoURL != nil }

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if hasPhoto {
                // The place card sits close under its photo.
                VStack(spacing: Theme.Spacing.m) {
                    photos
                    placeChip
                }
            }
            if !item.note.isEmpty {
                Text(item.note)
                    .font(.body)
                    .lineLimit(compact && !expanded && item.note.count >= 160 ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if compact && item.note.count >= 160 && !expanded {
                    Button("More") { expanded = true }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: Theme.minimumHitTarget)
                }
            }
            if let companions = item.companions, !companions.isEmpty {
                Text("With \(companions.map(\.displayName).formatted(.list(type: .and)))")
                    .font(.footnote)
                    .foregroundStyle(Roam.inkMuted)
            }
            // With a photo, the place is a slim card under it; without, the line and the standard row in a card.
            if !hasPhoto {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    byline(onPhoto: false)
                    placeRow
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
        .foregroundStyle(Roam.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-card-\(item.id.uuidString)")
    }

    private var hasPhoto: Bool { Self.hasPhoto(item) }

    /// One small line: their picture, name · date. Set into the top of the photo (white, on a soft dark fade), or on its
    /// own when there's no photo at all. It opens their profile.
    private func byline(onPhoto: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            AvatarView(member: item.author, size: 28)
            Text(item.author.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("·").font(.subheadline).opacity(onPhoto ? 1 : 0.7)
            date.font(.subheadline).lineLimit(1).opacity(onPhoto ? 1 : 0.75)
            Spacer(minLength: 0)
        }
        .foregroundStyle(onPhoto ? Color.white : Roam.ink)
        .padding(onPhoto ? Theme.Spacing.m : 0)
        // A deeper, taller fade, so the white line reads on any photo.
        .padding(.bottom, onPhoto ? Theme.Spacing.xl : 0)
        .background {
            if onPhoto {
                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if MemberProfiles.available { router.push(.member(item.author.id)) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("activity-author")
    }

    /// Their own photos, square, swiping between several; with none, the place's Google photo at its usual size. The
    /// byline sits in the top of either. Tapping a photo does nothing.
    @ViewBuilder private var photos: some View {
        Group {
            if !item.media.isEmpty {
                let media = item.media.sorted { $0.position < $1.position }
                PlaceGallery(items: media.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name, square: true,
                             cornerRadius: Self.corner)
            } else if let url = item.experience.photoURL {
                // The credit shows on the place's own page, a tap away.
                PlaceGallery(items: [.photo(url, credit: nil)], placeName: item.experience.name, cornerRadius: Self.corner)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap?() }
        .overlay(alignment: .top) {
            byline(onPhoto: true)
                // The photo's own corners, so the fade follows them.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Self.corner, topTrailingRadius: Self.corner, style: .continuous))
        }
        .overlay(alignment: .bottom) {
            if let actions {
                actions
                    .padding(.leading, Theme.Spacing.s)
                    .padding(.trailing, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.corner, bottomTrailingRadius: Self.corner, style: .continuous))
            }
        }
    }

    /// The place as a slim card under the photo, with no picture of its own: its name, city and country, and a chevron. It opens
    /// the place.
    private var placeChip: some View {
        Button { router.push(.experience(item.experience.id)) } label: {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(item.experience.name).font(.subheadline.weight(.semibold)).foregroundStyle(Roam.ink).lineLimit(1)
                    if !item.experience.areaLine.isEmpty {
                        Text(item.experience.areaLine).font(.caption).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            // As wide as the photo, less its margins.
            .frame(maxWidth: .infinity)
            // Liquid Glass, like the floating buttons.
            .floatingBubble(RoundedRectangle(cornerRadius: Self.corner, style: .continuous), clear: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity-place")
    }

    /// The place, as the standard row: its photo, name and where it is, and a chevron.
    private var placeRow: some View {
        Button { router.push(.experience(item.experience.id)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                PlaceThumbnail(id: "activity-\(item.id)", url: item.experience.photoURL, coordinate: item.experience.coordinate,
                               symbol: item.experience.iconName, size: 48)
                VStack(alignment: .leading, spacing: -2) {
                    Text(item.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1).truncationMode(.tail)
                    if !item.experience.areaLine.isEmpty {
                        Text(item.experience.areaLine).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity-place-row")
    }

    private var date: some View {
        Text(item.visitDate.date?.displayString ?? item.publishedAt.formatted(.relative(presentation: .named)))
    }
}
