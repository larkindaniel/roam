import SwiftUI

/// A friend's log: a photo (theirs, square; else the place's Google photo) with a small "picture, name · date" line set
/// into its top, their note, then the place as a standard row (city, country under its name) that opens it.
struct ActivityCardView: View {
    let item: ActivityItem
    var compact = true

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if hasPhoto { photos } else { byline(onPhoto: false) }
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
            placeRow
        }
        .foregroundStyle(Roam.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-card-\(item.id.uuidString)")
    }

    private var hasPhoto: Bool { !item.media.isEmpty || item.experience.photoURL != nil }

    /// One small line: their picture, name · date. Set into the top of the photo (white, on a soft dark fade), or on its
    /// own when there's no photo at all. It opens their profile.
    private func byline(onPhoto: Bool) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            AvatarView(member: item.author, size: 28)
            Text(item.author.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("·").font(.subheadline).opacity(0.7)
            date.font(.subheadline).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(onPhoto ? Color.white : Roam.ink)
        .padding(onPhoto ? Theme.Spacing.m : 0)
        .background {
            if onPhoto {
                LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom)
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
                PlaceGallery(items: media.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name, square: true)
            } else if let url = item.experience.photoURL {
                PlaceGallery(items: [.photo(url, credit: item.experience.photoCredit)], placeName: item.experience.name)
            }
        }
        .overlay(alignment: .top) {
            byline(onPhoto: true)
                // The gallery's own corners (24), so the fade follows them.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous))
        }
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
        .accessibilityIdentifier("activity-place")
    }

    private var date: some View {
        Text(item.visitDate.date?.displayString ?? item.publishedAt.formatted(.relative(presentation: .named)))
            .opacity(0.75)
    }
}
