//
//  PostCardView.swift
//  ImageCircle
//
//  Single feed post card with like, comment, and caption.
//

import SwiftUI
import Kingfisher

struct PostCardView: View {
    let post: Post
    let onLikeChanged: () -> Void
    let onCommentTapped: () -> Void
    let onDelete: () -> Void
    
    @State private var postState: Post
    @State private var showHeartOverlay = false
    @State private var heartScale: CGFloat = 0.5
    @State private var isLiking = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    
    init(post: Post, onLikeChanged: @escaping () -> Void, onCommentTapped: @escaping () -> Void, onDelete: @escaping () -> Void = {}) {
        self.post = post
        self._postState = State(initialValue: post)
        self.onLikeChanged = onLikeChanged
        self.onCommentTapped = onCommentTapped
        self.onDelete = onDelete
    }
    
    private var canDelete: Bool {
        AuthManager.shared.canDelete(contentUserID: postState.user.id)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if postState.isTextOnly {
                textContentSection
            } else {
                imageSection
            }
            actionBar
            infoSection
            Divider()
        }
        .background(Color(.systemBackground))
        .onChange(of: post) { _, newPost in
            postState = newPost
        }
    }
    
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatarView(for: postState.user)
                .frame(width: 40, height: 40)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(postState.user.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("@\(postState.user.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(postState.createdAt.relativeTimeFromISO())
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if canDelete {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .alert("Delete Post?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deletePost()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }
    
    private var imageSection: some View {
        ZStack {
            if let mediaFilename = postState.mediaFilename,
               let url = MediaURL.url(userID: postState.user.id, filename: mediaFilename) {
                KFImage(url)
                    .resizable()
                    .placeholder { Color(.systemGray5) }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 500)
                    .clipped()
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleLike()
                        animateHeart()
                    }
            }
            
            if showHeartOverlay {
                Image(systemName: "heart.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .scaleEffect(heartScale)
                    .opacity(showHeartOverlay ? 1 : 0)
            }
        }
    }
    
    private var textContentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let caption = postState.caption, !caption.isEmpty {
                Text(caption)
                    .font(.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        toggleLike()
                    }
            }
        }
    }
    
    private var actionBar: some View {
        HStack(spacing: 16) {
            Button(action: toggleLike) {
                Image(systemName: postState.hasLiked ? "heart.fill" : "heart")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(postState.hasLiked ? .pink : .primary)
            }
            .disabled(isLiking)
            .accessibilityLabel(postState.hasLiked ? "Unlike" : "Like")
            
            Button(action: onCommentTapped) {
                Image(systemName: "bubble.right")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Comment")
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(postState.likesCount) likes")
                .font(.subheadline.weight(.semibold))
            
            if !postState.isTextOnly, let caption = postState.caption, !caption.isEmpty {
                HStack(spacing: 4) {
                    Text(postState.user.username)
                        .font(.subheadline.weight(.semibold))
                    Text(caption)
                        .font(.subheadline)
                }
                .lineLimit(2)
            }
            
            if postState.commentsCount > 0 {
                Button(action: onCommentTapped) {
                    Text("View all \(postState.commentsCount) comments")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    private func avatarView(for user: User) -> some View {
        Group {
            if let filename = user.avatarFilename,
               !filename.isEmpty,
               let url = MediaURL.url(userID: user.id, filename: filename) {
                KFImage(url)
                    .resizable()
                    .placeholder { placeholderAvatar(name: user.username) }
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderAvatar(name: user.username)
            }
        }
    }
    
    private func toggleLike() {
        guard !isLiking else { return }
        isLiking = true
        
        // Optimistic update
        let currentlyLiked = postState.hasLiked
        postState = Post(
            id: postState.id,
            user: postState.user,
            caption: postState.caption,
            mediaFilename: postState.mediaFilename,
            thumbnailFilename: postState.thumbnailFilename,
            createdAt: postState.createdAt,
            likesCount: postState.likesCount + (currentlyLiked ? -1 : 1),
            commentsCount: postState.commentsCount,
            hasLiked: !currentlyLiked
        )
        
        Task {
            do {
                let result = try await APIClient.shared.toggleLike(id: postState.id)
                postState = Post(
                    id: postState.id,
                    user: postState.user,
                    caption: postState.caption,
                    mediaFilename: postState.mediaFilename,
                    thumbnailFilename: postState.thumbnailFilename,
                    createdAt: postState.createdAt,
                    likesCount: result.likeCount,
                    commentsCount: postState.commentsCount,
                    hasLiked: result.liked
                )
                onLikeChanged()
            } catch {
                // Revert on failure
                postState = post
            }
            isLiking = false
        }
    }
    
    private func deletePost() {
        guard canDelete else { return }
        isDeleting = true
        Task {
            do {
                try await APIClient.shared.deletePost(id: postState.id)
                await MainActor.run {
                    isDeleting = false
                    onDelete()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
    
    private func animateHeart() {
        withAnimation(.easeOut(duration: 0.15)) {
            showHeartOverlay = true
            heartScale = 1.2
        }
        withAnimation(.easeIn(duration: 0.15).delay(0.15)) {
            heartScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.5)) {
            showHeartOverlay = false
            heartScale = 0.5
        }
    }
}
