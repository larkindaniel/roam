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
    let symbol: String
    let color: Color
    let label: String
    var size: CGFloat = 24

    init(state: PlaceState, size: CGFloat = 24) {
        self.init(symbol: state.markerSymbol, color: state.markerColor, label: state.title, size: size)
    }

    /// A mark of its own, like a home's black house.
    init(symbol: String, color: Color, label: String, size: CGFloat = 24) {
        self.symbol = symbol
        self.color = color
        self.label = label
        self.size = size
    }

    var body: some View {
        Circle().fill(color)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white))
            .frame(width: size, height: size)
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}

/// The signed-in member's avatar, opening their profile from any tab's navigation bar.
struct ProfileAvatarButton: View {
    /// The cog's size; the system toolbar draws its glyphs larger, so its copy passes a smaller one to match Discover's.
    var glyphSize: CGFloat = 18
    @Environment(AppRouter.self) private var router

    var body: some View {
        // A settings cog: for now your profile is just settings.
        Button { router.push(.ownProfile) } label: {
            Image(systemName: "gearshape")
                .font(.system(size: glyphSize, weight: .regular))
                .foregroundStyle(Roam.ink)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityIdentifier("open-profile")
    }
}

/// The settings cog at the top right of each tab, always in a glass circle of its own (on iOS 26 a spacer keeps it out
/// of any group of buttons beside it), so it looks the same on Discover, Friends and My Places.
struct SettingsToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton(glyphSize: 15) }
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
                                MapStill(coordinate: location, symbol: placeholderSymbol, textInset: height >= 150 ? height * 0.36 : 0)
                            } else {
                                Image(systemName: placeholderSymbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                            }
                        }
                        .accessibilityLabel(label)
                    } else if let location {
                        MapStill(coordinate: location, symbol: placeholderSymbol, textInset: height >= 150 ? height * 0.36 : 0)
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
        .shadow(color: .black.opacity(0.07), radius: 10, y: 2)
    }
}
