import SwiftUI

/// Distinct collection states (SPEC R00): loading, populated, genuinely empty, filtered empty,
/// recoverable error and pagination failure. Refresh failures keep current content.
enum LoadPhase<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var primaryTitle: String?
    var primaryAction: (() -> Void)?
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent)
                .padding(20)
                .background(Circle().fill(Theme.accentFill))
                .accessibilityHidden(true)
            VStack(spacing: Theme.Spacing.s) {
                Text(title)
                    .font(.roamTitle())
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Theme.Spacing.s) {
                if let primaryTitle, let primaryAction {
                    Button(primaryTitle, action: primaryAction).buttonStyle(PrimaryButtonStyle(compact: true))
                }
                if let secondaryTitle, let secondaryAction {
                    Button(secondaryTitle, action: secondaryAction).buttonStyle(QuietButtonStyle())
                }
            }
            .frame(maxWidth: 320)
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("empty-state")
    }
}

/// Inline, non-blocking error with retry. Retry never clears filters or scroll.
struct InlineRetryView: View {
    let message: String
    var retryTitle = "Try again"
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.fine)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button(retryTitle, action: retry)
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: Theme.minimumHitTarget)
                    .accessibilityIdentifier("retry-button")
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.fineFill.opacity(0.6)))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inline-error")
    }
}

/// Placeholder rows shown while a collection first loads. Respects Reduce Motion.
struct SkeletonRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4).frame(width: 180, height: 14)
                RoundedRectangle(cornerRadius: 4).frame(width: 120, height: 10)
                RoundedRectangle(cornerRadius: 4).frame(width: 90, height: 10)
            }
            Spacer()
            Circle().frame(width: 44, height: 44)
        }
        .foregroundStyle(Theme.subtleFill)
        .opacity(reduceMotion ? 0.8 : (pulse ? 0.5 : 1))
        .padding(.vertical, Theme.Spacing.s)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}

struct SkeletonList: View {
    var rows = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { _ in
                SkeletonRow()
                Divider()
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
        .accessibilityIdentifier("loading-skeleton")
    }
}

/// Footer shown when the next page fails; existing rows stay visible.
struct PaginationFooter: View {
    let isLoading: Bool
    let errorMessage: String?
    let hasMore: Bool
    let loadMore: () -> Void

    var body: some View {
        Group {
            if let errorMessage {
                InlineRetryView(message: errorMessage, retryTitle: "Load more", retry: loadMore)
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 44)
            } else if hasMore {
                Color.clear.frame(height: 1).onAppear(perform: loadMore)
            }
        }
        .padding(.vertical, Theme.Spacing.s)
    }
}

/// Floating List/Map switch.
struct MapListToggle: View {
    @Binding var showsMap: Bool

    var body: some View {
        Button {
            showsMap.toggle()
        } label: {
            Label(showsMap ? "View List" : "View Map", systemImage: showsMap ? "list.bullet" : "map")
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(Roam.ink)
                .background(Capsule().fill(Roam.paperRaised))
                .shadow(color: .black.opacity(0.10), radius: 9, y: 6)
        }
        .frame(minHeight: Theme.minimumHitTarget)
        .accessibilityIdentifier("map-list-toggle")
    }
}

/// Card for the selected map pin; mirrors the same experience highlighted in the list.
struct SelectedPlaceCard: View {
    let summary: ExperienceSummary
    var onOpen: () -> Void
    var onSave: (() -> Void)?
    var onLog: (() -> Void)?
    var saveState: SaveActionState?
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top) {
                ExperienceRow(name: summary.name, category: summary.category, area: summary.areaLine,
                              score: summary.viewer.myScore, scoreSource: .you,
                              secondaryScore: summary.followingScore,
                              secondarySource: .following(count: summary.followingCount),
                              saveState: saveState, logTitle: summary.viewer.isRated ? "Add visit" : "Log",
                              onOpen: onOpen, onSave: onSave, onLog: onLog)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                }
                .accessibilityLabel("Close selected place")
            }
        }
        .roamCard(padding: Theme.Spacing.m)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityIdentifier("selected-place-card")
    }
}

/// Destructive confirmation copy is always explicit about what is kept and what is removed.
struct DestructiveConfirmation: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
}
