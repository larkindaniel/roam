import MapKit
import SwiftUI

/// Your logs of a place, as rows like My Places' trips: the visit's first photo with the been mark, its date and how
/// you felt, an edit button and a chevron. Opening a row shows the rest of its photos, its note and who can see it;
/// swiping it left deletes it. + Add visit runs across the bottom.
struct MyVisitsCard: View {
    let visits: [Visit]
    var sentiment: Sentiment?
    /// The place's own photo, for a visit with none of its own.
    var placePhotoURL: URL?
    let coordinate: CLLocationCoordinate2D
    var symbol = "mappin"
    var disabled = false
    let onAdd: () -> Void
    let onEdit: (Visit) -> Void
    let onDelete: (Visit) -> Void
    let onOpenPhotos: (Visit) -> Void

    @State private var open: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            ForEach(visits) { visit in
                SwipeToDelete(disabled: disabled) { onDelete(visit) } content: { row(visit) }
                if visit.id != visits.last?.id { RowSeparator() }
            }
            addButton.padding(.top, Theme.Spacing.s)
        }
        .roamCard(padding: Theme.Spacing.m)
        .accessibilityIdentifier("detail-memories")
    }

    private func photos(_ visit: Visit) -> [MediaRef] { visit.media.sorted { $0.position < $1.position } }

    private func row(_ visit: Visit) -> some View {
        let isOpen = open.contains(visit.id)
        let media = photos(visit)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                ZStack(alignment: .bottomTrailing) {
                    PlaceThumbnail(id: "visit-\(visit.id)", path: media.first?.path, url: placePhotoURL,
                                   coordinate: coordinate, symbol: symbol, size: 48)
                    StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6)
                }
                HStack(spacing: 6) {
                    Text(visit.visitDate.displayString).font(.headline).foregroundStyle(Roam.ink)
                    if let sentiment {
                        Image(systemName: sentiment.symbolName)
                            .font(.subheadline)
                            .foregroundStyle(color(sentiment))
                            .accessibilityLabel(sentiment.shortTitle)
                    }
                }
                Spacer(minLength: 0)
                Button { onEdit(visit) } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Roam.ink)
                        .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled)
                .accessibilityLabel("Edit this visit")
                .accessibilityIdentifier("detail-edit-visit-\(visit.id.uuidString)")
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Roam.inkMuted)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { if isOpen { open.remove(visit.id) } else { open.insert(visit.id) } } }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: isOpen ? "Hide details" : "Show details") {
                if isOpen { open.remove(visit.id) } else { open.insert(visit.id) }
            }
            if isOpen { details(visit, media: media) }
        }
        .padding(.vertical, Theme.Spacing.s)
    }

    /// The rest of the photos at the same size (the first is on the row), the note, and who can see it.
    private func details(_ visit: Visit, media: [MediaRef]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if media.count > 1 {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48, maximum: 48), spacing: Theme.Spacing.s)],
                          alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(Array(media.dropFirst().enumerated()), id: \.element.id) { index, item in
                        Button { onOpenPhotos(visit) } label: {
                            RemoteImageView(path: item.path, accessibilityLabel: "Photo \(index + 2) from this visit")
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !visit.publicNote.isEmpty {
                Text(visit.publicNote).font(.subheadline).foregroundStyle(Roam.ink).fixedSize(horizontal: false, vertical: true)
            }
            Label(visit.audience.title, systemImage: audienceSymbol(visit.audience))
                .font(.footnote).foregroundStyle(Roam.inkMuted)
        }
        .padding(.leading, 48 + Theme.Spacing.m)
        .transition(.opacity)
    }

    private func color(_ sentiment: Sentiment) -> Color {
        switch sentiment {
        case .liked: return PlaceState.visited.markerColor
        case .fine: return Roam.inkMuted
        case .disliked: return .red
        }
    }

    private func audienceSymbol(_ audience: Audience) -> String {
        switch audience {
        case .onlyMe: return "lock.fill"
        case .friends: return "person.2.fill"
        case .public: return "globe"
        }
    }

    /// A light green bubble the full width, like + New trip's in blue.
    private var addButton: some View {
        Button(action: onAdd) {
            Label("Add visit", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(PlaceState.visited.markerColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(PlaceState.visited.markerColor.opacity(0.15)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("detail-add-visit-bottom")
    }
}

/// A row that swipes left to show a red Delete pill, as a list's rows do; swiping far enough deletes straight away.
/// It's for rows in a card rather than a List, which has this built in.
struct SwipeToDelete<Content: View>: View {
    var disabled = false
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var settled: CGFloat = 0
    @State private var horizontal: Bool?
    private let reveal: CGFloat = 84

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button(role: .destructive) { delete() } label: {
                    Image(systemName: "trash.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Capsule().fill(.red))
                }
                .buttonStyle(.plain)
                .frame(width: max(0, -offset - Theme.Spacing.s))
                .padding(.vertical, Theme.Spacing.s)
                .accessibilityLabel("Delete")
            }
            content()
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 16)
                .onChanged { value in
                    guard !disabled else { return }
                    if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                    guard horizontal == true else { return }
                    offset = min(0, settled + value.translation.width)
                }
                .onEnded { value in
                    defer { horizontal = nil }
                    guard horizontal == true else { return }
                    let end = settled + value.predictedEndTranslation.width
                    withAnimation(.snappy) {
                        if end < -reveal * 2.5 { delete(); return }
                        offset = end < -reveal / 2 ? -reveal : 0
                        settled = offset
                    }
                }
        )
        .accessibilityAction(named: "Delete") { delete() }
    }

    private func delete() {
        withAnimation(.snappy) { offset = 0; settled = 0 }
        onDelete()
    }
}
