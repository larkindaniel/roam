import SwiftUI

/// + Log a place: find the place, then fill in the visit, all in one sheet.
struct LogPlaceSheet: View {
    var onSaved: (LogRequest, RatingFlowCompletion) -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExperienceSearchModel?
    @State private var query = ""
    @State private var request: LogRequest?
    @State private var opening: String?
    @State private var error: String?

    var body: some View {
        Group {
            if let request {
                RatingFlowView(request: request) { onSaved(request, $0) }
            } else {
                NavigationStack {
                    searchList
                        .scrollContentBackground(.hidden)
                        .background(Roam.paper)
                        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Where did you go?")
                        .navigationTitle("Log a place")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { dismiss() }.accessibilityIdentifier("log-place-close")
                            }
                        }
                }
            }
        }
        .task { if model == nil { model = ExperienceSearchModel(services: services) } }
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { model?.query = ""; return }
            try? await Task.sleep(for: Limits.searchDebounce)
            guard !Task.isCancelled else { return }
            await model?.search(query, near: nil)
        }
        .screenIdentifier("log-place-sheet")
    }

    private var searchList: some View {
        List {
            if let error { Text(error).foregroundStyle(Roam.signal).listRowBackground(Roam.paperRaised) }
            switch model?.phase ?? .idle {
            case .idle:
                Text("Search for the place you visited.").foregroundStyle(Roam.inkMuted).listRowBackground(Roam.paperRaised)
            case .loading:
                HStack { ProgressView(); Text("Searching…").foregroundStyle(Roam.inkMuted) }.listRowBackground(Roam.paperRaised)
            case .failed(let message):
                InlineRetryView(message: message) { Task { await model?.search(query, near: nil) } }.listRowBackground(Roam.paperRaised)
            case .noResults:
                Text("No places match \u{201C}\(query)\u{201D}.").foregroundStyle(Roam.inkMuted)
                    .accessibilityIdentifier("log-place-no-results").listRowBackground(Roam.paperRaised)
            case .results:
                ForEach(model?.hits ?? []) { hit in
                    Button { Task { await choose(hit) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.candidate.name).font(.headline).foregroundStyle(Roam.ink)
                                Text(hit.candidate.address ?? [hit.candidate.locality, hit.candidate.countryName].compactMap { $0 }.joined(separator: ", "))
                                    .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(2)
                            }
                            Spacer(minLength: Theme.Spacing.s)
                            if opening == hit.id { ProgressView() }
                        }
                        .frame(minHeight: Theme.minimumHitTarget)
                    }
                    .disabled(opening != nil)
                    .accessibilityIdentifier("log-place-result-\(hit.candidate.name)")
                    .listRowBackground(Roam.paperRaised)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func choose(_ hit: SearchHit) async {
        opening = hit.id
        defer { opening = nil }
        do {
            guard let model else { return }
            let summary = try await model.resolve(hit)
            var logRequest = try await services.makeLogRequest(experienceID: summary.id)
            logRequest.startsWithDetails = true
            request = logRequest
        } catch { self.error = error.roamMessage }
    }
}
