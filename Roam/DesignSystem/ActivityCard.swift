import SwiftUI

/// A friend's log: who and where at the top (their picture, name, then place and date), their photos, their note, then
/// the place as a standard row that opens it.
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

    /// Their picture and name, with where and when tucked under it.
    private var byline: some View {
        HStack(spacing: Theme.Spacing.m) {
            AvatarView(member: item.author, size: 44)
            VStack(alignment: .leading, spacing: -2) {
                Text(item.author.displayName).font(.headline).lineLimit(1)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) { area; Text("·").foregroundStyle(Roam.inkMuted); date }
                    VStack(alignment: .leading, spacing: 0) { area; date }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { if MemberProfiles.available { router.push(.member(item.author.id)) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("activity-author")
    }

    /// Their own photos; with none, the place's photo stands in.
    @ViewBuilder private var photos: some View {
        if let visitID = item.visitID, !item.media.isEmpty {
            let media = item.media.sorted { $0.position < $1.position }
            PlaceGallery(items: media.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name) { path in
                guard let photo = media.first(where: { $0.path == path }) else { return }
                router.push(.visitPhoto(experienceID: item.experience.id, visitID: visitID, photoID: photo.id))
            }
        } else if let url = item.experience.photoURL {
            Button { router.push(.experience(item.experience.id)) } label: {
                PlaceGallery(items: [.photo(url, credit: item.experience.photoCredit)], placeName: item.experience.name)
                    .allowsHitTesting(false)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the place")
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
                    if let category = item.experience.category?.title {
                        Text(category).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
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

    @ViewBuilder private var area: some View {
        if let city = item.experience.locality, !city.isEmpty {
            let destination = Destination(name: city, region: item.experience.region, countryCode: item.experience.countryCode,
                                          countryName: item.experience.countryName, latitude: item.experience.latitude,
                                          longitude: item.experience.longitude, radiusMeters: 15_000)
            Button { router.push(.city(destination)) } label: {
                Text(item.experience.areaLine)
                    .font(.footnote)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Roam.inkMuted)
            .accessibilityLabel("Open map of \(city)")
        } else if let code = item.experience.countryCode, !item.experience.areaLine.isEmpty {
            Button(item.experience.areaLine) { router.push(.country(code)) }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundStyle(Roam.inkMuted)
        }
    }

    private var date: some View {
        Text(item.visitDate.date?.displayString ?? item.publishedAt.formatted(.relative(presentation: .named)))
            .font(.footnote)
            .foregroundStyle(Roam.inkMuted)
    }
}
