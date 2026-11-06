import SwiftUI
import UIKit

/// Loads private media through the media service (signed/authorized reads) with an in-memory cache.
@MainActor
@Observable
final class ImageStore {
    private let media: (any MediaService)?
    private var cache: [String: UIImage] = [:]
    private var failures: Set<String> = []
    private struct Flight {
        let id: UUID
        let generation: Int
        let task: Task<UIImage?, Never>
    }
    private var inFlight: [String: Flight] = [:]
    private(set) var generation = 0

    init(media: (any MediaService)?) {
        self.media = media
    }

    func cached(_ path: String) -> UIImage? { cache[path] }

    func hasFailed(_ path: String) -> Bool { failures.contains(path) }

    func image(for path: String) async -> UIImage? {
        if let image = cache[path] { return Task.isCancelled ? nil : image }
        guard let media else { return nil }
        let flight: Flight
        if let pending = inFlight[path] { flight = pending }
        else {
            failures.remove(path)
            let task = Task<UIImage?, Never> {
                guard let data = try? await media.imageData(path: path) else { return nil }
                return UIImage(data: data)
            }
            flight = Flight(id: UUID(), generation: generation, task: task)
            inFlight[path] = flight
        }
        let image = await flight.task.value
        guard generation == flight.generation else { return nil }
        if inFlight[path]?.id == flight.id {
            inFlight[path] = nil
            if let image { cache[path] = image } else { failures.insert(path) }
        }
        return Task.isCancelled ? nil : cache[path]
    }

    func clear() {
        generation += 1
        cache.removeAll()
        failures.removeAll()
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
    }

    func store(_ image: UIImage, for path: String, generation expectedGeneration: Int? = nil) {
        guard expectedGeneration.map({ $0 == generation }) ?? true else { return }
        inFlight.removeValue(forKey: path)?.task.cancel()
        failures.remove(path)
        cache[path] = image
    }
}

/// Visit photo with loading, error (tap to retry) and missing states; never a stock image.
struct RemoteImageView: View {
    let path: String?
    var contentMode: ContentMode = .fill
    var accessibilityLabel: String = "Visit photo"

    @Environment(ImageStore.self) private var store
    @State private var image: UIImage?
    @State private var failed = false
    @State private var attempt = 0
    @State private var loadedIdentity: String?
    @State private var activeRequest = UUID()
    private var identity: String { "\(path ?? "-")-\(attempt)-\(store.generation)" }

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.subtleFill)
            if let image, loadedIdentity == identity {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(accessibilityLabel)
            } else if (failed && loadedIdentity == identity) || path == nil {
                Button {
                    attempt += 1
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text(path == nil ? "No photo" : "Photo unavailable · Retry").font(.caption2)
                    }
                    .foregroundStyle(Theme.secondaryText)
                }
                .disabled(path == nil)
                .accessibilityLabel(path == nil ? "No photo" : "Photo unavailable. Retry")
            } else {
                ProgressView()
                    .accessibilityLabel("Loading photo")
            }
        }
        .clipped()
        .task(id: identity) {
            let request = UUID(), currentIdentity = identity
            activeRequest = request
            image = nil
            loadedIdentity = nil
            failed = false
            guard let path else { return }
            let loaded = await store.image(for: path)
            guard !Task.isCancelled, activeRequest == request, currentIdentity == identity else { return }
            image = loaded
            failed = loaded == nil
            loadedIdentity = currentIdentity
        }
    }
}

/// Circular avatar with initials fallback when no photo exists or loading fails.
struct AvatarView: View {
    let member: MemberSummary
    var size: CGFloat = 44

    @Environment(ImageStore.self) private var store
    @State private var image: UIImage?
    @State private var loadedIdentity: String?
    @State private var activeRequest = UUID()
    /// The avatar and its initials grow with Dynamic Type, up to 125%, so rows stay balanced.
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    private var identity: String { "\(member.id.uuidString)-\(member.avatarPath ?? "-")-\(store.generation)" }
    private var scaledSize: CGFloat { size * min(max(textScale, 1), 1.25) }

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentFill)
            if let image, loadedIdentity == identity {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: scaledSize * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: scaledSize, height: scaledSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline.opacity(0.6)))
        .accessibilityHidden(true)
        .task(id: identity) {
            let request = UUID(), currentIdentity = identity
            activeRequest = request
            image = nil
            loadedIdentity = nil
            guard let path = member.avatarPath else { return }
            let loaded = await store.image(for: path)
            guard !Task.isCancelled, activeRequest == request, currentIdentity == identity else { return }
            image = loaded
            loadedIdentity = currentIdentity
        }
    }

    private var initials: String {
        let parts = member.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(member.handle.prefix(1)).uppercased() : letters.uppercased()
    }
}
