//
//  HomeView.swift
//  ImageCircle
//
//  Home feed with stories tray, post list, and Twitter-style feed filter.
//

import SwiftUI

struct HomeView: View {
    @Binding var refreshTrigger: UUID
    
    @State private var posts: [Post] = []
    @State private var storyGroups: [StoryGroup] = []
    @State private var selectedGroupIndex: Int = 0
    @State private var selectedStoryIndex: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showStoryViewer = false
    @State private var showCamera = false
    @State private var selectedPostForComments: Post?
    @State private var feedFilter: FeedFilter = .mixed
    @State private var profileUser: User? = nil
    
    /// Posts filtered by the selected segment (client-side until backend supports ?type=).
    private var filteredPosts: [Post] {
        posts.filter { feedFilter.includes($0) }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    StoriesTrayView(
                        groups: storyGroups,
                        onStorySelected: { groupIndex, storyIndex in
                            selectedGroupIndex = groupIndex
                            selectedStoryIndex = storyIndex
                            showStoryViewer = true
                        },
                        onAddStoryTapped: { showCamera = true },
                        showAddButton: true
                    )
                    
                    Divider()
                    
                    feedFilterPicker
                    
                    if filteredPosts.isEmpty && !isLoading {
                        emptyState
                    } else {
                        ForEach(filteredPosts) { post in
                            PostCardView(
                                post: post,
                                onLikeChanged: { refreshTrigger = UUID() },
                                onCommentTapped: { selectedPostForComments = post },
                                onDelete: { refreshTrigger = UUID() },
                                onProfileTapped: { profileUser = $0 }
                            )
                            .id(post.id)
                        }
                    }
                }
            }
            .refreshable {
                await loadFeed()
                await loadStories()
            }
            .navigationTitle("ImageCircle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { refreshTrigger = UUID() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .sheet(item: $selectedPostForComments) { post in
                CommentsSheetView(post: post)
            }
            .fullScreenCover(isPresented: $showStoryViewer) {
                if !storyGroups.isEmpty,
                   storyGroups.indices.contains(selectedGroupIndex),
                   storyGroups[selectedGroupIndex].stories.indices.contains(selectedStoryIndex) {
                    StoryViewerView(
                        groups: storyGroups,
                        groupIndex: selectedGroupIndex,
                        storyIndex: selectedStoryIndex,
                        isPresented: $showStoryViewer,
                        onStoriesChanged: { Task { await loadStories() } }
                    )
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView(onFinished: { shouldRefresh in
                    showCamera = false
                    if shouldRefresh {
                        Task {
                            await loadFeed()
                            await loadStories()
                        }
                    }
                })
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .task(id: refreshTrigger) {
                await loadFeed()
                guard !Task.isCancelled else { return }
                await loadStories()
            }
            .navigationDestination(item: $profileUser) { user in
                ProfileView(user: user)
            }
        }
    }
    
    private var feedFilterPicker: some View {
        Picker("Feed", selection: $feedFilter) {
            ForEach(FeedFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)
            Image(systemName: feedFilter == .text ? "text.bubble" : "photo.on.rectangle.angled")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)
                .foregroundStyle(.pink.opacity(0.6))
            Text(emptyStateMessage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var emptyStateMessage: String {
        switch feedFilter {
        case .mixed:
            return "No posts yet.\nBe the first to share!"
        case .images:
            return "No image posts yet."
        case .text:
            return "No text posts yet."
        }
    }
    
    private func loadFeed() async {
        isLoading = true
        do {
            posts = try await APIClient.shared.fetchFeed()
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? APIError) == .cancelled {
                // Suppress cancellation alerts from SwiftUI lifecycle.
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
        isLoading = false
    }
    
    private func loadStories() async {
        do {
            async let otherStories = APIClient.shared.fetchStories()
            let loadedOthers = try await otherStories
            
            var allStories = loadedOthers
            if let currentUserID = AuthManager.shared.currentUser?.id {
                async let myStories = APIClient.shared.fetchStories(userID: currentUserID)
                let loadedMine = try await myStories
                allStories = loadedMine + loadedOthers.filter { $0.user.id != currentUserID }
            }
            
            var groups = allStories.groupedByUser()
            if let currentUserID = AuthManager.shared.currentUser?.id,
               let ownIndex = groups.firstIndex(where: { $0.user.id == currentUserID }) {
                let ownGroup = groups.remove(at: ownIndex)
                groups.insert(ownGroup, at: 0)
            }
            storyGroups = groups
        } catch {
            // Stories failure is non-fatal; don't alert.
        }
    }
}

// MARK: - Comments Sheet

struct CommentsSheetView: View {
    let post: Post
    @State private var comments: [Comment] = []
    @State private var newComment: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var profileUser: User? = nil
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(comments) { comment in
                    HStack(alignment: .top, spacing: 12) {
                        Button(action: { profileUser = comment.user }) {
                            HStack(alignment: .top, spacing: 12) {
                                AvatarImage(user: comment.user, size: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(comment.user.username)
                                        .font(.subheadline.weight(.semibold))
                                    Text(comment.text)
                                        .font(.subheadline)
                                    Text(comment.createdAt.relativeTimeFromISO())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        if AuthManager.shared.canDelete(contentUserID: comment.user.id) {
                            Button(role: .destructive) {
                                deleteComment(comment)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                
                HStack(spacing: 12) {
                    TextField("Add a comment...", text: $newComment, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    
                    Button(action: submitComment) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(newComment.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.pink))
                    }
                    .disabled(newComment.isEmpty)
                    .accessibilityLabel("Send comment")
                }
                .padding()
                .background(Color(.systemBackground))
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadComments()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not load comments.")
            }
            .navigationDestination(item: $profileUser) { user in
                ProfileView(user: user)
            }
        }
    }
    
    private func loadComments() async {
        isLoading = true
        do {
            comments = try await APIClient.shared.fetchComments(postID: post.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
        }
        isLoading = false
    }
    
    private func deleteComment(_ comment: Comment) {
        Task {
            do {
                try await APIClient.shared.deleteComment(id: comment.id)
                await MainActor.run {
                    comments.removeAll { $0.id == comment.id }
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    private func submitComment() {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        newComment = ""
        Task {
            do {
                let comment = try await APIClient.shared.postComment(postID: post.id, text: text)
                comments.append(comment)
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
