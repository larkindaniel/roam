import SwiftUI

/// A friend's log as its own page, from its comment button: the log as it is on the Friends tab, then the comments as
/// plain rows (their picture, name and how long ago, then what they said), and a round white field pinned at the bottom
/// with your picture (it slides away once the comment wraps) and a send arrow. Long-press a comment to delete yours or report someone else's.
struct LogPostView: View {
    /// The comment field's height on one line, matching your picture beside it.
    private static let rowHeight: CGFloat = 46
    private static let sendSize: CGFloat = 32
    /// The gap below and to the right of the send circle.
    /// The gap below and to the right of the send circle: half the difference, so it's centred on one line.
    private static let sendInset: CGFloat = (rowHeight - sendSize) / 2

    let visitID: UUID
    /// Puts the cursor in the comment field as it opens.
    var focusComment = false

    @Environment(AppServices.self) private var services
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @Environment(AppRouter.self) private var router
    @State private var model: ActivityDetailModel?
    @State private var commentToDelete: Comment?
    @State private var reportTarget: ReportTarget?
    @FocusState private var composerFocused: Bool
    /// The comment wouldn't fit on one line beside your picture, so the picture steps aside.
    @State private var composerWraps = false
    /// The width of the whole comment row, for working out the text's room when the picture is showing.
    @State private var composerRowWidth: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if let model, let item = model.item {
                    ActivityCardView(item: item, compact: false, actions: AnyView(actions(model, item: item)),
                                     onDoubleTap: { if !item.likedByViewer { Task { await model.setLike(true) } } })
                } else if model?.isUnavailable == true {
                    EmptyStateView(systemImage: "eye.slash", title: "This isn't available",
                                   message: "It was removed, or you can no longer see it.")
                } else {
                    SkeletonCards(count: 1)
                }
                if let model { list(model) }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
        }
        .scrollDismissesKeyboard(.interactively)
        // Tapping anywhere off the field puts the keyboard away (buttons on the page still work).
        .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
        .safeAreaInset(edge: .bottom, spacing: 0) { if let model, model.item != nil { composer(model) } }
        .background(Roam.paper)
        // The comment field sits at the bottom, where the tab bar would be.
        .roamTabBar(hidden: true)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if model == nil { model = ActivityDetailModel(activityID: visitID, service: services.feed) }
            await model?.load()
            if focusComment { composerFocused = true }
        }
        .onDisappear { if let item = model?.item { changes.publish(item) } }
        .confirmationDialog("Delete your comment?", isPresented: Binding(get: { commentToDelete != nil }, set: { if !$0 { commentToDelete = nil } }),
                            titleVisibility: .visible, presenting: commentToDelete) { comment in
            Button("Delete", role: .destructive) { Task { await model?.deleteComment(comment) } }
        }
        .sheet(item: $reportTarget) { ReportSheet(target: $0, title: "Report comment") }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("log-post")
    }

    /// Like and comment, as on the Friends tab; comment puts the cursor in the field.
    private func actions(_ model: ActivityDetailModel, item: ActivityItem) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: model.likePending, tint: .white) {
                Task { await model.setLike(!item.likedByViewer) }
            }
            Button { composerFocused = true } label: {
                HStack(spacing: 4) { Image(systemName: "bubble.right"); Text("\(item.commentCount)") }
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(minWidth: Theme.minimumHitTarget, minHeight: Theme.minimumHitTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Comment")
        }
    }

    @ViewBuilder private func list(_ model: ActivityDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if model.item != nil { Text("Comments").font(.headline).accessibilityAddTraits(.isHeader) }
            if let error = model.commentsError ?? model.loadError {
                InlineRetryView(message: error) { Task { await model.load() } }
            }
            if model.commentsLoaded && model.comments.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("No comments yet").font(.headline)
                    Text("Start the conversation.").font(.subheadline).foregroundStyle(Roam.inkMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.l)
                .accessibilityIdentifier("comments-empty")
            } else if !model.commentsLoaded {
                SkeletonResults(kind: .people, rows: 3)
            }
            ForEach(model.comments) { comment in
                row(comment, deleting: model.deletingCommentID == comment.id)
            }
            if model.commentsCursor != nil {
                Button(model.loadingMoreComments ? "Loading…" : "Show more") { Task { await model.loadMoreComments() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Roam.inkMuted)
                    .disabled(model.loadingMoreComments)
                    .frame(minHeight: Theme.minimumHitTarget)
            }
        }
    }

    private func row(_ comment: Comment, deleting: Bool) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            AvatarView(member: comment.author, size: 36)
                .onTapGesture { router.push(.member(comment.author.id)) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.s) {
                    Text(comment.author.displayName).font(.subheadline.weight(.semibold))
                    Text(comment.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Roam.inkMuted)
                }
                Text(comment.body).font(.body).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if deleting { ProgressView() }
        }
        .contentShape(Rectangle())
        .contextMenu {
            if comment.isOwn {
                Button(role: .destructive) { commentToDelete = comment } label: { Label("Delete", systemImage: "trash") }
            } else {
                Button { reportTarget = .comment(comment.id) } label: { Label("Report", systemImage: "flag") }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("comment-\(comment.id.uuidString)")
    }

    /// The text's width when your picture sits beside the field: the row less the picture, the gaps and the send circle.
    private var narrowTextWidth: CGFloat {
        composerRowWidth - Self.rowHeight - Theme.Spacing.s - Theme.Spacing.m - Theme.Spacing.xs - Self.sendSize - Self.sendInset
    }

    private func composer(_ model: ActivityDetailModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let error = model.postError {
                Text(model.pending != nil ? "\(error) Send tries again." : error)
                    .font(.footnote).foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("comment-error")
            }
            // Your picture and the field, the same height and centred on each other. Once the comment won't fit on one
            // line beside the picture, the picture slides away so the field takes the whole width; shorten it to one line
            // again and the picture comes back. A pill on one line, a rounded box beyond.
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                if !composerWraps, let me = session.profile?.summary {
                    AvatarView(member: me, size: Self.rowHeight)
                        // A thin white ring sets it apart from the comments behind.
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 1)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                // The send circle stays centred top to bottom, rising as the comment grows.
                HStack(alignment: .center, spacing: Theme.Spacing.xs) {
                    TextField("Add a comment", text: $model.draft, axis: .vertical)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .disabled(model.isPosting)
                        // Less than the field's height, so one line is exactly `rowHeight` tall and the circle's maths holds.
                        .padding(.vertical, 10)
                        .frame(minHeight: Self.rowHeight)
                        .accessibilityIdentifier("comment-field")
                    Button {
                        Task { if await model.post() { composerFocused = false } }
                    } label: {
                        Group {
                            if model.isPosting { ProgressView() } else { Image(systemName: "arrow.up").font(.footnote.weight(.bold)) }
                        }
                        .foregroundStyle(.white)
                        .frame(width: Self.sendSize, height: Self.sendSize)
                        .background(Circle().fill(model.canPost ? Roam.ink : Roam.inkFaint))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canPost)
                    .accessibilityLabel(model.pending != nil ? "Retry sending comment" : "Send comment")
                    .accessibilityIdentifier("comment-send")
                }
                .padding(.leading, Theme.Spacing.m)
                // The same gap to its right as below it.
                .padding(.trailing, Self.sendInset)
                // Floating Liquid Glass over the comments, which scroll on underneath.
                // A generous radius: one line reads as a full pill; longer, a rounded box.
                // Solid white, lifted off the comments by a soft shadow.
                .background(RoundedRectangle(cornerRadius: 26, style: .circular).fill(Roam.paperRaised))
                .shadow(color: .black.opacity(0.12), radius: 12, y: 2)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { composerRowWidth = $0 }
        // Whether the comment fits on one line beside your picture, judged on its natural one-line width, so the picture
        // steps aside just before the text would reach the edge (the field never wraps beside it first).
        .background(alignment: .topLeading) {
            Text(model.draft.isEmpty ? " " : model.draft)
                .font(.body)
                .lineLimit(1)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: Bool.self) { $0.size.width > narrowTextWidth - 6 || model.draft.contains("\n") } action: { wraps in
                    withAnimation(.easeOut(duration: 0.2)) { composerWraps = wraps }
                }
        }
        // No band behind it; inset from the screen's curved corners, low on the screen.
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.top, Theme.Spacing.s)
    }
}
