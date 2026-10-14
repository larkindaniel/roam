import SwiftUI

/// Rating/revisit/rerank card. The score shown is the snapshot at posting time, labelled as such.
struct ActivityCardView: View {
    let item: ActivityItem
    var compact = false
    var onOpenAuthor: (() -> Void)?
    var onOpen: (() -> Void)?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Button { onOpenAuthor?() } label: { AvatarView(member: item.author, size: 40) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(item.author.displayName)'s profile")
                VStack(alignment: .leading, spacing: 2) {
                    (Text(item.author.displayName).bold() + Text(" \(item.type.verb) ") + Text(item.experience.name).bold())
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        CategoryBadge(category: item.category, compact: true)
                        if !item.experience.areaLine.isEmpty {
                            Text("· \(item.experience.areaLine)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Text(dateLine).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                ScoreBadge(score: item.scoreSnapshot, source: .snapshot, size: 42)
            }
            if !item.note.isEmpty {
                Text(item.note)
                    .font(.body)
                    .lineLimit(expanded || compact == false && item.note.count < 160 ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                if item.note.count >= 160 && !expanded {
                    Button("See more") { expanded = true }.font(.footnote.weight(.semibold))
                }
            }
            if !item.media.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(item.media) { media in
                            RemoteImageView(path: media.path, accessibilityLabel: "Photo from \(item.author.displayName)'s visit")
                                .frame(width: 150, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen?() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-card-\(item.id.uuidString)")
    }

    private var dateLine: String {
        let posted = item.publishedAt.formatted(.relative(presentation: .named))
        if let date = item.visitDate.date { return "Visited \(date.displayString) · posted \(posted)" }
        return "Visit date unknown · posted \(posted)"
    }
}
