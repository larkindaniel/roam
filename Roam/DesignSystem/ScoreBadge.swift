import SwiftUI

/// Whose score a badge shows. Missing scores read "Not rated"/"No friend ratings", never 0.
enum ScoreSource: Hashable {
    case you
    case following(count: Int)
    case owner(name: String)
    case snapshot

    var label: String {
        switch self {
        case .you: return "You"
        case .following: return "Friends"
        case .owner(let name): return name
        case .snapshot: return "Score when posted"
        }
    }
}

struct ScoreBadge: View {
    let score: Score?
    let source: ScoreSource
    var size: CGFloat = 46
    var showsLabel = true

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 3) {
            Group {
                if let score {
                    Text(score.formatted)
                        .font(.system(size: size * 0.42 * min(scale, 1.6), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Roam.ink)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(minWidth: size * min(scale, 1.6) * 0.8)
            if showsLabel {
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    // Three lines keep "Score when posted" whole at accessibility text sizes.
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: size * min(scale, 1.6) + 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var caption: String {
        if score == nil {
            switch source {
            case .following: return "No friends"
            case .you: return "Not rated"
            default: return source.label
            }
        }
        if case .following(let count) = source { return "Friends · \(count)" }
        return source.label
    }

    private var accessibilityText: String {
        switch (source, score) {
        case (.you, let score?): return "Your score \(score.formatted) out of 5"
        case (.you, nil): return "Not rated"
        case (.following(let count), let score?): return "Friends score \(score.formatted) out of 5 from \(count) \(count == 1 ? "person" : "people")"
        case (.following, nil): return "No friend ratings"
        case (.owner(let name), let score?): return "\(name)'s score \(score.formatted) out of 5"
        case (.owner(let name), nil): return "\(name) has not rated this"
        case (.snapshot, let score?): return "Score when posted \(score.formatted) out of 5"
        case (.snapshot, nil): return "No score"
        }
    }
}

/// Category label with icon, e.g. "Outdoors".
struct CategoryBadge: View {
    let category: ExperienceCategory?
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category?.symbolName ?? "questionmark.circle")
            Text(category?.title ?? "Uncategorized")
        }
        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Category: \(category?.title ?? "Uncategorized")")
    }
}

/// Sentiment chip that never relies on colour alone.
struct SentimentTag: View {
    let sentiment: Sentiment

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sentiment.symbolName)
            Text(sentiment.shortTitle)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(Theme.color(for: sentiment))
        .background(Capsule().fill(Theme.fill(for: sentiment)))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
