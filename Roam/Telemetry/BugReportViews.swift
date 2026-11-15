import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The beta's bug button: a red circle with a bug, dressed like the profile picture, always the right-most button at the top of every page.
/// It snaps the screen as it is (offered as the report's screenshot), then opens Report a bug.
struct BugReportButton: View {
    /// The same size as your profile picture beside it.
    private let size = ProfileAvatarButton.standardSize
    @State private var report: BugReportContext?

    var body: some View {
        if Telemetry.shared.bugReportsEnabled {
            Button {
                report = BugReportContext(screenshot: Self.snapshot(), screen: Telemetry.shared.currentScreen)
            } label: {
                // Dressed like the profile picture: a red circle, the same thin white ring and soft shadow.
                BugGlyph()
                    .foregroundStyle(.white)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Roam.signal))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Report a bug")
            .tapID("report-bug")
            .sheet(item: $report) { context in
                BugReportSheet(context: context)
            }
        }
    }

    /// The window as it looks right now, before the sheet covers it.
    @MainActor static func snapshot() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: false) }
    }
}

/// The usual "report a bug" beetle: a pointed head set apart from an oval body split down the middle, and three bent
/// legs a side. SF Symbols only has a ladybird and an ant.
struct BugGlyph: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            let round = StrokeStyle(lineWidth: w * 0.075, lineCap: .round, lineJoin: .round)

            // Legs, each bent once, under the body.
            var legs = Path()
            for (start, knee, foot) in [((0.34, 0.45), (0.22, 0.39), (0.16, 0.27)),
                                        ((0.32, 0.56), (0.21, 0.57), (0.12, 0.66)),
                                        ((0.34, 0.68), (0.23, 0.73), (0.17, 0.85))] {
                legs.move(to: p(start.0, start.1)); legs.addLine(to: p(knee.0, knee.1)); legs.addLine(to: p(foot.0, foot.1))
                legs.move(to: p(1 - start.0, start.1)); legs.addLine(to: p(1 - knee.0, knee.1)); legs.addLine(to: p(1 - foot.0, foot.1))
            }
            context.stroke(legs, with: .foreground, style: round)

            // Head: a little house shape with soft corners.
            var head = Path()
            head.move(to: p(0.39, 0.29)); head.addLine(to: p(0.39, 0.2)); head.addLine(to: p(0.5, 0.13))
            head.addLine(to: p(0.61, 0.2)); head.addLine(to: p(0.61, 0.29)); head.closeSubpath()
            context.fill(head, with: .foreground)
            context.stroke(head, with: .foreground, style: StrokeStyle(lineWidth: w * 0.03, lineJoin: .round))

            // Body, then the split down its back cut out of it.
            context.fill(Path(ellipseIn: CGRect(x: w * 0.3, y: h * 0.35, width: w * 0.4, height: h * 0.52)), with: .foreground)
            context.blendMode = .clear
            context.fill(Path(CGRect(x: w * 0.475, y: h * 0.33, width: w * 0.05, height: h * 0.56)), with: .foreground)
            context.blendMode = .normal
        }
        .accessibilityHidden(true)
    }
}

struct BugReportContext: Identifiable {
    let id = UUID()
    let screenshot: UIImage?
    let screen: String?
}

extension View {
    /// Puts the bug button at the right-most end of this page's top bar. Applied once to every tab's pages; pages that
    /// draw their own top row (Discover, Friends) or no bar (welcome, setup, sheets) place a `BugReportButton` there.
    func bugReportToolbar() -> some View {
        toolbar {
            if #available(iOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) { BugReportButton() }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarTrailing) { BugReportButton() }
            }
        }
    }
}

/// Report a bug: what went wrong, the screenshot taken as the button was tapped, and any more screenshots or screen
/// recordings from Photos (up to six). It's sent with the steps that led up to it.
struct BugReportSheet: View {
    let context: BugReportContext

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var attachments: [Attachment] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var loadingAttachment = false
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?
    @FocusState private var focused: Bool
    @State private var noteFrame: CGRect = .zero

    struct Attachment: Identifiable {
        enum Content {
            case screenshot(UIImage)
            case recording(URL, thumbnail: UIImage?)
        }
        let id = UUID()
        var content: Content

