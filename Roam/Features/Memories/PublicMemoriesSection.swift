import Foundation
import Observation
import SwiftUI

/// Visit-backed public memories for one experience. They outlive rating activity, so removing a
/// ranking keeps notes/photos reachable here. Refresh failure keeps the acknowledged page.
@MainActor
@Observable
final class PublicMemoriesModel {
    let experienceID: UUID
    private(set) var memories: [PublicMemory] = []
    private(set) var hasLoaded = false
    private(set) var isLoading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    private(set) var pageError: String?
    private(set) var nextCursor: String?
    private(set) var authError: RoamError?
    private let service: any MemoryService
    private var generation = 0

    init(experienceID: UUID, service: any MemoryService) {
        self.experienceID = experienceID
        self.service = service
    }

    func load() async {
        generation += 1
        let token = generation
        isLoading = true
        defer { if token == generation { isLoading = false } }
        do {
            let page = try await service.publicMemories(experienceID: experienceID, cursor: nil)
            guard token == generation, !Task.isCancelled else { return }
            memories = page.items
            nextCursor = page.nextCursor
            hasLoaded = true
            error = nil
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            record(error)
        }
    }

    func loadMore() async {
        guard !loadingMore, !isLoading, let cursor = nextCursor else { return }
        let token = generation
        loadingMore = true
        defer { if token == generation { loadingMore = false } }
        do {
            let page = try await service.publicMemories(experienceID: experienceID, cursor: cursor)
            guard token == generation, nextCursor == cursor, !Task.isCancelled else { return }
            var seen = Set(memories.map(\.id))
            memories += page.items.filter { seen.insert($0.id).inserted }
            nextCursor = page.nextCursor
            pageError = nil
        } catch {
            guard token == generation, !(error is CancellationError) else { return }
            pageError = error.roamMessage
            if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
        }
    }

    private func record(_ error: Error) {
        self.error = error.roamMessage
        if let error = error as? RoamError, error == .sessionExpired || error == .notSignedIn { authError = error }
    }
}

/// "From travellers": other members' memories. Your own Visits are listed under Your memories.
struct PublicMemoriesSection: View {
    let model: PublicMemoriesModel
    let onOpenPhotos: (UUID?) -> Void
    let onReport: (ReportTarget) -> Void
    /// Friends' entries, already shown in their own section above.
    var excludedIDs: Set<UUID> = []

    private var others: [PublicMemory] { model.memories.filter { !$0.isOwn && !excludedIDs.contains($0.id) } }

    private var header: some View {
        Text("From everyone else").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var allPhotos: some View {
        if model.memories.contains(where: { !$0.media.isEmpty }) {
            Button("All photos") { onOpenPhotos(nil) }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: Theme.minimumHitTarget)
                .accessibilityIdentifier("detail-all-photos")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            ViewThatFits(in: .horizontal) {
                HStack { header; Spacer(minLength: 0); allPhotos }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { header; allPhotos }
            }
            if let error = model.error {
                InlineRetryView(message: model.hasLoaded ? "Couldn't refresh memories. \(error)" : error) { Task { await model.load() } }
                    .accessibilityIdentifier("memories-error")
            }
            if !model.hasLoaded && model.isLoading {
                SkeletonList(rows: 2)
            } else if model.hasLoaded && others.isEmpty {
                Text("Nobody else has shared anything about this place yet.")
                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("memories-empty")
            } else {
                ForEach(others) { memory in
                    PublicMemoryCard(memory: memory,
                                     onOpenPhotos: { onOpenPhotos(memory.id) }, onReport: { onReport(.visit(memory.id)) })
                    Divider()
                }
                if let pageError = model.pageError {
                    InlineRetryView(message: pageError, retryTitle: "Load more") { Task { await model.loadMore() } }
                } else if model.nextCursor != nil {
                    Button(model.loadingMore ? "Loading…" : "Show more memories") { Task { await model.loadMore() } }
                        .disabled(model.loadingMore)
                        .frame(minHeight: Theme.minimumHitTarget)
                        .accessibilityIdentifier("memories-more")
                }
            }
        }
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail-public-memories")
    }
}

/// What friends said about this place, kept apart from other travellers.
struct FriendMemoriesSection: View {
    let memories: [PublicMemory]
    let onOpenPhotos: (UUID?) -> Void
    let onReport: (ReportTarget) -> Void

    var body: some View {
        if memories.isEmpty {
            Label("None of your friends have been here yet.", systemImage: "person.2")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
                .accessibilityIdentifier("friend-memories-empty")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("From your friends").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
                ForEach(memories) { memory in
                    PublicMemoryCard(memory: memory,
                                     onOpenPhotos: { onOpenPhotos(memory.id) }, onReport: { onReport(.visit(memory.id)) })
                    if memory.id != memories.last?.id { Divider() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .roamCard()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail-friend-memories")
        }
    }
}

struct PublicMemoryCard: View {
    let memory: PublicMemory
    let onOpenPhotos: () -> Void
    let onReport: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    AvatarView(member: memory.author, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(memory.author.displayName).font(.subheadline.weight(.semibold))
                        Text(memory.visitDate.date.map { "Visited \($0.displayString)" } ?? "Visit date unknown")
                            .font(.caption).foregroundStyle(Theme.secondaryText)
                    }
                }
                .frame(minHeight: Theme.minimumHitTarget, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(memory.author.displayName), \(memory.visitDate.displayString)")
                Spacer(minLength: 0)
                if Score.isShown, let score = memory.score {
                    Text(score.formatted)
                        .font(.system(.body, design: .rounded).bold())
                        .monospacedDigit()
                        .frame(minHeight: Theme.minimumHitTarget)
                        .accessibilityLabel("Rated \(score.formatted) out of 5")
                }
            }
            if !memory.publicNote.isEmpty {
                Text(memory.publicNote)
                    .font(.body)
                    .lineLimit(expanded ? nil : 4)
                    .fixedSize(horizontal: false, vertical: true)
                if memory.publicNote.count > 180 && !expanded {
                    Button("See more") { expanded = true }.font(.footnote.weight(.semibold))
                }
            }
            if !memory.media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(Array(memory.media.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, media in
                            Button(action: onOpenPhotos) {
                                RemoteImageView(path: media.path, accessibilityLabel: "Photo \(index + 1) from \(memory.author.displayName)'s visit")
                                    .frame(width: 120, height: 96)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("memory-photo-\(memory.id.uuidString)-\(index)")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memory-card-\(memory.id.uuidString)")
    }
}
