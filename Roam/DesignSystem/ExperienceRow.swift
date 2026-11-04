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
    var thumbnailURL: URL? = nil

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if typeSize.isAccessibilitySize {
                info
                badges
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    if let thumbnailURL {
                        AsyncImage(url: thumbnailURL) { image in image.resizable().scaledToFill() } placeholder: { Roam.fill }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .accessibilityHidden(true)
                    }
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
                        Text("·").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                        Text(area).font(.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    CategoryBadge(category: category, compact: true)
                    if !area.isEmpty {
                        Text(area).font(.caption).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let statusLine {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
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
        if Score.isShown, let rank { return Text("\(rank). ").monospacedDigit() + Text(name) }
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
                .foregroundStyle(Theme.secondaryText)
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
            .roamHaptic(.impact(weight: .light), trigger: saved)
            .accessibilityLabel(saved ? "Saved to Wishlist. Remove \(name)" : "Save \(name) to Wishlist")
            .accessibilityIdentifier("save-\(name)")
        }
    }
}

/// Member row with avatar, name, handle and an optional friend control.
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
                    Text("@\(member.handle)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText)
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
    case addFriend
    case accept
    case requested
    case friends
    case pending

    init(_ state: FriendState, pending: Bool = false) {
        if pending { self = .pending; return }
        switch state {
        case .none: self = .addFriend
        case .sent: self = .requested
        case .received: self = .accept
        case .friends: self = .friends
        }
    }
}

struct FollowButton: View {
    let state: FollowButtonState
    let name: String
    let action: () -> Void
    @State private var confirmingRemoval = false

    var body: some View {
        Button {
            if state == .friends { confirmingRemoval = true } else { action() }
        } label: {
            switch state {
            case .pending:
                ProgressView().controlSize(.small).frame(minWidth: 70)
            case .addFriend:
                Text("Add friend").frame(minWidth: 70)
            case .accept:
                Text("Accept").frame(minWidth: 70)
            case .requested:
                Text("Requested").frame(minWidth: 70)
            case .friends:
                Text("Friends").frame(minWidth: 70)
            }
        }
        .buttonStyle(PillButtonStyle(isSelected: state == .addFriend || state == .accept))
        .disabled(state == .pending)
        .roamHaptic(.impact(weight: .light), trigger: state == .friends)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("follow-button")
        .confirmationDialog("Remove \(name) as a friend?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive, action: action)
        } message: {
            Text("You'll stop seeing each other's friends-only places.")
        }
    }

    private var accessibilityText: String {
        switch state {
        case .addFriend: return "Add \(name) as a friend"
        case .accept: return "Accept friend request from \(name)"
        case .requested: return "Friend request sent to \(name). Cancel request"
        case .friends: return "Friends with \(name). Remove friend"
        case .pending: return "Updating friendship with \(name)"
        }
    }
}
