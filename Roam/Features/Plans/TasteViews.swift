import SwiftUI
import UIKit

/// Your Tastes: short, skippable and editable at any time.
struct TasteEditorView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var taste = TasteProfile.empty
    @State private var loaded = false
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form { Group {
            ForEach(TasteProfile.questions) { question in
                Section(question.title) {
                    Picker(question.title, selection: Binding(get: { taste[keyPath: question.keyPath] ?? "" },
                                                              set: { taste[keyPath: question.keyPath] = $0.isEmpty ? nil : $0 })) {
                        Text("Skip").tag("")
                        ForEach(question.options, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("taste-\(question.title)")
                }
                .listRowBackground(Roam.paperRaised)
            }
            if let error { Section { Text(error).foregroundStyle(Roam.signal) }.listRowBackground(Roam.paperRaised) }
        }
        .listRowBackground(Roam.paperRaised)
        }
        .scrollContentBackground(.hidden)
        .background(Roam.paper)
        .navigationTitle("Your Tastes")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }.disabled(saving || !loaded).accessibilityIdentifier("taste-save")
            }
        }
        .task {
            do { taste = try await services.plans.taste(); loaded = true }
            catch { self.error = error.roamMessage }
        }
        .screenIdentifier("taste-editor")
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            taste = try await services.plans.saveTaste(taste)
            dismiss()
        } catch { self.error = error.roamMessage }
    }
}

/// Plans a trip with an AI assistant: explains how, then hands over a prompt built from your tastes and favourite
/// places. Nothing leaves Roam unless the member copies it or opens an assistant.
struct ResearchBriefSheet: View {
    let destination: Destination

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Image(systemName: "sparkles").font(.title).foregroundStyle(PlaceState.planned.markerColor).accessibilityHidden(true)
                        Text("Plan \(destination.name) with AI").font(.roamTitle()).accessibilityAddTraits(.isHeader)
                        Text("We wrote a prompt from your tastes and the places you've loved. Paste it into ChatGPT or Claude for an itinerary, neighbourhoods to stay in and places to try. Then save the ones you like to your wishlist here.")
                            .font(.subheadline).foregroundStyle(Roam.inkMuted)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Your prompt").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                        TextEditor(text: $text)
                            .font(.subheadline)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 200)
                            .padding(Theme.Spacing.s)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Roam.paperRaised))
                            .accessibilityIdentifier("research-brief-text")
                        Text("Edit it however you like.").font(.caption).foregroundStyle(Roam.inkMuted)
                    }
                    // One row: open an assistant (the prompt is copied on the way), or just copy it.
                    HStack(spacing: Theme.Spacing.s) {
                        assistantButton("ChatGPT", url: "https://chatgpt.com/")
                        assistantButton("Claude", url: "https://claude.ai/new")
                        Button { copy() } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 24, height: 44)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(copied ? "Copied" : "Copy prompt")
                        .accessibilityIdentifier("research-brief-copy")
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Roam.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await build() }
        }
        .roamSheetStyle()
    }

    /// Copies the prompt first, so it's ready to paste when the assistant opens.
    private func assistantButton(_ title: String, url: String) -> some View {
        Button {
            copy()
            if let url = URL(string: url) { openURL(url) }
        } label: {
            Label(title, systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity).frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(PlaceState.planned.markerColor)
        .accessibilityLabel("Open \(title)")
        .accessibilityHint("Copies the prompt, then opens the assistant")
    }

    private func copy() {
        UIPasteboard.general.string = text
        copied = true
    }

    private func build() async {
        let taste = (try? await services.plans.taste()) ?? .empty
        var liked: [String] = []
        if let me = session.userID, let been = try? await services.lists.been(ownerID: me) {
            liked = been.filter { $0.ownerSentiment == .liked }.prefix(5).map(\.experience.name)
        }
        text = ResearchBrief.text(destination: destination, taste: taste, liked: liked)
    }
}
