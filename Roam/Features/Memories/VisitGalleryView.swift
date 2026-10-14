import SwiftUI

/// S07: visit photos for one Visit, or every public memory photo of an experience. Owners can
/// remove their own photo (an acknowledged Visit edit); anyone can report another member's photo.
struct VisitGalleryView: View {
    let experienceID: UUID
    let visitID: UUID?

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(AppRouter.self) private var router
    @Environment(LibraryStore.self) private var library
    @State private var model: VisitGalleryModel?
    @State private var viewer: GalleryViewerSelection?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4)]

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle(visitID == nil ? "Photos" : "Visit photos")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil, let owner = session.userID {
                model = VisitGalleryModel(experienceID: experienceID, visitID: visitID, ownerID: owner, memories: services.memories,
                                          storage: services.storage, currentAccount: { session.userID })
            }
            await model?.load()
        }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .onChange(of: model?.removedPhotoID) { _, removed in if removed != nil { library.noteChanged() } }
        .fullScreenCover(item: $viewer) { selection in
            if let model {
                GalleryPhotoViewer(model: model, selectedID: selection.photoID) { authorID in
                    viewer = nil
                    router.push(.member(authorID))
                }
            }
        }
        .screenIdentifier("visit-gallery")
    }

    @ViewBuilder private func content(_ model: VisitGalleryModel) -> some View {
        if model.photos.isEmpty {
            if model.isLoading {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(0..<6, id: \.self) { _ in Rectangle().fill(Theme.subtleFill).aspectRatio(1, contentMode: .fit) }
                    }
                    .accessibilityElement().accessibilityLabel("Loading photos")
                    .accessibilityIdentifier("gallery-loading")
                }
            } else if let error = model.error {
                // State identifiers sit on inner containers; the screen identifier owns the scroll view.
                ScrollView {
                    VStack {
                        EmptyStateView(systemImage: "photo.badge.exclamationmark", title: "Couldn't load photos", message: error,
                                       primaryTitle: "Try again", primaryAction: { Task { await model.load() } })
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("gallery-error")
                }
            } else {
                ScrollView {
                    VStack {
                        EmptyStateView(systemImage: "photo.on.rectangle", title: "No photos yet",
                                       message: visitID == nil ? "Photos appear here when travellers add them to their visits."
                                                               : "This visit has no photos.")
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("gallery-empty")
                }
            }
        } else {
            ScrollView {
                if let error = model.error {
                    InlineRetryView(message: error, retryTitle: model.pendingRemoval == nil ? "Reload" : "Retry removal") {
                        Task { if model.pendingRemoval != nil { await model.retryRemoval() } else { await model.load() } }
                    }
                    .padding(.horizontal, Theme.Spacing.l)
                    .accessibilityIdentifier("gallery-inline-error")
                }
                if visitID != nil, let photo = model.photos.first {
                    Text("\(photo.isOwn ? "Your visit" : photo.authorName) · \(photo.date.date.map { "Visited \($0.displayString)" } ?? "Visit date unknown")")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                        .accessibilityIdentifier("gallery-visit-caption")
                }
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                        Button { viewer = GalleryViewerSelection(photoID: photo.id) } label: {
                            Color.clear.aspectRatio(1, contentMode: .fit)
                                .overlay { RemoteImageView(path: photo.media.path, accessibilityLabel: label(photo, index: index)) }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(label(photo, index: index))
                        .accessibilityHint("Opens the photo")
                        .accessibilityIdentifier("gallery-photo-\(index)")
                    }
                }
                PaginationFooter(isLoading: model.loadingMore, errorMessage: model.pageError, hasMore: model.nextCursor != nil) {
                    Task { await model.loadMore() }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            .refreshable { await model.load() }
        }
    }

    private func label(_ photo: GalleryPhoto, index: Int) -> String {
        "Photo \(index + 1), \(photo.isOwn ? "your visit" : photo.authorName), \(photo.date.displayString)"
    }
}

