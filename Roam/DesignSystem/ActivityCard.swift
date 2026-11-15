import SwiftUI

/// A friend's log: a photo (theirs, square; else the place's Google photo) with a small "picture, name · date" line set
/// into its top, a slim card for the place under it, then their note.
struct ActivityCardView: View {
    /// Squarer corners for the photo and the place card than the app's usual cards.
    static let corner: CGFloat = 12

    let item: ActivityItem
    var compact = true
    /// Like and comment, set into the bottom right of the photo on a dark fade (white).
    var actions: AnyView? = nil
    /// Double-tapping the photo likes it.
    var onDoubleTap: (() -> Void)? = nil
    /// Tapping the photo once (the Friends tab opens the log's own page).
    var onTap: (() -> Void)? = nil
    /// The Friends tab shows the note's first line beside like and comment; the log's page shows it as the first comment.
    /// So the full note under the card is off by default.
    var showsNote = false

    static func hasPhoto(_ item: ActivityItem) -> Bool { !item.media.isEmpty || item.experience.photoURL != nil }

    @Environment(AppRouter.self) private var router
    @State private var expanded = false
    @State private var showsCollaborators = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if hasPhoto {
                // The place card sits close under its photo.
                VStack(spacing: Theme.Spacing.m) {
                    photos
                    placeChip
                }
            }
            if showsNote && !item.note.isEmpty {
                Text(item.note)
                    .font(.body)
                    .lineLimit(compact && !expanded && item.note.count >= 160 ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if compact && item.note.count >= 160 && !expanded {
                    Button("More") { expanded = true }
                        .font(.footnote.weight(.semibold))
                        .frame(minHeight: Theme.minimumHitTarget)
                }
            }
            // With a photo, the place is a slim card under it; without, the line and the standard row in a card.
            if !hasPhoto {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    byline(onPhoto: false)
                    placeRow
                }
                .roamCard(padding: Theme.Spacing.m)
            }
        }
        .foregroundStyle(Roam.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-card-\(item.id.uuidString)")
        // A small white card in the middle of the screen, over a dimmed page; tapping outside closes it.
        .fullScreenCover(isPresented: $showsCollaborators) {
            CollaboratorsSheet(people: [item.author] + collaborators)
                .presentationBackground(.clear)
        }
    }

    /// Everyone else on the log: friends who logged it with them, then anyone else they tagged with "With".
    private var collaborators: [MemberSummary] {
        var people = item.together
        for person in item.companions ?? [] where person.id != item.author.id && !people.contains(where: { $0.id == person.id }) {
            people.append(person)
        }
        return people
    }

    /// The popup fades in on its own, without the cover's slide up from the bottom.
    private func openCollaborators() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showsCollaborators = true }
    }

    private func openProfile(_ person: MemberSummary) {
        if MemberProfiles.available { router.push(.member(person.id)) }
    }

    private var hasPhoto: Bool { Self.hasPhoto(item) }

    /// Their picture, name · date, set into the top of the photo (white, on a soft dark fade), or on its own when there's
    /// no photo. With others, like Instagram: the pictures stacked, "Daniel Larkin with Nihal Menon" (or "with 2 others",
    /// which lists them in a small popup), and the date on the line below. Names open profiles.
    private func byline(onPhoto: Bool) -> some View {
        let others = collaborators
        let people = [item.author] + others
        return HStack(spacing: Theme.Spacing.s) {
            HStack(spacing: -10) {
                ForEach(Array(people.prefix(3).enumerated()), id: \.element.id) { index, person in
                    // Each picture opens that person's profile. The author's sits on top, then the next, and so on.
                    AvatarView(member: person, size: 28)
                        .overlay { if people.count > 1 { Circle().stroke(onPhoto ? Color.black.opacity(0.35) : Roam.paper, lineWidth: 1.5) } }
                        .contentShape(Circle())
                        .onTapGesture { openProfile(person) }
                        .zIndex(Double(3 - index))
                }
            }
            if others.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    Text(item.author.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("·").font(.subheadline).opacity(onPhoto ? 1 : 0.7)
                    date.font(.subheadline).lineLimit(1).opacity(onPhoto ? 1 : 0.75)
                }
                .contentShape(Rectangle())
                .onTapGesture { openProfile(item.author) }
            } else {
                VStack(alignment: .leading, spacing: -1) {
                    HStack(spacing: 4) {
                        Text(item.author.displayName).font(.subheadline.weight(.semibold))
                            .onTapGesture { openProfile(item.author) }
                        Text("with").font(.subheadline)
                        if others.count == 1 {
                            Text(others[0].displayName).font(.subheadline.weight(.semibold))
                                .onTapGesture { openProfile(others[0]) }
                        } else {
                            Text("\(others.count) others").font(.subheadline.weight(.semibold))
                                .onTapGesture { openCollaborators() }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("activity-collaborators")
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    date.font(.caption).lineLimit(1).opacity(onPhoto ? 0.9 : 0.75)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(onPhoto ? Color.white : Roam.ink)
        .padding(onPhoto ? Theme.Spacing.m : 0)
        // A deeper, taller fade, so the white line reads on any photo.
        .padding(.bottom, onPhoto ? Theme.Spacing.xl : 0)
        .background {
            if onPhoto {
                LinearGradient(colors: [.black.opacity(0.7), .black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                    // The fade itself doesn't take taps; the photo under it does.
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-author")
    }

    /// Their own photos, square, swiping between several; with none, the place's Google photo at its usual size. The
    /// byline sits in the top of either. Tapping a photo does nothing.
    @ViewBuilder private var photos: some View {
        Group {
            if !item.media.isEmpty {
                let media = item.media.sorted { $0.position < $1.position }
                PlaceGallery(items: media.map { .visitPhoto(path: $0.path) }, placeName: item.experience.name, square: true,
                             cornerRadius: Self.corner)
            } else if let url = item.experience.photoURL {
                // The credit shows on the place's own page, a tap away.
                PlaceGallery(items: [.photo(url, credit: nil)], placeName: item.experience.name, cornerRadius: Self.corner)
            }
        }
        .contentShape(Rectangle())
        // Double first, so a single tap waits to be sure it isn't one.
        .onTapGesture(count: 2) { onDoubleTap?() }
        .onTapGesture { onTap?() }
        .overlay(alignment: .top) {
            byline(onPhoto: true)
                // The photo's own corners, so the fade follows them.
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: Self.corner, topTrailingRadius: Self.corner, style: .continuous))
        }
        .overlay(alignment: .bottom) {
            if let actions {
                actions
                    .padding(.leading, Theme.Spacing.m)
                    .padding(.trailing, Theme.Spacing.m)
                    .padding(.bottom, Theme.Spacing.xs)
                    .padding(.top, Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.4), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Self.corner, bottomTrailingRadius: Self.corner, style: .continuous))
            }
        }
    }

    /// The place as a slim card under the photo, with no picture of its own: its name, city and country, and a chevron. It opens
    /// the place.
    private var placeChip: some View {
        Button { router.push(.experience(item.experience.id)) } label: {
            HStack(spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: -2) {
                    Text(item.experience.name).font(.subheadline.weight(.semibold)).foregroundStyle(Roam.ink).lineLimit(1)
                    if !item.experience.areaLine.isEmpty {
                        Text(item.experience.areaLine).font(.caption).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.s)
            // As wide as the photo, less its margins.
            .frame(maxWidth: .infinity)
            // Liquid Glass, like the floating buttons.
            .floatingBubble(RoundedRectangle(cornerRadius: Self.corner, style: .continuous), clear: true)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tapID("activity-place")
    }

    /// The place, as the standard row: its photo, name and where it is, and a chevron.
    private var placeRow: some View {
        Button { router.push(.experience(item.experience.id)) } label: {
            HStack(spacing: Theme.Spacing.m) {
                PlaceThumbnail(id: "activity-\(item.id)", url: item.experience.photoURL, coordinate: item.experience.coordinate,
                               symbol: item.experience.iconName, size: 48)
                VStack(alignment: .leading, spacing: -2) {
                    Text(item.experience.name).font(.headline).foregroundStyle(Roam.ink).lineLimit(1).truncationMode(.tail)
                    if !item.experience.areaLine.isEmpty {
                        Text(item.experience.areaLine).font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted).accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tapID("activity-place-row")
    }

    private var date: some View {
        Text(item.visitDate.date?.displayString ?? item.publishedAt.formatted(.relative(presentation: .named)))
    }
}

/// Who went together, from "with 2 others": a small solid white card in the middle of the screen over a dimmed page,
/// listing everyone; tapping one opens their profile, tapping outside closes it.
private struct CollaboratorsSheet: View {
    let people: [MemberSummary]
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Went together").font(.headline).accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(people) { person in
                        Button {
                            dismiss()
                            if MemberProfiles.available { router.push(.member(person.id)) }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                AvatarView(member: person, size: 40)
                                VStack(alignment: .leading, spacing: -2) {
                                    Text(person.displayName).font(.headline).lineLimit(1)
                                    Text("@\(person.handle)").font(.footnote).foregroundStyle(Roam.inkMuted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                            }
                            .padding(.vertical, Theme.Spacing.s)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if person.id != people.last?.id { RowSeparator(inset: 40 + Theme.Spacing.m) }
                    }
                }
            }
            .padding(Theme.Spacing.l)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Roam.paperRaised))
            .shadow(color: .black.opacity(0.2), radius: 24, y: 8)
            .padding(.horizontal, Theme.Spacing.xl)
            .scaleEffect(shown ? 1 : 0.92)
            .opacity(shown ? 1 : 0)
            .accessibilityIdentifier("collaborators-sheet")
        }
        .onAppear { withAnimation(.snappy(duration: 0.25)) { shown = true } }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.18)) { shown = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { dismiss() }
        }
    }
}
