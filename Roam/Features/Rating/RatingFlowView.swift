import PhotosUI
import CoreLocation
import SwiftUI

struct RatingFlowView: View {
    let request: LogRequest
    var onSaved: (RatingFlowCompletion) -> Void = { _ in }
    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var account
    @Environment(\.dismiss) private var dismiss
    @State private var feeling: Sentiment?
    @State private var model: RatingFlowModel?
    @State private var showsCancel = false
    @State private var showsDate = false
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var trips: [TripSummary] = []
    @State private var home: Destination?
    /// Saving straight from a comparison: the log form stays away while it saves and closes.
    @State private var fromComparison = false

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) }
                else { ProgressView("Loading…") }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let model else { dismiss(); return }
                        if model.completion != nil { dismiss() }
                        else if model.hasNonemptyDraft { showsCancel = true }
                        else { close(model) }
                    }
                    label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .disabled(model?.isBusy == true)
                    .accessibilityIdentifier("rating-close")
                    // No drafts: closing with something filled in asks to discard it, popping up from the ×. Only a save
                    // that was sent but not confirmed is kept, so it can be checked safely.
                    .confirmationDialog("Discard this log?", isPresented: $showsCancel, titleVisibility: .visible) {
                        if model?.hasPendingSave == true {
                            Button("Keep it to check later") { model?.keepDraft(); dismiss() }
                        } else {
                            Button("Discard", role: .destructive) { if let model { close(model) } }
                        }
                        Button("Keep editing", role: .cancel) {}
                    } message: {
                        if model?.hasPendingSave == true { Text("Saving wasn't confirmed yet.") }
                    }
                }
            }
            .interactiveDismissDisabled(model?.completion == nil && (model?.hasNonemptyDraft == true || model?.isBusy == true))
            .task {
                guard model == nil, let userID = account.userID else { return }
                let draftID = "rating-draft-\(request.experience.id.uuidString.lowercased())-\(request.mode.rawValue)-photos"
                let photos = PhotoDraftModel(ownerID: userID, draftID: draftID,
                                             existingMedia: [.rerank, .editVisit].contains(request.mode) ? request.existingVisit?.media ?? [] : [],
                                             storage: services.storage, media: services.media, currentAccount: { account.userID })
                let flow = RatingFlowModel(request: request, accountID: userID, ranking: services.ranking,
                                           storage: services.storage, currentAccount: { account.userID }, photos: photos)
                if request.mode == .editVisit, let original = request.existingVisit {
                    flow.saveEdit = { [services] visit in
                        let date = VisitDate(date: visit.date, timeZoneIdentifier: visit.timeZoneIdentifier)
                        _ = try await services.memories.updateVisit(visitID: original.id, note: visit.publicNote, date: date,
                                                                    mediaIDs: visit.mediaIDs, operationID: UUID())
                        if let audience = visit.audience, audience != original.audience {
                            try await services.plans.setVisitAudience(visitID: original.id, audience: audience)
                        }
                        if visit.tripID != original.tripID {
                            try await services.plans.setVisitTrip(visitID: original.id, tripID: visit.tripID)
                        }
                    }
                }
                model = flow
            }
        }
        .roamSheetStyle()
        .screenIdentifier("rating-flow")
    }

    private func savingFromComparison(_ model: RatingFlowModel) -> Bool {
        fromComparison && (model.step == .saving || model.step == .result)
    }

    /// Closes first, then tidies up: clearing the photos before closing showed the form changing for a moment.
    private func close(_ model: RatingFlowModel) {
        model.discardDraft()
        let photos = model.photos
        dismiss()
        Task { await photos?.discard() }
    }

    /// A town or city logged as somewhere you've been, rather than a place within one.
    private var isCity: Bool {
        let place = request.experience
        return place.category == .dayTrips || request.suggestedCategory == .dayTrips
            || GeographyKey.normalize(place.name) == GeographyKey.normalize(place.locality ?? "")
    }

    private var title: String {
        switch request.mode {
        case .firstLog: return "Log a place"
        case .rerank: return "Rank again"
        case .addVisit: return "Add a visit"
        case .editVisit: return "Edit visit"
        }
    }

    private func content(_ model: RatingFlowModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                // The name, with where it is right under it as one block: a city's country, or a place's city and country.
                // Not while comparing: the place is one of the two cards then.
                if model.step != .comparison && !savingFromComparison(model) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(request.experience.name).font(.roamTitle()).accessibilityIdentifier("rating-place")
                        Text(isCity ? (request.experience.countryName ?? "") : request.experience.areaLine)
                            .font(.subheadline).foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityElement(children: .combine)
                }
                if let error = model.persistenceError ?? model.message {
                    Text(error).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-message")
                }
                switch model.step {
                case .sentiment: sentiment(model)
                case .details: details(model)
                case .loading:
                    ProgressView("Loading your category ranking…").accessibilityIdentifier("rating-loading")
                case .comparison: comparison(model)
                // Saving and saved keep the form where it is (Save shows it's working); the log then just closes. After
                // a comparison, nothing shows while it does, rather than the form coming back for a moment.
                case .saving, .result:
                    if !fromComparison { details(model) }
                case .retry:
                    Button("Retry save") { Task { await model.retrySave() } }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rating-retry")
                }
            }
            .padding(Theme.Spacing.l)
        }
        .accessibilityIdentifier("rating-scroll")
        // Save sits where the other bottom buttons do: the tab bar's width and height, the same low gap from the bottom of
        // the screen, with room left above it for the content.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if [.details, .saving, .result].contains(model.step) && !savingFromComparison(model) { Color.clear.frame(height: RoamTabBar.reservedHeight) }
        }
        .overlay {
            if [.details, .saving, .result].contains(model.step) && !savingFromComparison(model) {
                let working = model.step != .details
                let canSave = !working && model.photos?.canCommit != false && model.category != nil
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button { Task { await model.okay() } } label: {
                        Group { if working { ProgressView() } else { Text("Save") } }
                            .font(.headline)
                            .foregroundStyle(Roam.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: RoamTabBar.height)
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // See-through Liquid Glass, like the tab bar.
                    .floatingBubble(Capsule())
                    .opacity(canSave || working ? 1 : 0.35)
                    .disabled(!canSave)
                    .padding(.horizontal, RoamTabBar.sideMargin)
                    .padding(.bottom, RoamTabBar.margin + 6)
                    .accessibilityIdentifier("rating-okay")
                }
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .onChange(of: model.step) { _, step in
            if step == .comparison { fromComparison = true } else if step == .details || step == .sentiment { fromComparison = false }
        }
        .roamHaptic(.selection, trigger: model.comparison?.id)
        .roamHaptic(.success, trigger: model.step == .result)
        // Saved: it just closes, no result screen to tap Done on.
        .onChange(of: model.completion) { _, completion in
            guard let completion else { return }
            onSaved(completion)
            dismiss()
        }
        .onChange(of: model.authError) { _, error in if let error { _ = account.handle(error) } }
        .onChange(of: model.photos?.assets) { _, _ in
            // Only a fully ready selection is mirrored into the draft; in-progress uploads are not errors.
            guard model.canEdit, let photos = model.photos, photos.canCommit, let ids = try? photos.attachmentIDs() else { return }
            _ = model.updateDetails(note: model.visit.publicNote, date: model.visit.date, mediaIDs: ids)
        }
    }

    /// One bubble's contents: an icon, its value, and optionally a hint it opens something. The same height and text as
    /// the feeling picker above (44 points, footnote semibold).
    private func bubbleLabel(symbol: String, text: String, trailing: String? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Roam.ink).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let trailing {
                Image(systemName: trailing).font(.caption2.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .contentShape(Rectangle())
    }

    /// The date, filled in (today for a new log), with a small × at the right to clear it; tapping anywhere else opens
    /// a calendar right there.
    private func dateBubble(_ model: RatingFlowModel) -> some View {
        let zone = model.timeZone
        return HStack(spacing: 5) {
            Image(systemName: "calendar").font(.footnote).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            Text(model.visit.date?.displayString ?? "Date").font(.footnote.weight(.semibold))
                .foregroundStyle(model.visit.date == nil ? Roam.inkMuted : Roam.ink).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if model.visit.date != nil {
                Button { model.updateDetails(note: model.visit.publicNote, date: nil) } label: {
                    Image(systemName: "xmark.circle.fill").font(.subheadline).foregroundStyle(Roam.inkMuted)
                        .frame(width: 32, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove date")
                .accessibilityIdentifier("rating-clear-date")
            }
        }
        .padding(.leading, Theme.Spacing.m)
        .padding(.trailing, model.visit.date == nil ? Theme.Spacing.m : Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 44)
        .contentShape(Rectangle())
        .onTapGesture { showsDate = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("rating-edit-date")
        .roamCard(padding: 0)
        .popover(isPresented: $showsDate) {
            DatePicker("Visit date", selection: Binding(
                get: { (model.visit.date ?? model.today).date(in: zone) },
                set: { picked in
                    model.updateDetails(note: model.visit.publicNote, date: LocalDate(date: picked, timeZone: zone))
                    showsDate = false
                }), in: ...model.today.date(in: zone), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .environment(\.timeZone, zone)
                .padding(Theme.Spacing.m)
                .frame(width: 320)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func pickerRow<Control: View>(_ title: String, symbol: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
            Text(title)
            Spacer(minLength: Theme.Spacing.m)
            control().fixedSize()
        }
        .frame(minHeight: Theme.minimumHitTarget)
    }

    private func sentiment(_ model: RatingFlowModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if !model.categoryLocked {
                pickerRow("Category", symbol: model.category?.symbolName ?? "square.grid.2x2") {
                    Picker("Category", selection: Binding(get: { model.category }, set: { if let category = $0 { model.selectCategory(category) } })) {
                        Text("Choose").tag(ExperienceCategory?.none)
                        ForEach(ExperienceCategory.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("rating-category-picker")
                }
                .roamCard(padding: Theme.Spacing.m)
            }
            Text("How was it?").font(.title2.weight(.semibold))
            // A three-stop slider. Roam works out the score itself from how this place compares with your others, so
            // all it needs here is which way you lean.
            FeelingSlider(selection: $feeling, enabled: model.category != nil) { picked in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    model.selectSentiment(picked)
                }
            }
            if request.mode == .firstLog {
                Button("Skip ranking") { model.logWithoutRanking() }
                    .buttonStyle(QuietButtonStyle())
                    .disabled(model.category == nil)
                    .accessibilityIdentifier("rating-skip-ranking")
            }
        }
    }

    private func details(_ model: RatingFlowModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            // How it was, always first. Picking a feeling ranks the place when you save; leaving it logs it unranked.
            if request.mode != .addVisit && request.mode != .editVisit {
                FeelingSlider(selection: Binding(get: { model.sentiment }, set: { _ in }), enabled: model.category != nil) { picked in
                    model.setFeeling(picked)
                }
            }
            // The category, when it isn't known yet, as its own bubble.
            if !model.categoryLocked {
                pickerRow("Category", symbol: model.category?.symbolName ?? "square.grid.2x2") {
                    Picker("Category", selection: Binding(get: { model.category }, set: { if let category = $0 { model.selectCategory(category) } })) {
                        Text("Choose").tag(ExperienceCategory?.none)
                        ForEach(ExperienceCategory.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("rating-details-category")
                }
                .roamCard(padding: Theme.Spacing.m)
            }
            // Three rows: the date beside which trip it was part of, then photos across the width, then the note.
            HStack(spacing: Theme.Spacing.m) {
                dateBubble(model)
                if request.mode != .rerank {
                    Menu {
                        // Icons say which is which: a house for home, a plane for each trip.
                        Picker("Part of", selection: Binding(get: { model.visit.tripID }, set: { model.setTrip($0) })) {
                            if let home { Label(home.name, systemImage: "house").tag(UUID?.none) }
                            else { Text("No trip").tag(UUID?.none) }
                            ForEach(trips) { Label($0.name, systemImage: "airplane").tag(Optional($0.id)) }
                        }
                    } label: {
                        bubbleLabel(symbol: home != nil && model.visit.tripID == nil ? "house" : "airplane",
                                    text: trips.first { $0.id == model.visit.tripID }?.name ?? home?.name ?? "No trip",
                                    trailing: "chevron.up.chevron.down")
                    }
                    .roamCard(padding: 0)
                    .accessibilityIdentifier("rating-part-of")
                    .task(id: request.experience.id) { await loadPlacement(model) }
                }
            }
            // Photos: the system picker straight away; once there are some, they show one at a time, swiping for more.
            if let photos = model.photos {
                Group {
                    if photos.assets.isEmpty {
                        PhotosPicker(selection: $pickedPhotos, selectionBehavior: .ordered, matching: .images) {
                            bubbleLabel(symbol: "photo.on.rectangle", text: "Add photos", trailing: "plus")
                        }
                        .buttonStyle(.plain)
                        .roamCard(padding: 0)
                    } else {
                        // Adding more is a glass bubble on the photos themselves.
                        PhotoCarousel(model: photos) {
                            PhotosPicker(selection: $pickedPhotos, selectionBehavior: .ordered, matching: .images) {
                                Label("Add more", systemImage: "plus")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .frame(height: 36)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .floatingBubble(Capsule())
                            .environment(\.colorScheme, .dark)
                        }
                    }
                }
                .accessibilityIdentifier("rating-edit-photos")
                .onChange(of: pickedPhotos) { _, items in
                    guard !items.isEmpty else { return }
                    Task {
                        await PhotoImport.add(items, to: photos)
                        pickedPhotos = []
                    }
                }
            }
            // The note, typed right here in a roomy box of its own.
            NoteBox(text: Binding(get: { model.visit.publicNote },
                                  set: { _ = model.updateDetails(note: $0, date: model.visit.date) }))
                .accessibilityIdentifier("rating-note")
            if request.mode == .rerank { Text("This updates your ranking and existing visit without adding another one.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if request.mode != .rerank {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Who can see this").font(.footnote.weight(.semibold))
                    // Only me, Friends, Public; a new log is public unless you choose otherwise.
                    Picker("Who can see this", selection: Binding(get: { model.visit.audience ?? .public }, set: { model.setAudience($0) })) {
                        ForEach(Audience.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("rating-audience")
                    Text("This covers the whole entry, including its note and photos.")
                        .font(.footnote).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-publication-disclosure")
                }
            }
        }
        .screenIdentifier("rating-details")
    }

    /// Near one of your home cities, a visit goes with that home. Otherwise it joins a trip covering this city
    /// right now, if there is one; you can always pick another trip.
    private func loadPlacement(_ model: RatingFlowModel) async {
        let homes = HomeCities.distinct((try? await services.plans.homeCities()) ?? [])
        let all = (try? await services.plans.myTrips()) ?? []
        let today = MyTimeline.today()
        trips = all.sorted { ($0.phase(today: today) == .past ? 1 : 0, $0.name) < ($1.phase(today: today) == .past ? 1 : 0, $1.name) }
        home = CityMatch.home(for: request.experience, homes: homes)
        // A visit being edited keeps what it was part of; only a new one gets a guess.
        guard model.visit.tripID == nil, request.mode != .editVisit else { return }
        // A trip happening now that covers this place comes first: it's in one of the trip's cities or within 100 km of
        // one (a day out from it), or in a country the trip is to. Otherwise, near a home, it goes with that home.
        let place = request.experience
        let spot = CLLocation(latitude: place.latitude, longitude: place.longitude)
        if let match = all.first(where: { trip in
            guard trip.isOwn, trip.phase(today: today) == .now else { return false }
            let nearCity = trip.cities.contains { city in
                CityMatch.same(place, city) || (!(city.latitude == 0 && city.longitude == 0)
                    && CLLocation(latitude: city.latitude, longitude: city.longitude).distance(from: spot) <= CityMatch.homeRadius)
            }
            return nearCity || place.countryCode.map { trip.covers(country: $0) } == true
        }) {
            model.setTrip(match.id)
        }
    }

    /// Just the question, the two places to tap, and small ways out underneath.
    private func comparison(_ model: RatingFlowModel) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Which did you like more?")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.bottom, Theme.Spacing.s)
            if let existing = model.comparison {
                comparisonCard(name: request.experience.name, city: request.experience.locality, identifier: "rating-prefer-new") {
                    Task { await model.choose(.preferNew) }
                }
                Text("or").font(.subheadline).foregroundStyle(Theme.secondaryText)
                comparisonCard(name: existing.name, city: existing.locality, identifier: "rating-prefer-existing") {
                    Task { await model.choose(.preferExisting) }
                }
            }
            HStack(spacing: Theme.Spacing.l) {
                if model.canUndo {
                    Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .accessibilityIdentifier("rating-undo")
                }
                Button("Too tough") { Task { await model.choose(.tooTough) } }
                    .accessibilityIdentifier("rating-too-tough")
                Button("Skip") { Task { await model.choose(.skip) } }
                    .accessibilityIdentifier("rating-skip")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.secondaryText)
            .buttonStyle(.plain)
            .frame(minHeight: Theme.minimumHitTarget)
            .padding(.top, Theme.Spacing.s)
        }
        .screenIdentifier("rating-comparison")
    }

    private func comparisonCard(name: String, city: String?, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(name).font(.headline).foregroundStyle(Roam.ink).multilineTextAlignment(.center).lineLimit(2)
                if let city, !city.isEmpty { Text(city).font(.subheadline).foregroundStyle(Theme.secondaryText).lineLimit(1) }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: 96)
            .roamCard(padding: 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

}

/// Didn't like · Neutral · Liked it, as a track with a knob that slides to the stop you tap or drag to.
/// Didn't like / Neutral / Liked it, with a glass bubble over the one picked. Logging a place, and a city.
struct FeelingSlider: View {
    @Binding var selection: Sentiment?
    var enabled: Bool
    var onPick: (Sentiment) -> Void

    private let stops: [Sentiment] = [.disliked, .fine, .liked]

    /// The picked pill: Didn't like red, Neutral white, Liked it green.
    private func fill(_ feeling: Sentiment) -> Color {
        switch feeling {
        case .disliked: return .red
        case .fine: return Roam.paperRaised
        case .liked: return PlaceState.visited.markerColor
        }
    }


    private func label(_ feeling: Sentiment) -> String {
        switch feeling {
        case .disliked: return "Didn't like"
        case .fine: return "Neutral"
        case .liked: return "Liked it"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let segment = width / CGFloat(stops.count)
            ZStack(alignment: .leading) {
                // Like My Places' Saved / Been selector: a grey track with the one picked as a raised pill sitting in it.
                Capsule().fill(Color.gray.opacity(0.18))
                if let selection, let index = stops.firstIndex(of: selection) {
                    Capsule().fill(fill(selection))
                        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                        .padding(3)
                        .frame(width: segment)
                        .offset(x: segment * CGFloat(index))
                        .animation(.snappy(duration: 0.25), value: selection)
                        .allowsHitTesting(false)
                }
                HStack(spacing: 0) {
                    ForEach(stops, id: \.self) { feeling in
                        HStack(spacing: 5) {
                            Image(systemName: feeling.symbolName).font(.footnote)
                            Text(label(feeling)).font(.footnote.weight(.semibold))
                        }
                        // The one picked reads on its pill (white on red or green, ink on white); the others muted.
                        .foregroundStyle(selection == feeling ? (feeling == .fine ? Roam.ink : .white) : Roam.inkMuted)
                        .frame(width: segment)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selection == feeling ? .isSelected : [])
                        .accessibilityAction { pick(feeling) }
                    }
                }
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let index = min(max(Int(value.location.x / segment), 0), stops.count - 1)
                        if selection != stops[index] { selection = stops[index] }
                    }
                    .onEnded { value in
                        let index = min(max(Int(value.location.x / segment), 0), stops.count - 1)
                        pick(stops[index])
                    }
            )
            .opacity(enabled ? 1 : 0.4)
            .allowsHitTesting(enabled)
        }
        .frame(height: 44)
        .accessibilityIdentifier("rating-feeling-slider")
    }

    private func pick(_ feeling: Sentiment) {
        selection = feeling
        onPick(feeling)
    }
}
