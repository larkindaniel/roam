import MapKit
import SwiftUI

/// Where a recommendation came from. Sources are never blended into one score.
enum RecommendationSource: Hashable, Sendable {
    case picked
    case friends
    case community
    case research

    var title: String {
        switch self {
        case .picked: return "Picked for you"
        case .friends: return "From your friends"
        case .community: return "From the community"
        case .research: return "Research further"
        }
    }

    var symbolName: String {
        switch self {
        case .picked: return "square.fill"
        case .friends: return "circle.fill"
        case .community: return "circle"
        case .research: return "square.dashed"
        }
    }
}

struct SourceLabel: View {
    let source: RecommendationSource

    var body: some View {
        Label(source.title, systemImage: source.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.footnote.weight(.semibold))
            .imageScale(.small)
            .foregroundStyle(Roam.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

enum PlaceState: Hashable, Sendable {
    case wishlist
    case planned
    case visited

    var title: String {
        switch self {
        case .wishlist: return "Wishlist"
        case .planned: return "Planned"
        case .visited: return "Visited"
        }
    }
}

/// State is carried by shape: dotted, solid outline or filled circle.
struct StatusMark: View {
    let state: PlaceState
    var size: CGFloat = 24

    var body: some View {
        Circle().fill(state.markerColor)
            .overlay(Image(systemName: state.markerSymbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(state.title)
    }
}

/// The signed-in member's avatar, opening their profile from any tab's navigation bar.
struct ProfileAvatarButton: View {
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        Button { router.push(.ownProfile) } label: {
            Text(initials)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Roam.ink)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Roam.fill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityIdentifier("open-profile")
    }

    private var initials: String {
        let name = session.profile?.displayName ?? ""
        return String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}

/// Log a place, at the top left of each tab's main screen.
struct LogPlaceToolbarButton: ToolbarContent {
    @Environment(AppRouter.self) private var router

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { router.sheet = .logPlace } label: { Image(systemName: "plus") }
                .accessibilityLabel("Log a place")
                .accessibilityIdentifier("log-place")
        }
    }
}

/// A place's picture: an uploaded photo when there is one, otherwise its linked photo with credit.
struct PlacePhotoView: View {
    var path: String?
    var url: URL?
    var credit: String?
    var label: String
    var placeholderSymbol = "mappin"
    var height: CGFloat
    var showsCredit = true
    var cornerRadius: CGFloat = Theme.cornerRadius
    /// Where the place is: with no photo, a map of the spot stands in.
    var location: CLLocationCoordinate2D?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Roam.fill
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    if let path {
                        RemoteImageView(path: path, accessibilityLabel: label)
                    } else if let url {
                        WebImage(url: url) { ProgressView() } failure: {
                            if let location {
                                MapStill(coordinate: location, symbol: placeholderSymbol)
                            } else {
                                Image(systemName: placeholderSymbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                            }
                        }
                        .accessibilityLabel(label)
                    } else if let location {
                        MapStill(coordinate: location, symbol: placeholderSymbol)
                    } else {
                        Image(systemName: placeholderSymbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            if showsCredit, path == nil, url != nil, let credit {
                Text("Photo: \(credit)").font(.caption2).foregroundStyle(Roam.inkMuted).lineLimit(1)
            }
        }
    }
}

/// A photo and its text enclosed in one raised card.
struct PhotoCard<Content: View>: View {
    var path: String?
    var url: URL?
    var credit: String?
    var label: String
    var placeholderSymbol = "mappin"
    var height: CGFloat
    var location: CLLocationCoordinate2D?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlacePhotoView(path: path, url: url, credit: nil, label: label, placeholderSymbol: placeholderSymbol, height: height,
                           showsCredit: false, cornerRadius: 0, location: location)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                content()
                if path == nil, url != nil, let credit {
                    Text("Photo: \(credit)").font(.caption2).foregroundStyle(Roam.inkMuted).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.m)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Roam.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Roam.rule))
    }
}

/// "★ 4.6 Google · 1,240 reviews", shown beside Roam's own scores when Google has rated the place.
struct GoogleRatingLine: View {
    let experience: ExperienceSummary

    var body: some View {
        if let rating = experience.googleRating {
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(.orange)
                Text(String(format: "%.1f", rating)).fontWeight(.semibold).foregroundStyle(Roam.ink).monospacedDigit()
                Text("Google").foregroundStyle(Roam.inkMuted)
                if let count = experience.googleRatingCount {
                    Text("· \(count.formatted()) \(count == 1 ? "review" : "reviews")").foregroundStyle(Roam.inkMuted)
                }
            }
            .font(.footnote)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Google rating \(String(format: "%.1f", rating)) out of 5\(experience.googleRatingCount.map { " from \($0) reviews" } ?? "")")
        }
    }
}
