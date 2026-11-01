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
    var size: CGFloat = 14

    var body: some View {
        Group {
            switch state {
            case .wishlist:
                Circle().strokeBorder(Roam.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 3.6]))
            case .planned:
                Circle().strokeBorder(Roam.ink, lineWidth: 1.5)
            case .visited:
                Circle().fill(Roam.ink)
            }
        }
        .frame(width: size, height: size)
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

/// + Log a place: the raised capsule in the tab bar's bottom accessory.
struct LogPlaceAccessory: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Button { router.sheet = .logPlace } label: {
            Label("Log a place", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Roam.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log-place")
    }
}

/// The toolbar fallback for + Log a place before iOS 26.
struct LogPlaceToolbarFallback: ToolbarContent {
    @Environment(AppRouter.self) private var router

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if #unavailable(iOS 26.0) {
                Button { router.sheet = .logPlace } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Log a place")
                    .accessibilityIdentifier("log-place")
            }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Roam.fill
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay {
                    if let path {
                        RemoteImageView(path: path, accessibilityLabel: label)
                    } else if let url {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill().accessibilityLabel(label)
                            } else if phase.error != nil {
                                Image(systemName: placeholderSymbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                            } else {
                                ProgressView()
                            }
                        }
                    } else {
                        Image(systemName: placeholderSymbol).font(.largeTitle).foregroundStyle(Roam.inkMuted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            if path == nil, url != nil, let credit {
                Text("Photo: \(credit)").font(.caption2).foregroundStyle(Roam.inkMuted).lineLimit(1)
            }
        }
    }
}
