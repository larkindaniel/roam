import MapKit
import SwiftUI

/// Your logs of a place, as rows like My Places' trips: the visit's first photo with the been mark, its date with the
/// start of its note, and a chevron that opens it in the log screen; swiping it left deletes it. + Add visit runs across
/// the bottom.
struct MyVisitsCard: View {
    let visits: [Visit]
    /// The place's own photo, for a visit with none of its own.
    var placePhotoURL: URL?
    let coordinate: CLLocationCoordinate2D
    var symbol = "mappin"
    var disabled = false
    let onAdd: () -> Void
    let onEdit: (Visit) -> Void
    let onDelete: (Visit) -> Void

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

    /// The first photo with the been mark, the date with the note's start under it, and a chevron; tapping opens the
    /// log screen to change it.
    private func row(_ visit: Visit) -> some View {
        Button { onEdit(visit) } label: {
            HStack(spacing: Theme.Spacing.m) {
                ZStack(alignment: .bottomTrailing) {
                    PlaceThumbnail(id: "visit-\(visit.id)", path: photos(visit).first?.path, url: placePhotoURL,
                                   coordinate: coordinate, symbol: symbol, size: 48)
                    StatusMark(state: .visited).scaleEffect(0.75).offset(x: 6, y: 6)
                }
                // The note's start tucked right under the date.
                VStack(alignment: .leading, spacing: -2) {
                    Text(visit.visitDate.displayString).font(.headline).foregroundStyle(Roam.ink).lineLimit(1)
                    if let companions = visit.companions, !companions.isEmpty {
                        Text("With \(companions.map(\.displayName).formatted(.list(type: .and)))")
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                    if !visit.publicNote.isEmpty {
                        Text(visit.publicNote.replacingOccurrences(of: "\n", with: " "))
                            .font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1).truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.vertical, Theme.Spacing.s)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityHint("Edit this visit")
        .accessibilityIdentifier("detail-edit-visit-\(visit.id.uuidString)")
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
