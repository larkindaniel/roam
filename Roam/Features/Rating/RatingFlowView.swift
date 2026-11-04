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
    @State private var showsNote = false
    @State private var showsDate = false
    @State private var showsPhotos = false
    @State private var trips: [TripSummary] = []
    @State private var home: Destination?

    var body: some View {
        NavigationStack {
            Group {
                if let model { content(model) }
                else { ProgressView("Preparing your draft…") }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let model else { dismiss(); return }
                        if model.completion != nil { dismiss() }
                        else if model.hasNonemptyDraft { showsCancel = true }
                        else {
                            Task { await model.photos?.discard(); model.discardDraft(); dismiss() }
                        }
                    }
                    label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Close")
                    .disabled(model?.isBusy == true)
                    .accessibilityIdentifier("rating-close")
                }
            }
            .confirmationDialog("Keep your draft?", isPresented: $showsCancel, titleVisibility: .visible) {
                Button("Keep draft") { model?.keepDraft(); dismiss() }
                if model?.hasPendingSave != true {
                    Button("Discard draft", role: .destructive) {
                        Task {
                            await model?.photos?.discard()
                            model?.discardDraft()
                            dismiss()
                        }
                    }
                }
                Button("Continue editing", role: .cancel) {}
            } message: {
                Text(model?.hasPendingSave == true
                     ? "Saving wasn't confirmed. Keep this draft so the original save can be checked safely."
                     : "Your draft is kept on this device. Nothing is published before saving finishes.")
            }
            .interactiveDismissDisabled(model?.completion == nil && (model?.hasNonemptyDraft == true || model?.isBusy == true))
            .task {
                guard model == nil, let userID = account.userID else { return }
                let draftID = "rating-draft-\(request.experience.id.uuidString.lowercased())-\(request.mode.rawValue)-photos"
                let photos = PhotoDraftModel(ownerID: userID, draftID: draftID,
                                             existingMedia: request.mode == .rerank ? request.existingVisit?.media ?? [] : [],
                                             storage: services.storage, media: services.media, currentAccount: { account.userID })
                model = RatingFlowModel(request: request, accountID: userID, ranking: services.ranking,
                                        storage: services.storage, currentAccount: { account.userID }, photos: photos)
            }
        }
        .roamSheetStyle()
        .screenIdentifier("rating-flow")
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
        }
    }

    private func content(_ model: RatingFlowModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                // The name, with where it is right under it as one block: a city's country, or a place's city and country.
                VStack(alignment: .leading, spacing: 0) {
                    Text(request.experience.name).font(.roamTitle()).accessibilityIdentifier("rating-place")
                    Text(isCity ? (request.experience.countryName ?? "") : request.experience.areaLine)
                        .font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if let error = model.persistenceError ?? model.message {
                    Text(error).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-message")
                }
                switch model.step {
                case .sentiment: sentiment(model)
                case .details: details(model)
                case .loading:
                    ProgressView("Loading your category ranking…").accessibilityIdentifier("rating-loading")
                case .comparison: comparison(model)
                case .saving:
                    ProgressView("Saving…").accessibilityIdentifier("rating-saving")
                    Text("Your result appears after saving is confirmed.").foregroundStyle(Theme.secondaryText)
                case .retry:
                    Button("Retry save") { Task { await model.retrySave() } }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rating-retry")
                case .result: result(model)
                }
            }
            .padding(Theme.Spacing.l)
        }
        .accessibilityIdentifier("rating-scroll")
        // Save sits at the bottom of the screen while you fill things in.
        .safeAreaInset(edge: .bottom) {
            if model.step == .details {
                Button("Save") { Task { await model.okay() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.photos?.canCommit == false || model.category == nil)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.vertical, Theme.Spacing.s)
                    .background(Roam.paper.opacity(0.95))
                    .accessibilityIdentifier("rating-okay")
            }
        }
        .roamHaptic(.selection, trigger: model.comparison?.id)
        .roamHaptic(.success, trigger: model.step == .result)
        .onChange(of: model.completion) { _, completion in if let completion { onSaved(completion) } }
        .onChange(of: model.authError) { _, error in if let error { _ = account.handle(error) } }
        .onChange(of: model.photos?.assets) { _, _ in
            // Only a fully ready selection is mirrored into the draft; in-progress uploads are not errors.
            guard model.canEdit, let photos = model.photos, photos.canCommit, let ids = try? photos.attachmentIDs() else { return }
            _ = model.updateDetails(note: model.visit.publicNote, date: model.visit.date, mediaIDs: ids)
        }
        .sheet(isPresented: $showsPhotos) {
            if let photos = model.photos {
                PhotoDraftEditor(model: photos, failureMessage: { model.persistenceError ?? model.message }) {
                    do {
                        return model.updateDetails(note: model.visit.publicNote, date: model.visit.date, mediaIDs: try photos.attachmentIDs())
                    } catch { return false }
                }
            }
        }
        .sheet(isPresented: $showsNote) {
            RatingNoteEditor(note: model.visit.publicNote, failureMessage: { model.persistenceError ?? model.message }) { note in
                model.updateDetails(note: note, date: model.visit.date)
            }
        }
        .sheet(isPresented: $showsDate) {
            RatingDateEditor(date: model.visit.date, zone: model.timeZone, today: model.today, failureMessage: { model.persistenceError ?? model.message }) { date in
                model.updateDetails(note: model.visit.publicNote, date: date)
            }
        }
    }

    private func detailRow(_ title: String, symbol: String, value: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: symbol).frame(width: 24).accessibilityHidden(true)
                Text(title)
                Spacer(minLength: Theme.Spacing.m)
                Text(value).foregroundStyle(Roam.inkMuted).lineLimit(1)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .foregroundStyle(Roam.ink)
            .frame(minHeight: Theme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
            if request.mode != .addVisit {
                FeelingSlider(selection: Binding(get: { model.sentiment }, set: { _ in }), enabled: model.category != nil) { picked in
                    model.setFeeling(picked)
                }
            }
            VStack(spacing: 0) {
                if !model.categoryLocked {
                    pickerRow("Category", symbol: model.category?.symbolName ?? "square.grid.2x2") {
                        Picker("Category", selection: Binding(get: { model.category }, set: { if let category = $0 { model.selectCategory(category) } })) {
                            Text("Choose").tag(ExperienceCategory?.none)
                            ForEach(ExperienceCategory.allCases) { Text($0.title).tag(Optional($0)) }
                        }
                        .labelsHidden()
                        .accessibilityIdentifier("rating-details-category")
                    }
                    Divider()
                }
                detailRow("Note", symbol: "text.alignleft", value: model.visit.publicNote.isEmpty ? "Optional" : model.visit.publicNote, identifier: "rating-edit-note") { showsNote = true }
                Divider()
                detailRow("Date", symbol: "calendar", value: model.visit.date?.displayString ?? "Unknown", identifier: "rating-edit-date") { showsDate = true }
                if let photos = model.photos {
                    Divider()
                    detailRow("Photos", symbol: "photo.on.rectangle", value: photos.assets.isEmpty ? "Optional" : "\(photos.assets.count)", identifier: "rating-edit-photos") { showsPhotos = true }
                }
            }
            .roamCard(padding: Theme.Spacing.m)
            if let photos = model.photos, !photos.canCommit {
                Text("Retry or remove unfinished photos before continuing.").foregroundStyle(Theme.disliked)
            }
            if request.mode != .rerank {
                pickerRow("Part of", symbol: home != nil && model.visit.tripID == nil ? "house" : "airplane") {
                    Picker("Part of", selection: Binding(get: { model.visit.tripID }, set: { model.setTrip($0) })) {
                        Text(home.map { "Home · \($0.name)" } ?? "No trip").tag(UUID?.none)
                        ForEach(trips) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("rating-part-of")
                }
                .roamCard(padding: Theme.Spacing.m)
                .task(id: request.experience.id) { await loadPlacement(model) }
            }
            if request.mode == .rerank { Text("This updates your ranking and existing visit without adding another one.").font(.footnote).foregroundStyle(Theme.secondaryText) }
            if request.mode != .rerank {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Who can see this").font(.footnote.weight(.semibold))
                    Picker("Who can see this", selection: Binding(get: { model.visit.audience ?? .friends }, set: { model.setAudience($0) })) {
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
        guard home == nil, model.visit.tripID == nil else { return }
        let place = request.experience
        if let match = all.first(where: { trip in
            trip.phase(today: today) == .now && trip.cities.contains { city in CityMatch.same(place, city) || place.countryCode?.uppercased() == city.countryCode?.uppercased() }
        }) {
            model.setTrip(match.id)
        }
    }

    private func comparison(_ model: RatingFlowModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Which did you prefer?").font(.title2.weight(.semibold))
            if let existing = model.comparison {
                comparisonCard(name: request.experience.name, city: request.experience.areaLine, identifier: "rating-prefer-new") {
                    Task { await model.choose(.preferNew) }
                }
                comparisonCard(name: existing.name, city: existing.locality ?? "Location unavailable", identifier: "rating-prefer-existing") {
                    Task { await model.choose(.preferExisting) }
                }
            }
            Text("Only your \(model.category?.title ?? "category") places marked \(model.sentiment?.title.lowercased() ?? "the same way") are compared.")
                .font(.footnote).foregroundStyle(Theme.secondaryText)
            Button("Too tough") { Task { await model.choose(.tooTough) } }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("rating-too-tough")
            Button("Skip") { Task { await model.choose(.skip) } }
                .frame(minHeight: Theme.minimumHitTarget).accessibilityIdentifier("rating-skip")
            Text("Skip places this approximately; you can rank again.")
                .font(.footnote).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-skip-explanation")
            Button("Undo") { model.undo() }.disabled(!model.canUndo)
                .frame(minHeight: Theme.minimumHitTarget).accessibilityIdentifier("rating-undo")
        }
        .screenIdentifier("rating-comparison")
    }

    private func comparisonCard(name: String, city: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text(name).font(.headline)
                Text(city).font(.subheadline).foregroundStyle(Theme.secondaryText)
            }.frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
                .roamCard()
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func result(_ model: RatingFlowModel) -> some View {
        if let completion = model.completion {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                switch completion {
                case .rating(let result):
                    Text("Saved").font(.title2.weight(.semibold))
                    if Score.isShown {
                    Text(result.score.formatted).font(.system(.largeTitle, design: .rounded).bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Your score \(result.score.formatted)").accessibilityIdentifier("rating-result-score")
                    Text("Position \(result.rank) of \(result.categoryCount) in \(result.category.title)")
                        .accessibilityIdentifier("rating-result-position")
                    if result.groupSize > 1 { Text("Tied with \(result.groupSize - 1) other \(result.groupSize == 2 ? "place" : "places").") }
                    Text("Your score can change as your category list grows.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                case .visit:
                    Text("Visit saved").font(.title2.weight(.semibold)).accessibilityIdentifier("rating-visit-saved")
                    Text(request.mode == .addVisit ? "Your existing ranking stays the same." : "You can rank this place whenever you like.").foregroundStyle(Theme.secondaryText)
                }
                Text("People you chose can see this entry on your profile and in their Friends tab.").font(.footnote)
                Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rating-done")
            }.screenIdentifier("rating-result")
        }
    }
}

private struct RatingNoteEditor: View {
    @State var note: String
    @State private var error: String?
    let failureMessage: () -> String?
    let onDone: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form { Group {
                TextEditor(text: $note).textInputAutocapitalization(.never).frame(minHeight: 200).accessibilityIdentifier("rating-note-text")
                Text("\(Validation.characterCount(note)) / 5,000 characters").foregroundStyle(Validation.characterCount(note) > 5_000 ? Color.red : Color.gray)
                if let error { Text(error).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-editor-error") }
            }
            .listRowBackground(Roam.paperRaised)
            }.navigationTitle("Note").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("rating-editor-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if onDone(note) { dismiss() } else { error = failureMessage() ?? "Your changes couldn't be kept. Try again." }
                    }.disabled(Validation.characterCount(note) > 5_000).accessibilityIdentifier("rating-editor-done")
                }
            }
        }
        .roamSheetStyle()
    }
}

