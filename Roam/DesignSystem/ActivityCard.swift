import SwiftUI

struct ActivityCardView: View {
    let item: ActivityItem
    var compact = true

    @Environment(AppRouter.self) private var router
    @State private var expanded = false

    private static let profileLink = URL(string: "roam-action://profile")!
    private static let placeLink = URL(string: "roam-action://place")!

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Button { router.push(.member(item.author.id)) } label: {
                    AvatarView(member: item.author, size: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(item.author.displayName)'s profile")
                .accessibilityIdentifier("activity-author")
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(headline)
                        .font(.body)
                        .tint(Roam.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .environment(\.openURL, OpenURLAction { url in
                            switch url {
                            case Self.profileLink: router.push(.member(item.author.id))
                            case Self.placeLink: router.push(.experience(item.experience.id))
                            default: return .discarded
                            }
                            return .handled
                        })
                        .accessibilityAction(named: Text("Open place")) { router.push(.experience(item.experience.id)) }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.s) { area; date }
                        VStack(alignment: .leading, spacing: 2) { area; date }
                    }
                }
            }
            if let trip = item.trip {
                Button { router.push(.trip(trip.id)) } label: {
                    Label(trip.name, systemImage: "airplane")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, Theme.Spacing.s)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Roam.fill, in: Capsule())
                        .frame(minHeight: Theme.minimumHitTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open trip \(trip.name)")
                .accessibilityIdentifier("activity-trip")
            }
            if let companions = item.companions, !companions.isEmpty {
                Text("With \(companions.map(\.displayName).formatted(.list(type: .and)))")
                    .font(.footnote)
                    .foregroundStyle(Roam.inkMuted)
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
            if let visitID = item.visitID, !item.media.isEmpty {
                let photos = item.media.sorted { $0.position < $1.position }
                PlaceGallery(items: photos.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name) { path in
                    guard let photo = photos.first(where: { $0.path == path }) else { return }
                    router.push(.visitPhoto(experienceID: item.experience.id, visitID: visitID, photoID: photo.id))
                }
            }
        }
        .foregroundStyle(Roam.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-card-\(item.id.uuidString)")
    }

    private var headline: AttributedString {
        var author = AttributedString(item.author.displayName)
        author.link = Self.profileLink
        author.font = .body.weight(.semibold)
        var place = AttributedString(item.experience.name)
        place.link = Self.placeLink
        place.font = .body.weight(.semibold)
        return author + AttributedString(" \(item.type.verb) ") + place
    }

    @ViewBuilder private var area: some View {
        if let city = item.experience.locality, !city.isEmpty {
            let destination = Destination(name: city, region: item.experience.region, countryCode: item.experience.countryCode,
                                          countryName: item.experience.countryName, latitude: item.experience.latitude,
                                          longitude: item.experience.longitude, radiusMeters: 15_000)
            Button { router.push(.city(destination)) } label: {
                Label(item.experience.areaLine, systemImage: "map")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
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
