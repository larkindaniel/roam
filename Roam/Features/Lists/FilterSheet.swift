import SwiftUI

/// S13: edits a sheet-local draft. Clear all clears the draft, Apply applies it, Cancel discards it.
struct FilterSheet: View {
    let kind: ListKind
    let cities: [FacetOption]
    let countries: [FacetOption]
    let applied: ListFilter
    let onApply: (ListFilter) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft = ListFilter()
    @State private var citySearch = ""

    var body: some View {
        NavigationStack {
            List { Group {
                Section("Category") {
                    FlowChips(items: ExperienceCategory.allCases.map { ($0.rawValue, $0.title, $0.symbolName) },
                              selected: Set(draft.categories.map(\.rawValue))) { raw in
                        if let category = ExperienceCategory(rawValue: raw) {
                            if draft.categories.contains(category) { draft.categories.remove(category) } else { draft.categories.insert(category) }
                        }
                    }
                }
                if kind == .been {
                    Section {
                        Toggle("Unranked places only", isOn: $draft.unrankedMemories)
                            .accessibilityIdentifier("filter-unranked")
                    } footer: {
                        Text("Show only places you've visited but not ranked.")
                    }
                }
                Section("City") {
                    if cities.count > 6 {
                        TextField("Search cities", text: $citySearch)
                    }
                    if cities.isEmpty { Text("No cities yet").foregroundStyle(Theme.secondaryText) }
                    ForEach(cities.filter { citySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(citySearch) }) { option in
                        checkRow(option, isOn: draft.cityKeys.contains(option.id)) {
                            if draft.cityKeys.contains(option.id) { draft.cityKeys.remove(option.id) } else { draft.cityKeys.insert(option.id) }
                        }
                    }
                }
                Section("Country") {
                    if countries.isEmpty { Text("No countries yet").foregroundStyle(Theme.secondaryText) }
                    ForEach(countries) { option in
                        checkRow(option, isOn: draft.countryCodes.contains(option.id)) {
                            if draft.countryCodes.contains(option.id) { draft.countryCodes.remove(option.id) } else { draft.countryCodes.insert(option.id) }
                        }
                    }
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .accessibilityIdentifier("filter-options")
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("filter-cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Theme.Spacing.s))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.m))
                layout {
                    Button("Clear all") { draft = ListFilter() }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(draft.isEmpty)
                        .accessibilityIdentifier("filter-clear")
                    Button(draft.activeCount > 0 ? "Apply (\(draft.activeCount))" : "Apply") {
                        onApply(draft)
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("filter-apply")
                }
                .padding(Theme.Spacing.l)
                .background(.bar)
            }
            .onAppear { draft = applied }
        }
        .roamSheetStyle()
        .screenIdentifier("filter-sheet")
    }

    private func checkRow(_ option: FacetOption, isOn: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack {
                Image(systemName: isOn ? "checkmark.square.fill" : "square").foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.title).foregroundStyle(.primary)
                    if let subtitle = option.subtitle, !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(Theme.secondaryText) }
                }
                Spacer()
                Text("\(option.count)").foregroundStyle(Theme.secondaryText).monospacedDigit()
            }
            .frame(minHeight: Theme.minimumHitTarget)
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("filter-option-\(option.title)")
    }
}

/// Wrapping selectable chips.
struct FlowChips: View {
    let items: [(id: String, title: String, symbol: String)]
    let selected: Set<String>
    let toggle: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            // Intrinsically sized pills can exceed a compact screen at accessibility sizes.
            // Full-width rows keep every label and selection reachable in the enclosing List.
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Button { toggle(item.id) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                            Image(systemName: selected.contains(item.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(Theme.accent)
                            Label(item.title, systemImage: item.symbol)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    .accessibilityIdentifier("chip-\(item.id)")
                }
            }
        } else {
            WrapLayout(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Button { toggle(item.id) } label: { PillLabel(title: item.title, systemImage: item.symbol) }
                        .buttonStyle(PillButtonStyle(isSelected: selected.contains(item.id)))
                        .accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                        .accessibilityIdentifier("chip-\(item.id)")
                }
            }
        }
    }
}

/// Simple flow layout that wraps children onto new lines.
struct WrapLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
