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
    /// The picture's size; the system toolbar draws its own glass circle around it, so its copy passes a smaller one.
    var size: CGFloat = 40
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session

    var body: some View {
        // Your profile picture (or initials) opens your profile and settings.
        Button { router.push(.ownProfile) } label: {
            if let me = session.profile?.summary {
                AvatarView(member: me, size: size)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: size * 0.6, weight: .regular))
                    .foregroundStyle(Roam.ink)
                    .frame(width: size, height: size)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
        .accessibilityIdentifier("open-profile")
    }
}

/// Your profile picture at the top right of each tab, always in a glass circle of its own (on iOS 26 a spacer keeps it out
/// of any group of buttons beside it), so it looks the same on Discover, Friends and My Places.
struct SettingsToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
        }
        ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton(size: 32) }
    }
}

/// What a tab's top row turns into once you scroll down: the swipe-up cards' dark fade with just the page's name,
/// small, white and centred (as on My Places). Scrolling back up brings the row back.
struct ScrolledTitleFade: View {
    /// No title when it only sits behind the floating row, to keep the page clear of the glass.
    var title: String?
    /// How far the fade runs past the top safe area.
    var depth: CGFloat = 64

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ZStack(alignment: .top) {
                // Down from the very top of the screen, so the clock and the name both sit on the dark.
                LinearGradient(colors: [.black.opacity(0.6), .black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: top + depth)
                if let title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.top, top + 2)
                }
            }
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
