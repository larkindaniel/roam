import PhotosUI
import SwiftUI

/// A working copy of the photo selection. Cancel restores its checkpoint, including order
/// and failures, and discards only uploads created during this editor session.
struct PhotoDraftEditor: View {
    let model: PhotoDraftModel
    var failureMessage: () -> String? = { nil }
    let onDone: () -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var checkpoint: PhotoDraftCheckpoint?
    @State private var importing = false
    @State private var restoring = false
    @State private var error: String?
    @State private var importGeneration = 0
    @State private var importTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List { Group {
                Section {
                    PhotosPicker(selection: $selectedItems, selectionBehavior: .ordered, matching: .images) {
                        Label("Choose photos", systemImage: "photo.on.rectangle.angled")
                            .frame(minHeight: Theme.minimumHitTarget)
                    }
                    .disabled(importing || restoring)
                    .accessibilityIdentifier("photo-picker")
                    Text(model.assets.count == 1 ? "1 photo" : "\(model.assets.count) photos").accessibilityIdentifier("photo-count")
                    if importing { ProgressView("Reading selected photos…").accessibilityIdentifier("photo-reading") }
                } footer: {
                    Text("Only photos you choose are read. Photos are private until your visit is saved. Failed photos must be retried or removed.")
                }
                ForEach(Array(model.assets.enumerated()), id: \.element.id) { index, asset in
                    Section {
                        HStack(alignment: .top, spacing: Theme.Spacing.m) {
                            thumbnail(asset)
                                .frame(width: 80, height: 80).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                                Text("Photo \(index + 1)").font(.headline)
                                Text(status(asset)).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                    .accessibilityIdentifier("photo-status-\(asset.id.uuidString)")
                                if let message = asset.error { Text(message).font(.footnote).foregroundStyle(Theme.disliked) }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("photo-asset-\(asset.id.uuidString)")
                        HStack {
                            if asset.status == .failed {
                                Button("Retry upload") { Task { await model.retry(assetID: asset.id) } }
                                    .disabled(model.isBusy || restoring)
                                    .accessibilityIdentifier("photo-retry-\(asset.id.uuidString)")
                            }
                            Button(role: .destructive) { Task { await model.remove(assetID: asset.id) } } label: {
                                Text("Remove").foregroundStyle(Theme.disliked)
                            }
                                .disabled(restoring)
                                .accessibilityIdentifier("photo-remove-\(asset.id.uuidString)")
                            Spacer(minLength: 0)
                            Button { model.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1) } label: {
                                Image(systemName: "arrow.up").frame(width: 44, height: 44)
                            }
                            .disabled(index == 0 || restoring)
                            .accessibilityLabel("Move photo \(index + 1) earlier")
                            .accessibilityIdentifier("photo-earlier-\(asset.id.uuidString)")
                            Button { model.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2) } label: {
                                Image(systemName: "arrow.down").frame(width: 44, height: 44)
                            }
                            .disabled(index + 1 == model.assets.count || restoring)
                            .accessibilityLabel("Move photo \(index + 1) later")
                            .accessibilityIdentifier("photo-later-\(asset.id.uuidString)")
                        }
                        .buttonStyle(.borderless)
                        .frame(minHeight: Theme.minimumHitTarget)
                    }
                }
                if let message = error ?? model.error {
                    Section { Text(message).foregroundStyle(Theme.disliked).accessibilityIdentifier("photo-editor-error") }
                }
            }
            .listRowBackground(Roam.paperRaised)
            }
            .accessibilityIdentifier("photo-editor-list")
            .navigationTitle("Visit photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        importGeneration += 1; importTask?.cancel()
                        restoring = true
                        Task {
                            if let checkpoint { await model.restore(checkpoint) }
                            dismiss()
                        }
                    }.disabled(restoring).accessibilityIdentifier("photo-editor-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if onDone() { dismiss() }
                        else { error = failureMessage() ?? "Your photo changes couldn't be kept. Try again." }
                    }
                    .disabled(!model.canCommit || importing || restoring)
                    .accessibilityIdentifier("photo-editor-done")
                }
            }
            .interactiveDismissDisabled()
            .onAppear { if checkpoint == nil { checkpoint = model.checkpoint() } }
            .onChange(of: selectedItems) { _, items in
                guard !items.isEmpty else { return }
                importTask?.cancel()
                importGeneration += 1
                let token = importGeneration
                importing = true
                importTask = Task { @MainActor in
                    for item in items {
                        guard token == importGeneration, !Task.isCancelled else { break }
                        do {
                            let data = try await item.loadTransferable(type: Data.self)
                            guard token == importGeneration, !Task.isCancelled else { break }
                            if let data { await model.add(data: data) }
                            else { model.addFailure(message: "This selected photo couldn't be read. Remove it or choose it again.") }
                        } catch {
                            guard token == importGeneration, !Task.isCancelled else { break }
                            model.addFailure(message: "This selected photo couldn't be read. Remove it or choose it again.")
                        }
                    }
                    guard token == importGeneration else { return }
                    importing = false
                    selectedItems = []
                }
            }
            .onDisappear { importGeneration += 1; importTask?.cancel() }
        }
        .roamSheetStyle()
        .screenIdentifier("photo-editor")
    }

    @ViewBuilder private func thumbnail(_ asset: PhotoDraftAsset) -> some View {
        if let data = model.thumbnailData(assetID: asset.id), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().accessibilityLabel("Selected visit photo")
        } else if let existing = asset.existing {
            RemoteImageView(path: existing.path)
        } else if let staged = asset.staged {
            RemoteImageView(path: staged.path)
        } else {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.subtleFill)
                .accessibilityLabel("Selected photo not ready")
        }
    }

    private func status(_ asset: PhotoDraftAsset) -> String {
        switch asset.status {
        case .preparing: return "Processing…"
        case .uploading: return "Uploading…"
        case .ready: return "Ready"
        case .existing: return "Saved photo"
        case .failed: return "Upload failed · Retry or remove"
        }
    }
}

