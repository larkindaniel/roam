import SwiftUI

/// S23: full post, likes and flat comments with a composer pinned above the keyboard.
struct ActivityDetailView: View {
    let activityID: UUID

    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(ActivityChangeStore.self) private var changes
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityDetailModel?
    @State private var confirmingRemoval = false
    @State private var commentToDelete: Comment?
    @State private var reportTarget: ReportTarget?
    @FocusState private var composerFocused: Bool

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background(Theme.groupedCanvas)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let item = model?.item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if item.isOwn {
                            Button(role: .destructive) { confirmingRemoval = true } label: { Label("Remove post", systemImage: "trash") }
                                .accessibilityIdentifier("activity-remove")
                        } else {
                            Button { reportTarget = .activity(item.id) } label: { Label("Report post", systemImage: "flag") }
                                .accessibilityIdentifier("activity-report")
                        }
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
                    .accessibilityIdentifier("activity-overflow")
                }
            }
        }
        .confirmationDialog("Remove this post?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove post", role: .destructive) {
                Task {
                    if await model?.removePost() == true {
                        changes.publishRemoval(activityID)
                        dismiss()
                    }
                }
            }
            .accessibilityIdentifier("confirm-remove-post")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this post, its likes and comments are removed. Your ranking and visit stay. To remove those, use the place's own actions.")
        }
        .confirmationDialog("Delete your comment?", isPresented: Binding(get: { commentToDelete != nil }, set: { if !$0 { commentToDelete = nil } }),
                            titleVisibility: .visible, presenting: commentToDelete) { comment in
            Button("Delete comment", role: .destructive) { Task { await model?.deleteComment(comment); publish() } }
                .accessibilityIdentifier("confirm-delete-comment")
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $reportTarget) { target in
            ReportSheet(target: target, title: target.kind == "comment" ? "Report comment" : "Report post")
        }
        .task {
            if model == nil { model = ActivityDetailModel(activityID: activityID, service: services.feed) }
            await model?.load()
            publish()
        }
        .onChange(of: model?.authError) { _, error in if let error { _ = session.handle(error) } }
        .screenIdentifier("activity-detail")
    }

    private func publish() {
        if let item = model?.item { changes.publish(item) }
        if model?.isUnavailable == true { changes.publishRemoval(activityID) }
    }

    @ViewBuilder private func content(_ model: ActivityDetailModel) -> some View {
        if model.isUnavailable {
            ScrollView {
                VStack {
                    EmptyStateView(systemImage: "eye.slash", title: "This post isn't available",
                                   message: "It was removed, or you can no longer see it.",
                                   primaryTitle: "Go back", primaryAction: { dismiss() })
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity-unavailable")
                .padding(.top, Theme.Spacing.xxl)
            }
        } else if let item = model.item {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                        ActivityCardView(item: item, compact: false,
                                         onOpenPhotos: item.visitID.map { visitID in { router.push(.gallery(experienceID: item.experience.id, visitID: visitID)) } })
                        Button { router.push(.experience(item.experience.id)) } label: {
                            Label("Open \(item.experience.name)", systemImage: "mappin.circle").frame(minHeight: Theme.minimumHitTarget)
                        }
                        .accessibilityIdentifier("activity-open-experience")
                        HStack(spacing: Theme.Spacing.l) {
                            LikeButton(liked: item.likedByViewer, count: item.likeCount, pending: model.likePending) {
                                Task { await model.setLike(!item.likedByViewer); publish() }
                            }
                            Label(item.commentCount == 1 ? "1 comment" : "\(item.commentCount) comments", systemImage: "bubble.left")
                                .font(.subheadline).foregroundStyle(Theme.secondaryText)
                                .accessibilityIdentifier("activity-comment-count")
                        }
                    }
                    .roamCard()
                    if let error = model.actionError {
                        InlineRetryView(message: error, retryTitle: "Reload") { Task { await model.load() } }
                    }
                    comments(model)
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
            }
            .refreshable { await model.load(); publish() }
            .safeAreaInset(edge: .bottom) { composer(model) }
        } else if let error = model.loadError {
            ScrollView {
                EmptyStateView(systemImage: "wifi.exclamationmark", title: "Couldn't load this post", message: error,
                               primaryTitle: "Try again", primaryAction: { Task { await model.load() } })
                    .padding(.top, Theme.Spacing.xxl)
            }
        } else {
            ScrollView { SkeletonList(rows: 4).padding() }
        }
    }

    private func comments(_ model: ActivityDetailModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Comments").font(.roamTitle(.title3)).accessibilityAddTraits(.isHeader)
            if let error = model.commentsError {
                InlineRetryView(message: error) { Task { await model.load() } }
            }
            if model.commentsLoaded && model.comments.isEmpty {
                Text("No comments yet. Be the first to say something kind.").font(.subheadline).foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("comments-empty")
            }
            ForEach(model.comments) { comment in
                CommentRow(comment: comment, deleting: model.deletingCommentID == comment.id,
                           onDelete: { commentToDelete = comment },
                           onReport: { reportTarget = .comment(comment.id) })
                Divider()
            }
            if model.commentsCursor != nil {
                Button(model.loadingMoreComments ? "Loading…" : "Show more comments") { Task { await model.loadMoreComments() } }
                    .disabled(model.loadingMoreComments)
                    .frame(minHeight: Theme.minimumHitTarget)
                    .accessibilityIdentifier("comments-more")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roamCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity-comments")
    }

    private func composer(_ model: ActivityDetailModel) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let error = model.postError {
                Text(model.pending != nil ? "\(error) Your comment is kept; Send retries it." : error)
                    .font(.footnote).foregroundStyle(Theme.disliked)
                    .accessibilityIdentifier("comment-error")
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.s) {
                TextField("Add a comment", text: $model.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($composerFocused)
                    .disabled(model.isPosting)
                    .accessibilityIdentifier("comment-field")
                Button {
                    Task { if await model.post() { composerFocused = false; publish() } }
                } label: {
                    if model.isPosting { ProgressView().frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget) }
                    else { Image(systemName: "paperplane.fill").frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget) }
                }
                .disabled(!model.canPost)
                .accessibilityLabel(model.pending != nil ? "Retry sending comment" : "Send comment")
                .accessibilityIdentifier("comment-send")
            }
            if Validation.characterCount(model.draft) > 1_800 {
                Text("\(Validation.characterCount(model.draft)) / 2,000 characters").font(.caption)
                    .foregroundStyle(Validation.characterCount(model.draft) > 2_000 ? Theme.disliked : .secondary)
            }
        }
        .padding(Theme.Spacing.m)
        .background(.bar)
    }
}

struct CommentRow: View {
    let comment: Comment
    var deleting = false
    let onDelete: () -> Void
    let onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            AvatarView(member: comment.author, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(comment.author.displayName).font(.subheadline.weight(.semibold))
                    Text(comment.createdAt.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(Theme.secondaryText)
                }
                Text(comment.body).font(.body).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Menu {
                if comment.isOwn {
                    Button(role: .destructive, action: onDelete) { Label("Delete comment", systemImage: "trash") }
                } else {
                    Button(action: onReport) { Label("Report comment", systemImage: "flag") }
                }
            } label: {
                if deleting { ProgressView() } else { Image(systemName: "ellipsis") }
            }
            .frame(width: Theme.minimumHitTarget, height: Theme.minimumHitTarget)
            .accessibilityLabel("More for \(comment.author.displayName)'s comment")
            .accessibilityIdentifier("comment-overflow-\(comment.id.uuidString)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment-\(comment.id.uuidString)")
    }
}
