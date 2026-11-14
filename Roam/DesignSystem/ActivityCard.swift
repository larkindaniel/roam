import SwiftUI

/// A friend's log: a small line at the top (their picture, name · date), their own photos if any (never a
/// stand-in), their note, then the place as a standard row (city, country under its name) that opens it.
struct ActivityCardView: View {
    let item: ActivityItem
    var compact = true

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            byline
            photos
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

    /// One small line: their picture, name · date. Where it was is on the place row below.
    private var byline: some View {
        HStack(spacing: Theme.Spacing.s) {
            AvatarView(member: item.author, size: 28)
            Text(item.author.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text("·").font(.subheadline).foregroundStyle(Roam.inkMuted)
            date.font(.subheadline).lineLimit(1)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { if MemberProfiles.available { router.push(.member(item.author.id)) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("activity-author")
    }

    /// Their own photos, square, swiping between several. Tapping a photo does nothing.
    @ViewBuilder private var photos: some View {
        if !item.media.isEmpty {
            let media = item.media.sorted { $0.position < $1.position }
            PlaceGallery(items: media.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name, square: true)
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
            .foregroundStyle(Roam.inkMuted)
    }
}