/// A photo in a draft: what was picked on this device, else the uploaded copy.
struct PhotoDraftImage: View {
    let model: PhotoDraftModel
    let asset: PhotoDraftAsset

    var body: some View {
        if let data = model.thumbnailData(assetID: asset.id), let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().accessibilityLabel("Selected visit photo")
        } else if let existing = asset.existing {
            RemoteImageView(path: existing.path)
        } else if let staged = asset.staged {
            RemoteImageView(path: staged.path)
        } else {
            Image(systemName: "photo").font(.largeTitle).foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.subtleFill)
                .accessibilityLabel("Selected photo not ready")
        }
    }
}

/// Reads photos picked in the system picker into a draft, which uploads them.
@MainActor
enum PhotoImport {
    static func add(_ items: [PhotosPickerItem], to model: PhotoDraftModel) async {
        for item in items {
            guard !Task.isCancelled else { break }
            if let data = try? await item.loadTransferable(type: Data.self) { await model.add(data: data) }
            else { model.addFailure(message: "This selected photo couldn't be read. Remove it or choose it again.") }
        }
    }
}

/// A visit's photos one at a time, swiping for the next. The ✕ (for the photo showing) and any accessory (adding more)
/// sit on the frame itself, well inside it whatever shape the photo is.
struct PhotoCarousel<Accessory: View>: View {
    let model: PhotoDraftModel
    var height: CGFloat = 240
    @ViewBuilder var accessory: () -> Accessory
    @State private var current: UUID?

    var body: some View {
        TabView(selection: $current) {
            ForEach(model.assets) { asset in
                PhotoDraftImage(model: model, asset: asset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay {
                        if asset.status == .preparing || asset.status == .uploading { ProgressView().tint(.white) }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if asset.status == .failed {
                            Button("Retry") { Task { await model.retry(assetID: asset.id) } }
                                .font(.subheadline.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .padding(Theme.Spacing.l)
                        }
                    }
                    .tag(Optional(asset.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: model.assets.count > 1 ? .always : .never))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(alignment: .topTrailing) {
            Button {
                guard let id = current ?? model.assets.first?.id else { return }
                Task { await model.remove(assetID: id) }
            } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(.black.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.l)
            .accessibilityLabel("Remove this photo")
        }
        .overlay(alignment: .bottomTrailing) { accessory().padding(Theme.Spacing.l) }
        .onChange(of: model.assets.map(\.id)) { _, ids in
            // After adding or removing, show a photo that's there.
            if current.map({ !ids.contains($0) }) ?? true { current = ids.last }
        }
        .onAppear { current = current ?? model.assets.first?.id }
        .accessibilityIdentifier("photo-carousel")
    }
}

/// Your own photos of somewhere, one at a time, swiping for the next; shown to you ahead of Google's photo.
struct MyPhotoCarousel: View {
    let paths: [String]
    var height: CGFloat = 220

    var body: some View {
        TabView {
            ForEach(paths, id: \.self) { path in
                RemoteImageView(path: path, accessibilityLabel: "Your photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .tabViewStyle(.page(indexDisplayMode: paths.count > 1 ? .always : .never))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .accessibilityIdentifier("my-photos")
    }
}
