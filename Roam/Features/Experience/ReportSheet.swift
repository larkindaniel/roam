import SwiftUI

/// Content/category report. Stores an actionable report and says so honestly — no instant correction
/// and no claim that a person has reviewed it.
struct ReportSheet: View {
    let target: ReportTarget
    var title = "Report a problem"
    var suggestedReason: ReportReason?

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason?
    @State private var text = ""
    @FocusState private var detailsFocused: Bool
    @State private var busy = false
    @State private var error: String?
    @State private var receipt: ReportReceipt?
    @State private var operationID = UUID()

    var body: some View {
        NavigationStack {
            Form { Group {
                if let receipt {
                    Section {
                        Label("Report received", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.liked).font(.headline)
                        Text("Thanks. Your report is stored for Roam's moderators (\(receipt.reason.title.lowercased())). Nothing changes automatically, and it hasn't been reviewed yet.")
                            .font(.subheadline)
                    }
                    .accessibilityIdentifier("report-received")
                } else {
                    Section("What's wrong?") {
                        ForEach(ReportReason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack {
                                    Text(option.title).foregroundStyle(.primary)
                                    Spacer()
                                    if reason == option { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                                .frame(minHeight: Theme.minimumHitTarget)
                            }
                            .accessibilityAddTraits(reason == option ? .isSelected : [])
                            .accessibilityIdentifier("report-reason-\(option.rawValue)")
                        }
                    }
                    Section {
                        TextField("Add details (optional)", text: $text, axis: .vertical)
                            .lineLimit(3...8)
                            .focused($detailsFocused)
                            // The field fills its whole box, so a tap anywhere in it starts typing.
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                            .onTapGesture { detailsFocused = true }
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            .accessibilityIdentifier("report-details")
                    } footer: {
                        Text("\(text.count)/\(Limits.reportTextMax)").foregroundStyle(text.count > Limits.reportTextMax ? Theme.disliked : .secondary)
                    }
                    if let error { Section { ErrorText(error) } }
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Cancel" : "Done") { dismiss() }
                }
                if receipt == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await submit() } }
                            .disabled(reason == nil || busy || text.count > Limits.reportTextMax)
                            .accessibilityIdentifier("report-send")
                    }
                }
            }
            .onAppear { if reason == nil { reason = suggestedReason } }
        }
        .roamSheetStyle()
    }

    private func submit() async {
        guard let reason else { return }
        busy = true
        defer { busy = false }
        do {
            receipt = try await services.social.report(target: target, reason: reason, text: text.isEmpty ? nil : text, operationID: operationID)
        } catch {
            // The same operation id is reused on retry, so the report is stored once.
            self.error = session.handle(error)
        }
    }
}
