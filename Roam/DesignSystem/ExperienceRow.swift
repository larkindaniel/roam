import SwiftUI

/// Viewer-side save state for a row's Save action.
enum SaveActionState: Hashable {
    case notSaved
    case saved
    case pending(target: Bool)
    /// Already rated by the viewer: saving is replaced by "Add visit".
    case alreadyBeen
}

/// Experience row: name, category, area, relevant score/source, optional rank and distinct
/// Save/Log actions. Tapping an action never opens the row.
struct ExperienceRow: View {
    let name: String
    let category: ExperienceCategory?
    let area: String
    var rank: Int?
    var score: Score?
    var scoreSource: ScoreSource = .you
    var secondaryScore: Score?
    var secondarySource: ScoreSource?
    var statusLine: String?
    var saveState: SaveActionState?
    var logTitle: String?
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?
    var onLog: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if typeSize.isAccessibilitySize {
                info
                badges
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    info.frame(maxWidth: .infinity, alignment: .leading)
                    badges
                }
            }
            if saveState != nil || onLog != nil {
                actions
            }
        }
        .padding(.vertical, Theme.Spacing.s)
        .screenIdentifier("experience-row-\(name)")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleText
                .font(.headline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    CategoryBadge(category: category, compact: true).fixedSize()
                    if !area.isEmpty {
                        Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(area).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    CategoryBadge(category: category, compact: true)
                    if !area.isEmpty {
                        Text(area).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(onOpen == nil ? [] : .isButton)
        .accessibilityAction { onOpen?() }
    }

    private var badges: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            if let secondarySource {
                ScoreBadge(score: secondaryScore, source: secondarySource, size: 40)
            }
            if score != nil || scoreSource == .you {
                ScoreBadge(score: score, source: scoreSource, size: 44)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
    }

    private var titleText: Text {
        if let rank { return Text("\(rank). ").monospacedDigit() + Text(name) }
        return Text(name)
    }

    @ViewBuilder private var actions: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.s))
        layout {
            if let saveState {
                saveButton(saveState)
            }
            if let onLog {
                Button(action: onLog) {
                    PillLabel(title: logTitle ?? "Log", systemImage: logTitle == "Add visit" ? "plus.circle" : "plus.circle.fill")
                }
                .buttonStyle(PillButtonStyle(isSelected: false))
                .accessibilityLabel("\(logTitle ?? "Log") \(name)")
                .accessibilityIdentifier("log-\(name)")
            }
        }
    }

    @ViewBuilder private func saveButton(_ state: SaveActionState) -> some View {
        switch state {
        case .alreadyBeen:
            PillLabel(title: "Been", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .foregroundStyle(.secondary)
                .frame(minHeight: Theme.minimumHitTarget)
                .accessibilityLabel("Already been")
        case .pending(let target):
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(target ? "Saving" : "Removing")
                }
            }
            .buttonStyle(PillButtonStyle(isSelected: target))
            .disabled(true)
        case .saved, .notSaved:
            let saved = state == .saved
            Button { onSave?() } label: {
                PillLabel(title: saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
            }
            .buttonStyle(PillButtonStyle(isSelected: saved))
            .accessibilityLabel(saved ? "Saved to Want to Go. Remove \(name)" : "Save \(name) to Want to Go")
            .accessibilityIdentifier("save-\(name)")
        }
    }
}

/// Member row with avatar, name, handle and an optional follow control.
struct MemberRowView: View {
    let member: MemberSummary
    var subtitle: String?
    var followState: FollowButtonState?
    var onOpen: (() -> Void)?
    var onToggleFollow: (() -> Void)?

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                AvatarView(member: member, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName).font(.headline).lineLimit(2)
                    Text("@\(member.handle)").font(.subheadline).foregroundStyle(.secondary)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onOpen?() }
            if let followState {
                FollowButton(state: followState, name: member.displayName) { onToggleFollow?() }
            }
        }
        .padding(.vertical, 6)
        .screenIdentifier("member-row-\(member.handle)")
    }
}

enum FollowButtonState: Hashable {
    case follow
    case followBack
    case following
    case pending
}

struct FollowButton: View {
    let state: FollowButtonState
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            switch state {
            case .pending:
                ProgressView().controlSize(.small).frame(minWidth: 70)
            case .follow:
                Text("Follow").frame(minWidth: 70)
            case .followBack:
                Text("Follow back").frame(minWidth: 70)
            case .following:
                Text("Following").frame(minWidth: 70)
            }
        }
        .buttonStyle(PillButtonStyle(isSelected: state == .follow || state == .followBack))
        .disabled(state == .pending)
        .accessibilityLabel(state == .following ? "Following \(name). Unfollow" : "Follow \(name)")
        .accessibilityIdentifier("follow-button")
    }
}
