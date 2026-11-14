import SwiftUI

/// A friend's log as its own page, from its comment button: the log as it is on the Friends tab, then the comments as
/// plain rows (their picture, name and how long ago, then what they said), and a round field pinned at the bottom with
/// your picture and a send arrow. Long-press a comment to delete yours or report someone else's.
struct LogPostView: View {
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

    private func composer(_ model: ActivityDetailModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let error = model.postError {
                Text(model.pending != nil ? "\(error) Send tries again." : error)
                    .font(.footnote).foregroundStyle(Theme.destructive)
                    .accessibilityIdentifier("comment-error")
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                if let me = session.profile?.summary { AvatarView(member: me, size: 36) }
                HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                    TextField("Add a comment", text: $model.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .disabled(model.isPosting)
                        .padding(.vertical, 10)
                        .accessibilityIdentifier("comment-field")
                    Button {
                        Task { if await model.post() { composerFocused = false } }
                    } label: {
                        Group {
                            if model.isPosting { ProgressView() } else { Image(systemName: "arrow.up").font(.subheadline.weight(.bold)) }
                        }
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(model.canPost ? Roam.ink : Roam.inkFaint))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canPost)
                    .padding(.bottom, 5)
                    .accessibilityLabel(model.pending != nil ? "Retry sending comment" : "Send comment")
                    .accessibilityIdentifier("comment-send")
                }
                .padding(.leading, Theme.Spacing.m)
                .padding(.trailing, 5)
                .background(Capsule().fill(Roam.fill))
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.s)
        .padding(.bottom, Theme.Spacing.s)
        .background(.bar)
    }
}
