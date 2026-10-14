import SwiftUI

/// Whose score a badge shows. Missing scores read "Not rated"/"No following ratings", never 0.
enum ScoreSource: Hashable {
    case you
    case following(count: Int)
    case owner(name: String)
    case snapshot

    var label: String {
        switch self {
        case .you: return "You"
        case .following: return "Following"
        case .owner(let name): return name
        case .snapshot: return "When posted"
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
            ZStack {
                Circle()
                    .fill(score.map { Theme.fill(for: $0.band) } ?? Theme.subtleFill)
                Circle()
                    .strokeBorder(score.map { Theme.color(for: $0.band) } ?? Color.secondary.opacity(0.35), lineWidth: 2)
                if let score {
                    Text(score.formatted)
                        .font(.system(size: size * 0.36 * min(scale, 1.6), weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.color(for: score.band))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .padding(4)
                } else {
                    Image(systemName: "minus")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: size * min(scale, 1.6), height: size * min(scale, 1.6))
            if showsLabel {
                Text(caption)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
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
            case .following: return "No following"
            case .you: return "Not rated"
            default: return source.label
            }
        }
        if case .following(let count) = source { return "Following · \(count)" }
        return source.label
    }

    private var accessibilityText: String {
        switch (source, score) {
        case (.you, let score?): return "Your score \(score.formatted) out of 10"
        case (.you, nil): return "Not rated"
        case (.following(let count), let score?): return "Following score \(score.formatted) out of 10 from \(count) \(count == 1 ? "person" : "people")"
        case (.following, nil): return "No following ratings"
        case (.owner(let name), let score?): return "\(name)'s score \(score.formatted) out of 10"
        case (.owner(let name), nil): return "\(name) has not rated this"
        case (.snapshot, let score?): return "Score when posted \(score.formatted) out of 10"
        case (.snapshot, nil): return "No score"
        }
    }
}

/// Category label with icon, e.g. "Outdoors".
struct CategoryBadge: View {
    let category: ExperienceCategory?
    var compact = false

    var body: some View {
        Label {
            Text(category?.title ?? "Uncategorized")
        } icon: {
            Image(systemName: category?.symbolName ?? "questionmark.circle")
        }
        .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(Theme.accent)
        .labelStyle(.titleAndIcon)
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