private struct RatingDateEditor: View {
    @State private var date: Date
    @State private var unknown: Bool
    @State private var error: String?
    let zone: TimeZone
    let today: LocalDate
    let failureMessage: () -> String?
    let onDone: (LocalDate?) -> Bool
    @Environment(\.dismiss) private var dismiss
    init(date: LocalDate?, zone: TimeZone, today: LocalDate, failureMessage: @escaping () -> String?, onDone: @escaping (LocalDate?) -> Bool) {
        self.zone = zone; self.today = today; self.failureMessage = failureMessage; self.onDone = onDone
        _date = State(initialValue: (date ?? today).date(in: zone))
        _unknown = State(initialValue: date == nil)
    }
    var body: some View {
        NavigationStack {
            Form { Group {
                Toggle("Date unknown", isOn: $unknown).accessibilityIdentifier("rating-date-unknown")
                if !unknown { DatePicker("Visit date", selection: $date, in: ...today.date(in: zone), displayedComponents: .date).environment(\.timeZone, zone) }
                if let error { Text(error).foregroundStyle(Theme.secondaryText).accessibilityIdentifier("rating-editor-error") }
            }
            .listRowBackground(Roam.paperRaised)
            }.navigationTitle("Visit date").toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("rating-editor-cancel") }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if onDone(unknown ? nil : LocalDate(date: date, timeZone: zone)) { dismiss() }
                        else { error = failureMessage() ?? "Your changes couldn't be kept. Try again." }
                    }.accessibilityIdentifier("rating-editor-done")
                }
            }
        }
        .roamSheetStyle()
    }
}

/// Didn't like · Neutral · Liked it, as a track with a knob that slides to the stop you tap or drag to.
private struct FeelingSlider: View {
    @Binding var selection: Sentiment?
    var enabled: Bool
    var onPick: (Sentiment) -> Void

    private let stops: [Sentiment] = [.disliked, .fine, .liked]

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
                Capsule().fill(Roam.ink.opacity(0.06))
                if let selection, let index = stops.firstIndex(of: selection) {
                    Capsule().fill(Theme.fill(for: selection))
                        .overlay(Capsule().stroke(Theme.color(for: selection).opacity(0.5), lineWidth: 1.5))
                        .frame(width: segment - 8)
                        .offset(x: segment * CGFloat(index) + 4)
                        .animation(.snappy(duration: 0.25), value: selection)
                }
                HStack(spacing: 0) {
                    ForEach(stops, id: \.self) { feeling in
                        HStack(spacing: 5) {
                            Image(systemName: feeling.symbolName).font(.footnote)
                            Text(label(feeling)).font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(selection == feeling ? Theme.color(for: feeling) : Roam.inkMuted)
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
