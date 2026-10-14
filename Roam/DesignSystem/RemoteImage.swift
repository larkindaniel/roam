import SwiftUI
import UIKit

/// Loads private media through the media service (signed/authorized reads) with an in-memory cache.
@MainActor
@Observable
final class ImageStore {
    private let media: (any MediaService)?
    private var cache: [String: UIImage] = [:]
    private var failures: Set<String> = []
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init(media: (any MediaService)?) {
        self.media = media
    }

    func cached(_ path: String) -> UIImage? { cache[path] }

    func hasFailed(_ path: String) -> Bool { failures.contains(path) }

    func image(for path: String) async -> UIImage? {
        if let image = cache[path] { return image }
        if let task = inFlight[path] { return await task.value }
        guard let media else { return nil }
        failures.remove(path)
        let task = Task<UIImage?, Never> {
            guard let data = try? await media.imageData(path: path) else { return nil }
            return UIImage(data: data)
        }
        inFlight[path] = task
        let image = await task.value
        inFlight[path] = nil
        if let image { cache[path] = image } else { failures.insert(path) }
        return image
    }

    func clear() {
        cache.removeAll()
        failures.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    func store(_ image: UIImage, for path: String) { cache[path] = image }
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

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.subtleFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .accessibilityLabel(accessibilityLabel)
            } else if failed || path == nil {
                Button {
                    attempt += 1
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text(path == nil ? "No photo" : "Photo unavailable · Retry").font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .disabled(path == nil)
                .accessibilityLabel(path == nil ? "No photo" : "Photo unavailable. Retry")
            } else {
                ProgressView()
                    .accessibilityLabel("Loading photo")
            }
        }
        .clipped()
        .task(id: "\(path ?? "-")-\(attempt)") {
            guard let path else { return }
            if let cached = store.cached(path) { image = cached; return }
            failed = false
            let loaded = await store.image(for: path)
            image = loaded
            failed = loaded == nil
        }
    }
}

/// Circular avatar with initials fallback when no photo exists or loading fails.
struct AvatarView: View {
    let member: MemberSummary
    var size: CGFloat = 44

    @Environment(ImageStore.self) private var store
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle().fill(Theme.accentFill)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Theme.hairline.opacity(0.6)))
        .accessibilityHidden(true)
        .task(id: member.avatarPath) {
            guard let path = member.avatarPath else { image = nil; return }
            image = await store.image(for: path)
        }
    }

    private var initials: String {
        let parts = member.displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined()
        return letters.isEmpty ? String(member.handle.prefix(1)).uppercased() : letters.uppercased()
    }
}