private struct GalleryViewerSelection: Identifiable, Hashable {
    let photoID: UUID
    var id: UUID { photoID }
}

/// Full-screen paged viewer. Removal states exactly what is changed; reports say they are stored, not reviewed.
private struct GalleryPhotoViewer: View {
    let model: VisitGalleryModel
    let onOpenAuthor: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID
    @State private var confirmingRemoval: GalleryPhoto?
    @State private var reportTarget: ReportTarget?

    init(model: VisitGalleryModel, selectedID: UUID, onOpenAuthor: @escaping (UUID) -> Void) {
        self.model = model
        self.onOpenAuthor = onOpenAuthor
        _selectedID = State(initialValue: selectedID)
    }

    private var selected: GalleryPhoto? { model.photos.first { $0.id == selectedID } ?? model.photos.first }

    var body: some View {
        NavigationStack {
            pages
                .safeAreaInset(edge: .bottom) { if let selected { footer(selected) } }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.accessibilityIdentifier("viewer-close")
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .onChange(of: model.photos) { _, photos in
                    if !photos.contains(where: { $0.id == selectedID }), let first = photos.first { selectedID = first.id }
                }
                .confirmationDialog("Remove this photo?", isPresented: removalBinding, titleVisibility: .visible,
                                    presenting: confirmingRemoval) { photo in
                    Button("Remove photo", role: .destructive) { Task { await model.remove(photo) } }
                        .accessibilityIdentifier("confirm-remove-photo")
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("The photo is removed from this visit and its post. Your visit, note and ranking stay.")
                }
                .sheet(item: $reportTarget) { target in
                    ReportSheet(target: target, title: "Report photo")
                }
        }
        .screenIdentifier("photo-viewer")
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } })
    }

    @ViewBuilder private var pages: some View {
        if model.photos.isEmpty {
            EmptyStateView(systemImage: "photo", title: "No photos", message: "There are no more photos to show.",
                           primaryTitle: "Close", primaryAction: { dismiss() })
        } else {
            TabView(selection: $selectedID) {
                ForEach(Array(model.photos.enumerated()), id: \.element.id) { index, photo in
                    page(photo, index: index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: model.photos.count > 1 ? .always : .never))
            .background(Color.black)
        }
    }

    private func page(_ photo: GalleryPhoto, index: Int) -> some View {
        RemoteImageView(path: photo.media.path, contentMode: .fit, accessibilityLabel: "Photo \(index + 1) of \(model.photos.count)")
            .tag(photo.id)
            .accessibilityIdentifier("viewer-photo-\(index)")
    }

    private func footer(_ photo: GalleryPhoto) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button { onOpenAuthor(photo.ownerID) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.isOwn ? "Your visit" : photo.authorName).font(.headline)
                    Text(photo.date.date.map { "Visited \($0.displayString)" } ?? "Visit date unknown")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the profile")
            .accessibilityIdentifier("viewer-author")
            if let error = model.error {
                Text(error).font(.footnote).foregroundStyle(Theme.disliked).accessibilityIdentifier("viewer-error")
            }
            HStack {
                if photo.isOwn {
                    if model.pendingRemoval != nil {
                        Button("Retry removal") { Task { await model.retryRemoval() } }
                            .disabled(model.isRemoving)
                            .accessibilityIdentifier("viewer-retry-removal")
                    } else {
                        Button("Remove photo", role: .destructive) { confirmingRemoval = photo }
                            .disabled(model.isRemoving)
                            .accessibilityIdentifier("viewer-remove")
                    }
                } else {
                    Button { reportTarget = .media(photo.media.id) } label: { Label("Report photo", systemImage: "flag") }
                        .accessibilityIdentifier("viewer-report")
                }
                if model.isRemoving { ProgressView().accessibilityIdentifier("viewer-removing") }
                Spacer(minLength: 0)
            }
            .frame(minHeight: Theme.minimumHitTarget)
        }
        .padding(Theme.Spacing.l)
        .background(.regularMaterial)
    }
}