        var preview: UIImage? {
            switch content {
            case .screenshot(let image): image
            case .recording(_, let thumbnail): thumbnail
            }
        }
        var isRecording: Bool { if case .recording = content { true } else { false } }
    }

    static let maxAttachments = 6

    init(context: BugReportContext) {
        self.context = context
        _attachments = State(initialValue: context.screenshot.map { [Attachment(content: .screenshot($0))] } ?? [])
    }

    private var signedIn: Bool { session.userID != nil }

    private var title: some View {
        Text("Report a bug").font(.roamTitle()).fixedSize().accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Laid out like Send: the note in a white card, then what's attached.
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    if sent {
                        Label("Sent. Thanks, we'll look into it.", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(PlaceState.visited.markerColor)
                            .roamCard()
                    } else {
                        NoteBox(text: $text, placeholder: "What went wrong?")
                            .focused($focused)
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { noteFrame = $0 }
                            .accessibilityIdentifier("bug-report-text")
                        attachmentSection
                        if let error { Text(error).font(.footnote).foregroundStyle(Roam.signal) }
                    }
                }
                .disabled(sending)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.top, Theme.Spacing.m)
                .padding(.bottom, Theme.Spacing.l)
            }
            .scrollDismissesKeyboard(.interactively)
            // Tapping anywhere off the note drops the cursor.
            .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { tap in
                if !noteFrame.contains(tap.location) { focused = false }
            })
            .background(Roam.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The title sits top left, level with the ×.
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { title }.sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { title }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .disabled(sending)
                        .accessibilityLabel("Close")
                        .tapID("bug-report-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !sent {
                    Button { Task { await send() } } label: {
                        Group {
                            if sending { ProgressView() } else { Text("Send").fontWeight(.semibold) }
                        }
                        .frame(maxWidth: .infinity, minHeight: Theme.minimumHitTarget)
                        // The whole bubble takes the tap, not just the word.
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    // Glass with a near-solid white wash, so it reads clearly over the screenshots behind it.
                    .floatingBubble(Capsule(), tint: Roam.paperRaised.opacity(0.85))
                    // Only off while sending: a tap on an empty report says why instead of doing nothing.
                    .disabled(sending)
                    .tapID("bug-report-send")
                    .padding(Theme.Spacing.l)
                }
            }
        }
        .interactiveDismissDisabled(sending)
        .roamSheetStyle()
        .task(id: pickerItems) { await load(pickerItems) }
        .onAppear { Log.action("bug_report.opened", ["screen": context.screen ?? ""]) }
        .screenIdentifier("bug-report", sheet: true)
    }

    /// What's attached, the full width of the page so it can be read, one under another with × on each; then a row
    /// to add another from Photos. Signed out, it's words only.
    @ViewBuilder private var attachmentSection: some View {
        ForEach(attachments) { attachment in preview(attachment) }
        if loadingAttachment { ProgressView().frame(maxWidth: .infinity) }
        if signedIn, attachments.count < Self.maxAttachments {
            picker {
                HStack(spacing: Theme.Spacing.m) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.headline)
                        .foregroundStyle(Roam.ink)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Roam.fill))
                    Text(attachments.isEmpty ? "Add screenshots or recordings" : "Add another")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Roam.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "plus").font(.subheadline.weight(.semibold)).foregroundStyle(Roam.inkMuted)
                }
                .roamCard(padding: Theme.Spacing.m)
                .contentShape(Rectangle())
            }
        }
    }

    private func picker<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        PhotosPicker(selection: $pickerItems, maxSelectionCount: Self.maxAttachments - attachments.count,
                     matching: .any(of: [.screenshots, .screenRecordings, .images, .videos])) { label() }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bug-report-photos")
    }

    /// A screenshot (or a recording's first frame) the full width of the page at its own shape, with × to remove it.
    private func preview(_ attachment: Attachment) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let image = attachment.preview
        let ratio = image.map { $0.size.width / max($0.size.height, 1) } ?? 0.46
        return ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Roam.fill
            }
            if attachment.isRecording {
                Image(systemName: "play.fill").font(.title2).foregroundStyle(.white)
                    .frame(width: 52, height: 52).background(Circle().fill(.black.opacity(0.45)))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(ratio, contentMode: .fit)
        .clipShape(shape)
        .overlay(shape.stroke(Roam.ink.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
        .overlay(alignment: .topTrailing) {
            Button { attachments.removeAll { $0.id == attachment.id } } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Roam.ink)
                    .frame(width: 30, height: 30)
                    .floatingBubble(Circle())
            }
            .buttonStyle(.plain)
            .padding(Theme.Spacing.s)
            .accessibilityLabel(attachment.isRecording ? "Remove recording" : "Remove screenshot")
            .tapID("bug-report-remove-attachment")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(attachment.isRecording ? "Screen recording" : "Screenshot")
    }

    // MARK: Attachments

    private func load(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        loadingAttachment = true
        defer { loadingAttachment = false; pickerItems = [] }
        error = nil
        for item in items where attachments.count < Self.maxAttachments {
            do {
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let movie = try await item.loadTransferable(type: PickedMovie.self) else { continue }
                    attachments.append(Attachment(content: .recording(movie.url, thumbnail: await Self.thumbnail(movie.url))))
                } else if let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    attachments.append(Attachment(content: .screenshot(image)))
                }
            } catch {
                self.error = "Couldn't open one of those. Try another."
                Log.error("bug_report.attachment", error)
            }
        }
    }

    private static func thumbnail(_ url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        guard let image = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: Sending

    private func send() async {
        guard !sending else { return }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Say what went wrong first."
            focused = true
            Log.action("bug_report.send_empty")
            return
        }
        if loadingAttachment {
            error = "Wait for the attachment to finish loading."
            return
        }
        sending = true
        error = nil
        defer { sending = false }
        do {
            let files = try await prepareAttachments()
            // The steps so far go up first, so the report lines up with them.
            await Telemetry.shared.flush()
            let telemetry = Telemetry.shared
            let draft = BugReportDraft(description: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                       screen: context.screen, attachments: files,
                                       sessionID: telemetry.session.id, lastSeq: telemetry.lastSeq, device: telemetry.session)
            let id = try await services.bugReports.submitBugReport(draft)
            Log.action("bug_report.sent", ["report": id.uuidString, "attachments": "\(files.count)"])
            sent = true
            try? await Task.sleep(for: .seconds(1.2))
            dismiss()
        } catch {
            self.error = session.handle(error)
            Log.error("bug_report.send", error)
        }
    }

    private func prepareAttachments() async throws -> [BugReportDraft.Attachment] {
        guard signedIn else { return [] }
        var files: [BugReportDraft.Attachment] = []
        for attachment in attachments {
            switch attachment.content {
            case .screenshot(let image):
                guard let data = Self.jpeg(image) else { continue }
                files.append(.init(kind: .screenshot, data: data, contentType: "image/jpeg", fileExtension: "jpg"))
            case .recording(let url, _):
                files.append(.init(kind: .recording, data: try await Self.compressedMovie(url), contentType: "video/mp4", fileExtension: "mp4"))
            }
        }
        return files
    }

    /// At most 1600 px on the long side, which keeps text readable and the file well under a megabyte.
    private static func jpeg(_ image: UIImage) -> Data? {
        let longest = max(image.size.width * image.scale, image.size.height * image.scale)
        let scale = min(1, 1_600 / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.7)
    }

    /// Re-encodes a recording at 720p so a minute of screen fits in a few megabytes.
    private static func compressedMovie(_ url: URL) async throws -> Data {
        let asset = AVURLAsset(url: url)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            return try Data(contentsOf: url)
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("bug-\(UUID().uuidString).mp4")
        try await export.export(to: output, as: .mp4)
        defer { try? FileManager.default.removeItem(at: output) }
        let data = try Data(contentsOf: output)
        if data.count > 50_000_000 { throw RoamError.validation("That recording is too long. Try one under a few minutes.") }
        return data
    }
}

/// A video from Photos, copied somewhere the app can read it.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in SentTransferredFile(movie.url) } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
