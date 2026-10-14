import MapKit
import SwiftUI

@MainActor
@Observable
final class ExperienceDetailModel {
    let experienceID: UUID
    private(set) var phase: LoadPhase<ExperienceDetail> = .idle
    private(set) var refreshError: String?
    private let services: AppServices

    init(experienceID: UUID, services: AppServices) {
        self.experienceID = experienceID
        self.services = services
    }

    var detail: ExperienceDetail? { phase.value }

    /// Refresh keeps the current content on failure.
    func load() async {
        if detail == nil { phase = .loading }
        do {
            phase = .loaded(try await services.experiences.detail(experienceID: experienceID))
            refreshError = nil
        } catch {
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
    @State private var model: ExperienceDetailModel?
    @State private var reportTarget: ReportTarget?
    @State private var reportReason: ReportReason?

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
                ToolbarItem(placement: .topBarTrailing) { overflowMenu(detail) }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, title: reportReason == .incorrectPlaceOrCategory ? "Report category issue" : "Report a problem",
                        suggestedReason: reportReason)
        }
        .task {
            if model == nil { model = ExperienceDetailModel(experienceID: experienceID, services: services) }
            await model?.load()
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        .screenIdentifier("experience-detail")
    }

    private func content(_ detail: ExperienceDetail) -> some View {
        let summary = detail.summary
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                hero(detail)
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
                            Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                            Text(summary.areaLine).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if detail.isLocality {
                        Label("Town or city — logged as a Day Trip destination", systemImage: "signpost.right").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                actionRow(detail)
                scores(detail)
                memories(detail)
                about(detail)
                activity(detail)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .refreshable { await model?.load() }
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

    @ViewBuilder private func actionRow(_ detail: ExperienceDetail) -> some View {
        let id = detail.summary.id
        let rated = detail.myRating != nil
        HStack(spacing: Theme.Spacing.s) {
            if rated {
                Label("Already been", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.liked)
                    .frame(minHeight: Theme.minimumHitTarget)
                    .accessibilityIdentifier("detail-already-been")
            } else {
                switch library.saveState(for: id) {
                case .pending(let target):
                    Button {} label: { HStack { ProgressView().controlSize(.small); Text(target ? "Saving" : "Removing") } }
                        .buttonStyle(PillButtonStyle(isSelected: target))
                        .disabled(true)
                case .saved:
                    Button { Task { await library.setBookmark(id, saved: false) } } label: { PillLabel(title: "Saved to Want to Go", systemImage: "bookmark.fill") }
                        .buttonStyle(PillButtonStyle(isSelected: true))
                        .accessibilityIdentifier("detail-save")
                default:
                    Button { Task { await library.setBookmark(id, saved: true) } } label: { PillLabel(title: "Want to Go", systemImage: "bookmark") }
                        .buttonStyle(PillButtonStyle(isSelected: false))
                        .accessibilityIdentifier("detail-save")
                }
            }
            Spacer(minLength: 0)
        }
        if let error = library.lastError {
            InlineRetryView(message: error, retryTitle: "Dismiss") { library.clearError() }
        }
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
                            if rating.groupSize > 1 { Text("Tied with \(rating.groupSize - 1) other\(rating.groupSize == 2 ? "" : "s")").font(.caption).foregroundStyle(.secondary) }
                            SentimentTag(sentiment: rating.sentiment)
                        }
                    } else {
                        Text(detail.myVisits.isEmpty ? "Not rated" : "Unranked memory").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail-your-score")
            VStack(alignment: .leading, spacing: 6) {
                Text("Following").font(.headline)
                HStack(spacing: Theme.Spacing.m) {
                    ScoreBadge(score: detail.summary.followingScore, source: .following(count: detail.summary.followingCount), size: 52, showsLabel: false)
                    Text(detail.summary.followingCount == 0 ? "No following ratings"
                         : "\(detail.summary.followingCount) \(detail.summary.followingCount == 1 ? "person" : "people") you follow")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail-following-score")
        }
        .roamCard()
    }

    @ViewBuilder private func memories(_ detail: ExperienceDetail) -> some View {
        if !detail.myVisits.isEmpty || detail.hasPrivateNote {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Your memories").font(.roamTitle(.title3))
                ForEach(detail.myVisits) { visit in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(visit.visitDate.displayString).font(.subheadline.weight(.semibold))
                        if !visit.publicNote.isEmpty { Text(visit.publicNote).font(.body) }
                        if !visit.media.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack { ForEach(visit.media) { RemoteImageView(path: $0.path).frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10)) } }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    Divider()
                }
                if detail.hasPrivateNote {
                    Label("You have a private note (only you can see it)", systemImage: "lock.fill").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .roamCard()
            .accessibilityIdentifier("detail-memories")
        }
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
                Label("Address not available", systemImage: "mappin.slash").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.s) {
                Button { openInMaps(detail) } label: { PillLabel(title: "Directions", systemImage: "arrow.triangle.turn.up.right.diamond") }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("detail-directions")
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
            Text(detail.provider == .mapkit ? "Place details from Apple Maps." : "Fictional test place (fixture data).")
                .font(.caption).foregroundStyle(.secondary)
        }
        .roamCard()
    }

    @ViewBuilder private func activity(_ detail: ExperienceDetail) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("From travellers").font(.roamTitle(.title3))
            if detail.publicActivity.isEmpty {
                Text("No public visits yet. When people rank or revisit this place, their notes and photos appear here.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(detail.publicActivity) { item in
                    ActivityCardView(item: item, onOpenAuthor: { router.push(.member(item.author.id)) }, onOpen: { router.push(.activity(item.id)) })
                    Divider()
                }
            }
        }
        .roamCard()
        .accessibilityIdentifier("detail-activity")
    }

    private func overflowMenu(_ detail: ExperienceDetail) -> some View {
        Menu {
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
