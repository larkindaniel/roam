import MapKit
import Observation
import SwiftUI

extension PlaceMapItem {
    /// Each place appears once, in its most advanced state.
    static func items(been: [ExperienceSummary], planned: [ExperienceSummary], wishlist: [ExperienceSummary]) -> [PlaceMapItem] {
        var items: [UUID: PlaceMapItem] = [:]
        for place in wishlist { items[place.id] = PlaceMapItem(experience: place, state: .wishlist) }
        for place in planned { items[place.id] = PlaceMapItem(experience: place, state: .planned) }
        for place in been { items[place.id] = PlaceMapItem(experience: place, state: .visited) }
        return items.values.sorted { $0.experience.name < $1.experience.name }
    }
}

/// A trip with what's needed to show it: a picture and the date it sorts by.
struct MyPlacesTrip: Identifiable, Hashable {
    var summary: TripSummary
    var coverURL: URL?
    var latestVisit: LocalDate?

    var id: UUID { summary.id }
    var sortDate: LocalDate? { summary.endDate ?? summary.startDate ?? latestVisit }

    /// Soonest first when looking ahead, most recent first when looking back. Undated trips go last.
    static func chronological(_ trips: [MyPlacesTrip], newestFirst: Bool) -> [MyPlacesTrip] {
        trips.sorted { lhs, rhs in
            switch (lhs.sortDate, rhs.sortDate) {
            case let (left?, right?) where left != right: return newestFirst ? left > right : left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.summary.name < rhs.summary.name
            }
        }
    }
}

@MainActor
@Observable
final class MyPlacesModel {
    private(set) var pins: [PlaceMapItem] = []
    private(set) var upcoming: [MyPlacesTrip] = []
    private(set) var past: [MyPlacesTrip] = []
    private(set) var hasLoaded = false
    private(set) var error: String?
    private let services: AppServices
    private let ownerID: UUID

    init(services: AppServices, ownerID: UUID) {
        self.services = services
        self.ownerID = ownerID
    }

    func load() async {
        do {
            async let been = services.lists.been(ownerID: ownerID)
            async let wishlist = services.lists.want(ownerID: ownerID)
            async let summaries = services.plans.myTrips()
            let (beenEntries, wishlistEntries, trips) = try await (been, wishlist, summaries)
            var planned: [ExperienceSummary] = []
            var loaded: [MyPlacesTrip] = []
            for trip in trips {
                let detail = try? await services.plans.trip(id: trip.id)
                let entries = (try? await services.plans.tripUpdates(ownerID: ownerID, tripID: trip.id)) ?? []
                planned += detail?.places.filter(\.isPlanned).map(\.experience) ?? []
                loaded.append(MyPlacesTrip(summary: trip, coverURL: detail?.places.compactMap(\.experience.photoURL).first,
                                           latestVisit: entries.compactMap(\.visitDate.date).max()))
            }
            pins = PlaceMapItem.items(been: beenEntries.map(\.experience), planned: planned, wishlist: wishlistEntries.map(\.experience))
            upcoming = MyPlacesTrip.chronological(loaded.filter { $0.summary.status != .past }, newestFirst: false)
            past = MyPlacesTrip.chronological(loaded.filter { $0.summary.status == .past }, newestFirst: true)
            hasLoaded = true
            error = nil
        } catch {
            self.error = error.roamMessage
        }
    }
}

