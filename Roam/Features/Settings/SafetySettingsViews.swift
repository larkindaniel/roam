import Observation
import SwiftUI

/// Blocked or muted members with loading, empty, retry and removal (S26 Safety).
@MainActor
@Observable
final class SafetyMembersModel {
    let kind: SafetyListKind
    private(set) var phase: LoadPhase<[MemberSummary]> = .idle
    private(set) var removing: Set<UUID> = []
    var actionError: String?

    private let social: any SocialService

    init(kind: SafetyListKind, social: any SocialService) {
        self.kind = kind
        self.social = social
    }

    func load() async {
        if phase.value == nil { phase = .loading }
        do {
            let members = kind == .blocked ? try await social.blockedMembers() : try await social.mutedMembers()
            phase = .loaded(members)
        } catch {
            // A failed refresh keeps the rows already shown.
            if phase.value == nil { phase = .failed(error.roamMessage) } else { actionError = error.roamMessage }
        }
    }

    /// Unblock/unmute: the row leaves at once and returns if the server refuses. Unblocking never
    /// restores the follows the block removed.
    func remove(_ member: MemberSummary) async {
        guard case .loaded(let members) = phase, !removing.contains(member.id) else { return }
        removing.insert(member.id)
        defer { removing.remove(member.id) }
        phase = .loaded(members.filter { $0.id != member.id })
        do {
            if kind == .blocked {
                try await social.setBlock(userID: member.id, blocked: false)
            } else {
                try await social.setMute(userID: member.id, muted: false)
            }
            actionError = nil
        } catch {
            if case .loaded(let current) = phase, !current.contains(where: { $0.id == member.id }) {
                phase = .loaded(members.filter { original in original.id == member.id || current.contains { $0.id == original.id } })
            }
            actionError = "Couldn't \(kind == .blocked ? "unblock" : "unmute") @\(member.handle). \(error.roamMessage)"
        }
    }
}

struct SafetyMembersView: View {
    let kind: SafetyListKind

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @State private var model: SafetyMembersModel?
    @State private var confirming: MemberSummary?

    private var title: String { kind == .blocked ? "Blocked people" : "Muted people" }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.groupedCanvas)
        .task {
            if model == nil { model = SafetyMembersModel(kind: kind, social: services.social) }
            await model?.load()
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible, presenting: confirming) { member in
            Button(kind == .blocked ? "Unblock" : "Unmute") {
                Task {
                    await model?.remove(member)
                    changes.markFeedStale()
                }
            }
            .accessibilityIdentifier("confirm-safety-remove")
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text(kind == .blocked
                 ? "You'll be able to see each other's profiles, posts, lists and comments again. Friendships that the block ended aren't restored."
                 : "Their places will appear in your Friends tab again.")
        }
        .screenIdentifier("safety-\(kind.rawValue)")
    }

    private var confirmTitle: String {
        guard let confirming else { return "" }
        return kind == .blocked ? "Unblock @\(confirming.handle)?" : "Unmute @\(confirming.handle)?"
    }

    @ViewBuilder private func content(_ model: SafetyMembersModel) -> some View {
        switch model.phase {
        case .idle, .loading:
            SkeletonList(rows: 3).padding()
                .frame(maxHeight: .infinity, alignment: .top)
        case .failed(let message):
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this list", message: message,
                           primaryTitle: "Try again", primaryAction: { Task { await model.load() } })
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded(let members) where members.isEmpty:
            EmptyStateView(systemImage: kind == .blocked ? "hand.raised" : "speaker.slash",
                           title: kind == .blocked ? "No one is blocked" : "No one is muted",
                           message: kind == .blocked
                               ? "Blocking someone from their profile hides you from each other everywhere in Roam."
                               : "Muting someone from their profile hides their places from your Friends tab. You still see their profile.")
                .frame(maxHeight: .infinity, alignment: .top)
        case .loaded(let members):
            List { Group {
                if let error = model.actionError {
                    Text(error).font(.footnote).foregroundStyle(Theme.disliked)
                        .accessibilityIdentifier("safety-error")
                }
                Section {
                    ForEach(members) { member in
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarView(member: member, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.displayName).font(.headline)
                                Text("@\(member.handle)").font(.subheadline).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button(kind == .blocked ? "Unblock" : "Unmute") { confirming = member }
                                .buttonStyle(PillButtonStyle())
                                .disabled(model.removing.contains(member.id))
                                .accessibilityIdentifier("safety-remove-\(member.handle)")
                        }
                        .accessibilityElement(children: .contain)
                    }
                } footer: {
                    Text(kind == .blocked ? "Blocked people can't see your profile, posts, lists or comments, and you can't see theirs."
                                          : "Muted people don't know they're muted.")
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .accessibilityIdentifier("safety-list")
        }
    }
}

/// Reports this member filed. They're stored for an operator; nothing here claims a review happened.
struct ReportHistoryView: View {
    @Environment(AppServices.self) private var services
    @State private var phase: LoadPhase<[ReportReceipt]> = .idle

    var body: some View {
        Group {
            switch phase {
            case .idle, .loading:
                SkeletonList(rows: 3).padding().frame(maxHeight: .infinity, alignment: .top)
            case .failed(let message):
                EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load your reports", message: message,
                               primaryTitle: "Try again", primaryAction: { Task { await load() } })
                    .frame(maxHeight: .infinity, alignment: .top)
            case .loaded(let reports) where reports.isEmpty:
                EmptyStateView(systemImage: "flag", title: "No reports",
                               message: "Reports you send about a place, post, comment, photo or member appear here with their status.")
                    .frame(maxHeight: .infinity, alignment: .top)
            case .loaded(let reports):
                List { Group {
                    Section {
                        ForEach(reports) { report in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(Self.targetTitle(report.targetKind)) · \(report.reason.title)").font(.headline)
                                Text("Sent \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                                Text(Self.statusText(report.status)).font(.subheadline)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("report-row")
                        }
                    } footer: {
                        Text("Reports are stored privately for Roam's operators; the people you report can't see them. A status changes only when someone actually reviews a report.")
                    }
                }
                .listRowBackground(Roam.paperRaised)
                }
            }
        }
        .navigationTitle("Your reports")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.groupedCanvas)
        .task { await load() }
        .screenIdentifier("report-history")
    }

    private func load() async {
        if phase.value == nil { phase = .loading }
        do {
            phase = .loaded(try await services.social.myReports())
        } catch {
            if phase.value == nil { phase = .failed(error.roamMessage) }
        }
    }

    static func targetTitle(_ kind: String) -> String {
        switch kind {
        case "experience": return "Place"
        case "activity": return "Post"
        case "comment": return "Comment"
        case "media": return "Photo"
        case "member": return "Person"
        case "visit": return "Visit"
        default: return "Report"
        }
    }

    static func statusText(_ status: String) -> String {
        switch status {
        case "reviewing": return "Being reviewed"
        case "resolved": return "Reviewed and resolved"
        case "dismissed": return "Reviewed, no action taken"
        default: return "Received, not yet reviewed"
        }
    }
}
