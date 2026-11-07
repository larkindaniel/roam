import CoreLocation
import SwiftUI

/// Onboarding, "Where have you been?": places around home to tap (friends' first), or search for any place.
struct OnboardingBeenStep: View {
    @Bindable var model: OnboardingTasteModel
    let home: Destination?
    let onContinue: () -> Void

    @State private var query = ""
    private var hasQuery: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Where have you been?").font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                Text(home.map { "Tap places you know around \($0.name). Roam learns what you like from them." }
                     ?? "Search for places you've been. Roam learns what you like from them.")
                    .font(.body).foregroundStyle(Theme.secondaryText)
            }
            searchField
            if hasQuery {
                if !model.searchResults.isEmpty { searchRows }
            } else {
                candidateRows
            }
            Button(model.selected.isEmpty ? "Skip for now" : "Continue") { onContinue() }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("onboarding-been-continue")
        }
        .task { if case .idle = model.candidates { await model.loadCandidates(home: home) } }
        .task(id: query) {
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            await model.search(query, near: home)
        }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            TextField("Search places", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("onboarding-search")
            if hasQuery {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Roam.inkMuted) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .frame(height: 44)
        .background(Capsule().fill(Roam.fill))
    }

    @ViewBuilder private var candidateRows: some View {
        switch model.candidates {
        case .idle, .loading:
            SkeletonList(rows: 4)
        case .failed(let message):
            InlineRetryView(message: message) { Task { await model.loadCandidates(home: home) } }
        case .loaded(let places):
            // Places picked from search stay listed with the suggestions, so they can be unpicked.
            let extra = model.selected.filter { picked in !places.contains { $0.id == picked.id } }
            let rows = places + extra
            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, place in
                        if index > 0 { RowSeparator() }
                        row(name: place.name, subtitle: place.areaLine, url: place.photoURL, coordinate: place.coordinate,
                            symbol: place.iconName, picked: model.isSelected(place)) { model.toggle(place) }
                    }
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
    }

    private var searchRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.searchResults.enumerated()), id: \.element.id) { index, hit in
                if index > 0 { RowSeparator() }
                let picked = hit.experience.map(model.isSelected) ?? model.selected.contains { $0.name == hit.candidate.name }
                row(name: hit.candidate.name, subtitle: [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.joined(separator: ", "),
                    url: hit.experience?.photoURL, coordinate: CLLocationCoordinate2D(latitude: hit.candidate.latitude, longitude: hit.candidate.longitude),
                    symbol: hit.experience?.iconName ?? "mappin", picked: picked) {
                    if let place = hit.experience, picked { model.toggle(place) } else if !picked { Task { await model.add(hit) } }
                }
            }
        }
        .roamCard(padding: Theme.Spacing.m)
    }

    /// The standard row: a photo with a green Been mark once picked, the name and where it is, and a tick on the right.
    private func row(name: String, subtitle: String, url: URL?, coordinate: CLLocationCoordinate2D, symbol: String, picked: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack(alignment: .bottomTrailing) {
                    PlaceThumbnail(id: "onboarding-\(name)", url: url, coordinate: coordinate, symbol: symbol, size: 48)
                    if picked { StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6) }
                }
                VStack(alignment: .leading, spacing: -2) {
                    Text(name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1).truncationMode(.tail)
                    if !subtitle.isEmpty { Text(subtitle).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1) }
                }
                Spacer(minLength: Theme.Spacing.s)
                Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(picked ? PlaceState.visited.markerColor : Roam.inkFaint)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(picked ? .isSelected : [])
        .accessibilityLabel(name)
        .accessibilityIdentifier("onboarding-place-\(name)")
    }
}

/// Onboarding, one place at a time: how was it, then which did you like more, like the log screen.
struct OnboardingRankStep: View {
    @Bindable var model: OnboardingTasteModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if let place = model.current {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let progress = model.progressLabel {
                        Text(progress).font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                            .accessibilityIdentifier("onboarding-progress")
                    }
                    Text(place.name).font(.roamDisplay(.title)).accessibilityAddTraits(.isHeader)
                    if !place.areaLine.isEmpty { Text(place.areaLine).font(.body).foregroundStyle(Theme.secondaryText) }
                }
                switch model.stage {
                case .feeling:
                    Text("How was it?").font(.title3.weight(.semibold))
                    FeelingSlider(selection: $model.feeling, enabled: true) { picked in Task { await model.pick(picked) } }
                case .comparing, .saving:
                    comparison(place)
                case .picking, .done:
                    EmptyView()
                }
                if let error = model.error {
                    ErrorText(error)
                    if case .comparing = model.stage, model.session?.isComplete == true {
                        Button("Try again") { Task { await model.retry() } }.buttonStyle(SecondaryButtonStyle())
                    }
                }
                Button("Skip the rest") { model.skipRest() }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("onboarding-skip-rest")
            }
        }
        .roamHaptic(.selection, trigger: model.comparison?.id)
    }

    private func comparison(_ place: ExperienceSummary) -> some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Which did you like more?")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
            if let existing = model.comparison {
                card(name: place.name, city: place.locality, identifier: "onboarding-prefer-new") { Task { await model.choose(.preferNew) } }
                Text("or").font(.subheadline).foregroundStyle(Theme.secondaryText)
                card(name: existing.name, city: existing.locality, identifier: "onboarding-prefer-existing") { Task { await model.choose(.preferExisting) } }
                HStack(spacing: Theme.Spacing.l) {
                    if model.canUndo {
                        Button { model.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                            .accessibilityIdentifier("onboarding-undo")
                    }
                    Button("Too tough") { Task { await model.choose(.tooTough) } }
                        .accessibilityIdentifier("onboarding-too-tough")
                    Button("Skip") { Task { await model.choose(.skip) } }
                        .accessibilityIdentifier("onboarding-skip-comparison")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.secondaryText)
                .buttonStyle(.plain)
                .frame(minHeight: Theme.minimumHitTarget)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 96)
            }
        }
    }

    private func card(name: String, city: String?, identifier: String, action: @escaping () -> Void) -> some View {
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
        .disabled(model.stage != .comparing(model.currentIndex ?? -1))
        .accessibilityIdentifier(identifier)
    }
}