/// My Places tab: your map, then upcoming trips, then past trips.
struct MyPlacesRootView: View {
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var model: MyPlacesModel?
    @State private var creating: TripDraft?
    @State private var showsCoachmark = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let model, model.hasLoaded {
                    mapCard(model.pins)
                    upcomingSection(model.upcoming)
                    pastSection(model.past)
                    moreSection
                } else if let error = model?.error {
                    InlineRetryView(message: error) { Task { await model?.load() } }
                } else {
                    SkeletonList(rows: 4)
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .background(Roam.paper)
        .navigationTitle("My Places")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ProfileAvatarButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { openWishlist() } label: { Image(systemName: "bookmark") }
                    .accessibilityLabel("Wishlist")
                    .accessibilityIdentifier("open-wishlist")
            }
            LogPlaceToolbarFallback()
        }
        .sheet(item: $creating) { draft in
            TripEditorSheet(draft: draft) { Task { await model?.load() } }.presentationBackground(Roam.paper)
        }
        .task {
            if model == nil, let me = session.userID { model = MyPlacesModel(services: services, ownerID: me) }
            await model?.load()
        }
        .onChange(of: library.revision) { _, _ in Task { await model?.load() } }
        .onChange(of: router.path(for: .myPlaces).isEmpty) { _, isRoot in if isRoot { Task { await model?.load() } } }
        .refreshable { await model?.load() }
        .overlay {
            if session.profile?.hasSeenBeenIntro == false {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    BeenIntroCard {
                        Task {
                            await session.markBeenIntroSeen()
                            showsCoachmark = true
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsCoachmark { LogCoachmark { showsCoachmark = false } }
        }
        .screenIdentifier("myplaces-root")
    }

    private func openWishlist() {
        if let me = session.userID { router.push(.memberList(me, .want)) }
    }

    private func mapCard(_ pins: [PlaceMapItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PlaceMapView(items: pins) { router.push(.experience($0)) }
                .id(pins.map(\.id))
                .frame(height: 300)
            PlaceMapLegend().padding(Theme.Spacing.m)
        }
        .background(Roam.paperRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Roam.rule))
        .accessibilityIdentifier("myplaces-map")
    }

    private func upcomingSection(_ trips: [MyPlacesTrip]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                Text("Upcoming trips").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { creating = TripDraft() } label: { PillLabel(title: "New trip", systemImage: "plus") }
                    .buttonStyle(PillButtonStyle())
                    .accessibilityIdentifier("trip-new")
            }
            if trips.isEmpty {
                Text("No upcoming trips yet.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("trips-empty")
            }
            ForEach(trips) { trip in
                Button { router.push(.trip(trip.id)) } label: {
                    PhotoCard(url: trip.coverURL, label: "Photo from \(trip.summary.name)", placeholderSymbol: "suitcase", height: 170) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(trip.summary.name).font(.roamTitle()).foregroundStyle(Roam.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: Theme.Spacing.s)
                            TripStatusPill(status: trip.summary.status)
                        }
                        Text(TripText.summaryLine(trip.summary)).font(.footnote).foregroundStyle(Roam.inkMuted).multilineTextAlignment(.leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("trip-\(trip.summary.name)")
            }
        }
    }

    private func pastSection(_ trips: [MyPlacesTrip]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Past trips").font(.roamTitle()).accessibilityAddTraits(.isHeader)
            if trips.isEmpty {
                Text("Trips you've finished appear here.").font(.subheadline).foregroundStyle(Roam.inkMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(trips) { trip in
                        Button { router.push(.trip(trip.id)) } label: { pastRow(trip) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("trip-\(trip.summary.name)")
                        if trip.id != trips.last?.id { Divider() }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    private func pastRow(_ trip: MyPlacesTrip) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Roam.fill
                .frame(width: 52, height: 52)
                .overlay {
                    if let url = trip.coverURL {
                        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Roam.fill }
                    } else {
                        Image(systemName: "suitcase").foregroundStyle(Roam.inkMuted)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.summary.name).font(.headline).foregroundStyle(Roam.ink)
                Text(trip.sortDate?.displayString ?? "No dates").font(.footnote).foregroundStyle(Roam.inkMuted)
                Text("\(trip.summary.visitedCount) \(trip.summary.visitedCount == 1 ? "place" : "places") visited").font(.footnote).foregroundStyle(Roam.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .padding(.vertical, Theme.Spacing.s)
        .contentShape(Rectangle())
    }

    private var moreSection: some View {
        VStack(spacing: 0) {
            Button { if let me = session.userID { router.push(.memberList(me, .been)) } } label: { linkRow("All places you've been", symbol: "mappin.and.ellipse") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-been")
            Divider()
            Button { router.push(.lists) } label: { linkRow("Custom lists", symbol: "list.bullet") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-lists")
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    private func linkRow(_ title: String, symbol: String) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
        }
        .foregroundStyle(Roam.ink)
        .frame(minHeight: Theme.minimumHitTarget)
        .contentShape(Rectangle())
    }
}
