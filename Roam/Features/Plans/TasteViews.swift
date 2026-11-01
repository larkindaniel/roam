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

/// Reviews and copies the brief. Nothing leaves Roam unless the member pastes it somewhere.
struct ResearchBriefSheet: View {
    let destination: Destination

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Edit this, copy it, then paste it into ChatGPT or Claude.")
                    .font(.subheadline).foregroundStyle(Roam.inkMuted)
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Roam.paperRaised))
                    .accessibilityIdentifier("research-brief-text")
                Button(copied ? "Copied" : "Copy research brief") {
                    UIPasteboard.general.string = text
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("research-brief-copy")
            }
            .padding()
            .navigationTitle("Research further")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await build() }
        }
        .roamSheetStyle()
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
