import MapKit
import SwiftUI

@MainActor
@Observable
final class ExperienceDetailModel {
    let experienceID: UUID
    private(set) var phase: LoadPhase<ExperienceDetail> = .idle
    private(set) var refreshError: String?
    private let services: AppServices
    private var generation = 0

    init(experienceID: UUID, services: AppServices) {
        self.experienceID = experienceID
        self.services = services
    }

    var detail: ExperienceDetail? { phase.value }

    /// Refresh keeps the current content on failure.
    func load() async {
        generation += 1
        let token = generation
        if detail == nil { phase = .loading }
        do {
            let detail = try await services.experiences.detail(experienceID: experienceID)
            try Task.checkCancellation()
            guard token == generation else { return }
            phase = .loaded(detail)
            refreshError = nil
        } catch is CancellationError {
            guard token == generation else { return }
            if detail == nil { phase = .idle }
        } catch {
            guard token == generation else { return }
            if detail == nil { phase = .failed(error.roamMessage) } else { refreshError = error.roamMessage }
        }
    }
}

/// S06 experience detail.
struct ExperienceDetailView: View {
    let experienceID: UUID

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var friendMemories: [PublicMemory] = []
    @State private var model: ExperienceDetailModel?
    @State private var memoriesModel: PublicMemoriesModel?
    @State private var editingVisit: Visit?
    @State private var showsPrivateNote = false
    @State private var reportTarget: ReportTarget?
    @State private var reportReason: ReportReason?
    @State private var pendingDeletion: DetailDeletion?
    @State private var failedDeletion: DetailDeletion?
    @State private var actionError: String?
    @State private var deleting = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            switch model?.phase ?? .idle {
            case .idle, .loading:
                ScrollView { SkeletonList(rows: 6).padding() }
                    .accessibilityIdentifier("experience-loading")
            case .failed(let message):
                ScrollView {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn't load this place", message: message,
                                   primaryTitle: "Try again", primaryAction: { Task { await model?.load() } })
                }
            case .loaded(let detail):
                content(detail)
            }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(model?.detail?.summary.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let detail = model?.detail {
                ToolbarItem(placement: .topBarTrailing) {
                    // Native text share: public values, an Apple Maps link and only your own current score.
                    ShareLink(item: ShareText.experience(detail.summary, ownRating: detail.myRating)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share \(detail.summary.name)")
                    .accessibilityIdentifier("share-experience")
                }
                ToolbarItem(placement: .topBarTrailing) { overflowMenu(detail) }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, title: reportTitle(target), suggestedReason: reportReason)
        }
        .sheet(item: $editingVisit) { visit in
            VisitMemoryEditor(visit: visit, destinationTimeZone: model?.detail?.timeZoneIdentifier) { _ in
                library.noteChanged()
                Task { await reload() }
            }
        }
        .sheet(isPresented: $showsPrivateNote) {
            PrivateNoteEditor(experienceID: experienceID) { Task { await model?.load() } }
        }
        .alert(pendingDeletion?.title ?? "Confirm removal", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }), presenting: pendingDeletion) { action in
                Button(action.buttonTitle, role: .destructive) { Task { await confirmDeletion(action) } }
                    .accessibilityIdentifier(action.confirmID)
                Button("Cancel", role: .cancel) {}
            } message: { action in Text(action.message) }
        .safeAreaInset(edge: .bottom) {
            if let actionError {
                InlineRetryView(message: actionError, retryTitle: failedDeletion == nil ? "Dismiss" : "Try again") {
                    if let failedDeletion { Task { await confirmDeletion(failedDeletion) } } else { self.actionError = nil }
                }.padding().background(.bar).accessibilityIdentifier("detail-action-error")
            }
        }
        .task {
            if let owner = session.userID {
                let name = "detail-pending-delete-\(experienceID.uuidString)"
                if let retained = services.storage.read(DetailDeletion.self, name: name, userID: owner) {
                    failedDeletion = retained
                    actionError = "A removal response was interrupted. Retry the same request to confirm its result."
                }
            }
            if model == nil { model = ExperienceDetailModel(experienceID: experienceID, services: services) }
            if memoriesModel == nil { memoriesModel = PublicMemoriesModel(experienceID: experienceID, service: services.memories) }
            await reload()
        }
        .onChange(of: library.revision) { _, _ in Task { await reload() } }
        .onChange(of: memoriesModel?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("experience-detail")
    }

    private func content(_ detail: ExperienceDetail) -> some View {
        let summary = detail.summary
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if summary.photoURL != nil {
                    PlacePhotoView(url: summary.photoURL, credit: summary.photoCredit, label: "Photo of \(summary.name)", height: 220)
                        .padding(.top, Theme.Spacing.s)
                } else {
                    hero(detail)
                }
                if let refreshError = model?.refreshError {
                    InlineRetryView(message: refreshError) { Task { await model?.load() } }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text(summary.name)
                        .font(.roamDisplay(.largeTitle))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    HStack(spacing: Theme.Spacing.s) {
                        CategoryBadge(category: detail.myRating?.category ?? summary.category)
                        if !summary.areaLine.isEmpty {
                            Text("·").foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
                            Text(summary.areaLine).font(.subheadline).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    if detail.isLocality {
                        Label("Town or city — logged as a Day Trip destination", systemImage: "signpost.right").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
                actionRow(detail)
                FriendMemoriesSection(memories: friendMemories, onOpenAuthor: { router.push(.member($0)) },
                                      onOpenPhotos: { router.push(.gallery(experienceID: experienceID, visitID: $0)) },
                                      onReport: { target in reportReason = nil; reportTarget = target })
                scores(detail)
                if summary.photoURL != nil { hero(detail) }
                memories(detail)
                privateNote(detail)
                about(detail)
                if let memoriesModel, !memoriesModel.hasLoaded || memoriesModel.memories.contains(where: { !$0.isOwn && !friendMemories.map(\.id).contains($0.id) }) {
                    PublicMemoriesSection(model: memoriesModel, onOpenAuthor: { router.push(.member($0)) },
                                          onOpenPhotos: { router.push(.gallery(experienceID: experienceID, visitID: $0)) },
                                          onReport: { target in reportReason = nil; reportTarget = target },
                                          excludedIDs: Set(friendMemories.map(\.id)))
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        async let detail: Void = model?.load() ?? ()
        async let memories: Void = memoriesModel?.load() ?? ()
        async let friends = try? services.plans.friendMemories(experienceID: experienceID)
        let loadedFriends = await friends
        _ = await (detail, memories)
        if let loadedFriends { friendMemories = loadedFriends }
    }

    private func reportTitle(_ target: ReportTarget) -> String {
        if reportReason == .incorrectPlaceOrCategory { return "Report category issue" }
        if case .visit = target { return "Report memory" }
        return "Report a problem"
    }

    private func hero(_ detail: ExperienceDetail) -> some View {
        let coordinate = detail.summary.coordinate
        return Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: detail.isLocality ? 20_000 : 1_500,
                                                              longitudinalMeters: detail.isLocality ? 20_000 : 1_500)),
                   interactionModes: []) {
            Marker(detail.summary.name, systemImage: (detail.myRating?.category ?? detail.summary.category)?.symbolName ?? "mappin",
                   coordinate: coordinate)
                .tint(Theme.accent)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .padding(.top, Theme.Spacing.s)
        .accessibilityLabel("Map showing \(detail.summary.name)")
    }

    private func actionRow(_ detail: ExperienceDetail) -> some View {
        let id = detail.summary.id
        let rated = detail.myRating != nil
        let visited = rated || detail.summary.viewer.hasVisits
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                if visited || library.isBookmarked(id) { StatusMark(state: visited ? .visited : .wishlist) }
                Text(visited ? "You've been here" : (library.isBookmarked(id) ? "On your wishlist" : "Not on your lists yet"))
                    .font(.footnote).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier(visited ? "detail-already-been" : "detail-place-state")
            }
            HStack(spacing: Theme.Spacing.s) {
                actionTile(rated ? "Add visit" : "Log visit", symbol: "plus", prominent: true, identifier: rated ? "detail-add-visit" : "detail-log") {
                    Task { await openLog(rated ? .addVisit : .firstLog) }
                }
                .disabled(deleting || failedDeletion != nil)
                actionTile(library.isBookmarked(id) ? "Saved" : "Save", symbol: library.isBookmarked(id) ? "bookmark.fill" : "bookmark", identifier: "detail-save") {
                    Task { await library.setBookmark(id, saved: !library.isBookmarked(id)) }
                }
                .disabled(visited && !library.isBookmarked(id))
                actionTile("Directions", symbol: "arrow.triangle.turn.up.right.diamond", identifier: "detail-directions") { openInMaps(detail) }
                actionTile("Share", symbol: "square.and.arrow.up", identifier: "detail-recommend") {
                    router.sheet = .share(.place(id), title: detail.summary.name)
                }
            }
            HStack(spacing: Theme.Spacing.s) {
                Button { router.sheet = .addToTrip(experienceID: id, name: detail.summary.name) } label: { Label("Add to trip", systemImage: "suitcase") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("detail-add-to-trip")
                Button { router.sheet = .addToList(experienceID: id, name: detail.summary.name) } label: { Label("Add to list", systemImage: "list.bullet") }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule).accessibilityIdentifier("detail-add-to-list")
            }
            .font(.subheadline)
            if let error = library.lastError {
                InlineRetryView(message: error, retryTitle: "Dismiss") { library.clearError() }
            }
        }
    }

    private func actionTile(_ title: String, symbol: String, prominent: Bool = false, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? Roam.onInk : Roam.ink)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(prominent ? Roam.ink : Roam.fill))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func scores(_ detail: ExperienceDetail) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: 6) {
                Text("You").font(.headline)
                HStack(spacing: Theme.Spacing.m) {
                    ScoreBadge(score: detail.myRating?.score, source: .you, size: 52, showsLabel: false)
                    if let rating = detail.myRating {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("#\(rating.rank) of \(rating.categoryCount) in \(rating.category.title)").font(.subheadline.weight(.semibold))
                            if rating.groupSize > 1 { Text("Tied with \(rating.groupSize - 1) other\(rating.groupSize == 2 ? "" : "s")").font(.caption).foregroundStyle(Theme.secondaryText) }
                            SentimentTag(sentiment: rating.sentiment)
                        }
                    } else {
                        Text(detail.myVisits.isEmpty ? "Not rated" : "Unranked memory").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail-your-score")
            VStack(alignment: .leading, spacing: 6) {
                Text("Friends").font(.headline)
                HStack(spacing: Theme.Spacing.m) {
                    ScoreBadge(score: detail.summary.followingScore, source: .following(count: detail.summary.followingCount), size: 52, showsLabel: false)
                    Text(detail.summary.followingCount == 0 ? "No friend ratings"
                         : "\(detail.summary.followingCount) \(detail.summary.followingCount == 1 ? "friend" : "friends") rated this")
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail-following-score")
        }
        .roamCard()
    }

    @ViewBuilder private func memories(_ detail: ExperienceDetail) -> some View {
        if !detail.myVisits.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Your memories").font(.roamTitle(.title3))
                ForEach(detail.myVisits) { visit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.visitDate.displayString).font(.subheadline.weight(.semibold))
                        if !visit.publicNote.isEmpty { Text(visit.publicNote).font(.body) }
                        if !visit.media.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(Array(visit.media.sorted { $0.position < $1.position }.enumerated()), id: \.element.id) { index, media in
                                        Button { router.push(.gallery(experienceID: experienceID, visitID: visit.id)) } label: {
                                            RemoteImageView(path: media.path, accessibilityLabel: "Photo \(index + 1) from your visit")
                                                .frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("detail-visit-photo-\(visit.id.uuidString)-\(index)")
                                    }
                                }
                            }
                        }
                        HStack(spacing: Theme.Spacing.l) {
                            Button { editingVisit = visit } label: { Label("Edit", systemImage: "pencil") }
                                .frame(minHeight: Theme.minimumHitTarget)
                                .disabled(deleting || failedDeletion != nil)
                                .accessibilityLabel("Edit note, date and photos for this visit")
                                .accessibilityIdentifier("detail-edit-visit-\(visit.id.uuidString)")
                            Button(role: .destructive) {
                                pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: visit.id,
                                                                 lastVisit: detail.myVisits.count == 1 && detail.myRating != nil)
                            } label: { Text("Delete visit").foregroundStyle(Theme.disliked) }
                            .frame(minHeight: Theme.minimumHitTarget)
                            .disabled(deleting || failedDeletion != nil)
                            .accessibilityIdentifier("detail-delete-visit-\(visit.id.uuidString)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .contain)
                    Divider()
                }
            }
            .roamCard()
            .accessibilityIdentifier("detail-memories")
        }
    }

    /// Owner-only note, separate from public visit notes and never part of any public projection.
    private func privateNote(_ detail: ExperienceDetail) -> some View {
        Button { showsPrivateNote = true } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "lock.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.hasPrivateNote ? "Private note" : "Add a private note").font(.subheadline.weight(.semibold))
                    Text("Only you can see this.").font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.secondaryText).accessibilityHidden(true)
            }
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .roamCard()
        .accessibilityIdentifier("detail-private-note")
    }

    private func about(_ detail: ExperienceDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("About").font(.roamTitle(.title3))
            if detail.providerStatus == .unavailable {
                Label("This listing is no longer available in Apple Maps. Your memories stay here.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.fine)
            }
            if let address = detail.address {
                Label(address, systemImage: "mappin.and.ellipse").font(.subheadline).textSelection(.enabled)
            } else {
                Label("Address not available", systemImage: "mappin.slash").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            // Pills never shrink, so a row that cannot fit (large text) stacks instead of widening the screen.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.s) { utilityPills(detail) }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { utilityPills(detail) }
            }
            if detail.provider != .fixture {
                Text(detail.provider == .mapkit ? "Place details from Apple Maps." : "Added by someone on Roam.")
                    .font(.caption).foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roamCard()
    }

    @ViewBuilder private func utilityPills(_ detail: ExperienceDetail) -> some View {
        if let website = detail.website {
            Button { openURL(website) } label: { PillLabel(title: "Website", systemImage: "safari") }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("detail-website")
        }
        if let phone = detail.phone, let url = URL(string: "tel:\(phone.filter { $0.isNumber || $0 == "+" })") {
            Button { openURL(url) } label: { PillLabel(title: "Call", systemImage: "phone") }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("detail-call")
        }
    }

    private func overflowMenu(_ detail: ExperienceDetail) -> some View {
        Menu {
            if detail.myRating != nil {
                Button { Task { await openLog(.rerank) } } label: { Label("Rank again", systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(deleting || failedDeletion != nil)
                    .accessibilityIdentifier("detail-rerank")
                Button(role: .destructive) {
                    pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: nil, lastVisit: false)
                } label: { Label("Remove ranking", systemImage: "minus.circle") }
                .disabled(deleting || failedDeletion != nil)
                .accessibilityIdentifier("detail-remove-ranking")
            }
            Button { openInMaps(detail) } label: { Label("Open in Maps", systemImage: "map") }
            if detail.categoryLocked {
                Button {
                    reportReason = .incorrectPlaceOrCategory
                    reportTarget = .experience(detail.summary.id)
                } label: { Label("Report category issue", systemImage: "tag.slash") }
            }
            Button {
                reportReason = nil
                reportTarget = .experience(detail.summary.id)
            } label: { Label("Report a problem", systemImage: "flag") }
        } label: {
            Image(systemName: "ellipsis.circle").accessibilityLabel("More")
        }
        .accessibilityIdentifier("detail-overflow")
    }

    private func openLog(_ mode: LogRequest.Mode) async {
        do { router.sheet = .log(try await services.makeLogRequest(experienceID: experienceID, mode: mode)) }
        catch { actionError = session.handle(error) }
    }

    private func confirmDeletion(_ action: DetailDeletion) async {
        guard !deleting, let owner = session.userID else { return }
        let name = "detail-pending-delete-\(experienceID.uuidString)"
        deleting = true
        defer { deleting = false }
        actionError = nil
        do {
            try services.storage.write(action, name: name, userID: owner)
            if let visitID = action.visitID {
                let result = try await services.ranking.deleteVisit(visitID: visitID, operationID: action.operationID, allowRatingRemoval: action.lastVisit)
                guard owner == session.userID else { return }
                if result.removedRating { library.applyRatingRemoved(experienceID) }
            } else {
                try await services.ranking.removeRating(experienceID: experienceID, operationID: action.operationID)
                guard owner == session.userID else { return }
                library.applyRatingRemoved(experienceID)
            }
            services.storage.remove(name: name, userID: owner)
            failedDeletion = nil
            await library.refresh()
            library.noteChanged()
            await model?.load()
        } catch {
            guard owner == session.userID else { return }
            if let error = error as? RoamError, error == .lastVisitConfirmationRequired, let visitID = action.visitID {
                services.storage.remove(name: name, userID: owner)
                failedDeletion = nil
                pendingDeletion = DetailDeletion(experienceID: experienceID, visitID: visitID, lastVisit: true)
                await model?.load()
                return
            }
            if let error = error as? RoamError, !error.isRetryable {
                services.storage.remove(name: name, userID: owner)
                failedDeletion = nil
            } else { failedDeletion = action }
            actionError = session.handle(error)
        }
    }

    /// Hands off to Apple Maps; cancelling there leaves Roam unchanged.
    private func openInMaps(_ detail: ExperienceDetail) {
        Task { @MainActor in
            var item: MKMapItem?
            if detail.provider == .mapkit, let raw = detail.summary.providerPlaceID, let identifier = MKMapItem.Identifier(rawValue: raw) {
                item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
            }
            let mapItem = item ?? {
                let fallback = MKMapItem(placemark: MKPlacemark(coordinate: detail.summary.coordinate))
                fallback.name = detail.summary.name
                return fallback
            }()
            mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
        }
    }
}

extension ReportTarget: Identifiable {
    var id: String { "\(kind)-\(targetID.uuidString)" }
}

private struct DetailDeletion: Codable, Identifiable {
    let operationID: UUID
    let experienceID: UUID
    let visitID: UUID?
    let lastVisit: Bool
    var id: UUID { operationID }
    init(experienceID: UUID, visitID: UUID?, lastVisit: Bool) {
        operationID = UUID(); self.experienceID = experienceID; self.visitID = visitID; self.lastVisit = lastVisit
    }
    var title: String { visitID == nil ? "Remove ranking?" : (lastVisit ? "Delete your last visit?" : "Delete visit?") }
    var buttonTitle: String { visitID == nil ? "Remove ranking" : "Delete visit" }
    var confirmID: String { visitID == nil ? "confirm-remove-ranking" : (lastVisit ? "confirm-delete-last-visit" : "confirm-delete-visit") }
    var message: String {
        if visitID == nil { return "Your visits, notes and photos will stay; your ranking and rating activity will be removed." }
        if lastVisit { return "This deletes the visit, its public note and photos, and its activity. Because it is your last visit, your ranking and rating activity will also be removed." }
        return "This deletes this visit, its public note and photos, and its activity. Other visits stay. Removing the last visit of a ranking requires a separate confirmation."
    }
}
