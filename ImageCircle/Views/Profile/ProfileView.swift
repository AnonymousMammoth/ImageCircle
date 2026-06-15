//
//  ProfileView.swift
//  ImageCircle
//
//  User profile with avatar, stats, filterable post grid, and avatar upload.
//

import SwiftUI
import Kingfisher
import PhotosUI

struct ProfileView: View {
    let user: User?
    
    @StateObject private var auth = AuthManager.shared
    @State private var posts: [Post] = []
    @State private var selectedPost: Post?
    @State private var commentPost: Post?
    @State private var showSettings = false
    @State private var isLoading = false
    @State private var filter: FeedFilter = .mixed
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var loadErrorMessage: String?
    @State private var showLoadError = false
    @State private var avatarErrorMessage: String?
    @State private var showAvatarError = false
    @State private var refreshTrigger = UUID()
    @State private var profileUser: User? = nil
    
    private var isCurrentUser: Bool {
        guard let user = user, let current = auth.currentUser else { return true }
        return user.id == current.id
    }
    
    private var displayUser: User? {
        user ?? auth.currentUser
    }
    
    private var filteredPosts: [Post] {
        posts.filter { filter.includes($0) }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileHeader
                statsRow
                filterPicker
                Divider()
                postGrid
            }
        }
        .navigationTitle(displayUser?.username ?? "Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isCurrentUser {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $selectedPost) { post in
            ProfilePostDetailView(post: post, onDelete: { refreshTrigger = UUID() })
        }
        .sheet(item: $commentPost) { post in
            CommentsSheetView(post: post)
        }
        .refreshable {
            refreshTrigger = UUID()
        }
        .task(id: refreshTrigger) {
            await loadPosts()
        }
        .alert("Error", isPresented: $showLoadError, presenting: loadErrorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .alert("Avatar Error", isPresented: $showAvatarError, presenting: avatarErrorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .navigationDestination(item: $profileUser) { user in
            ProfileView(user: user)
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 12) {
            avatarView
            
            Text(displayUser?.username ?? "")
                .font(.title2.weight(.semibold))
            
            Text(displayUser?.displayName ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }
    
    private var avatarView: some View {
        ZStack(alignment: .bottomTrailing) {
            if let displayUser = displayUser {
                AvatarImage(user: displayUser, size: 80)
            } else {
                placeholderAvatar(name: "")
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            }
            
            if isCurrentUser {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .disabled(isUploadingAvatar)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    selectedPhotoItem = nil
                    Task { await uploadAvatar(from: newItem) }
                }
            }
        }
    }
    
    private var statsRow: some View {
        HStack {
            Spacer()
            VStack {
                Text("\(filteredPosts.count)")
                    .font(.headline.weight(.semibold))
                Text("posts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
    
    private var filterPicker: some View {
        Picker("Filter", selection: $filter) {
            ForEach(FeedFilter.allCases) { filterCase in
                Text(filterCase.rawValue).tag(filterCase)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }
    
    private var postGrid: some View {
        Group {
            if filter == .text {
                textFeed
            } else {
                imageGrid
            }
        }
    }
    
    private var textFeed: some View {
        LazyVStack(spacing: 0) {
            ForEach(filteredPosts) { post in
                PostCardView(
                    post: post,
                    onLikeChanged: { refreshTrigger = UUID() },
                    onCommentTapped: { commentPost = post },
                    onDelete: { refreshTrigger = UUID() },
                    onProfileTapped: { profileUser = $0 }
                )
                .id(post.id)
            }
        }
    }
    
    private var imageGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(filteredPosts) { post in
                Button(action: { selectedPost = post }) {
                    if post.isTextOnly {
                        textPostCell(for: post)
                    } else if let filename = effectiveThumbnailFilename(for: post),
                              let url = MediaURL.url(userID: post.user.id, filename: filename) {
                        imageGridCell(for: post, url: url)
                    } else {
                        Color(.systemGray4)
                            .frame(maxWidth: .infinity, minHeight: 0)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .buttonStyle(.plain)
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("View post \(post.id)")
            }
        }
    }
    
    private func imageGridCell(for post: Post, url: URL) -> some View {
        GeometryReader { geo in
            KFImage(url)
                .resizable()
                .placeholder { Color(.systemGray4) }
                .onFailure { error in
                    print("[KFImage] Failed to load post \(post.id) at \(url): \(error)")
                }
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.width)
                .clipped()
        }
    }
    
    private func effectiveThumbnailFilename(for post: Post) -> String? {
        if let thumbnail = post.thumbnailFilename, !thumbnail.isEmpty {
            print("[Profile] post \(post.id) using thumbnail: \(thumbnail)")
            return thumbnail
        }
        if let media = post.mediaFilename, !media.isEmpty {
            print("[Profile] post \(post.id) falling back to media: \(media)")
            return media
        }
        print("[Profile] post \(post.id) has no media/thumbnail")
        return nil
    }
    
    private func textPostCell(for post: Post) -> some View {
        ZStack {
            Color(.systemGray6)
            
            VStack(spacing: 4) {
                Image(systemName: "text.quote")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                
                if let caption = post.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func loadPosts() async {
        guard let displayUser = displayUser else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Try the dedicated user-posts endpoint first (added in newer backends).
            posts = try await APIClient.shared.fetchUserPosts(userID: displayUser.id)
            print("[Profile] loaded \(posts.count) posts")
            for post in posts {
                print("  post \(post.id): isTextOnly=\(post.isTextOnly), media=\(post.mediaFilename ?? "-"), thumb=\(post.thumbnailFilename ?? "-")")
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? APIError) == .cancelled {
                return
            }
            // Fall back to filtering the global feed for older backends.
            do {
                let feed = try await APIClient.shared.fetchFeed()
                posts = feed.filter { $0.user.id == displayUser.id }
            } catch {
                posts = []
                if Task.isCancelled || error is CancellationError || (error as? APIError) == .cancelled {
                    return
                }
                loadErrorMessage = error.localizedDescription
                showLoadError = true
            }
        }
    }
    
    private func uploadAvatar(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                avatarErrorMessage = "Could not load selected photo."
                showAvatarError = true
                return
            }
            
            // Compress/resize off the main actor to avoid blocking UI.
            let compressed = try await Task.detached(priority: .userInitiated) {
                compressImageForAvatar(data)
            }.value
            
            guard !Task.isCancelled else { return }
            
            let updatedUser = try await APIClient.shared.updateAvatar(imageData: compressed)
            
            guard !Task.isCancelled else { return }
            
            // Clear cached avatar so the new one is fetched immediately.
            if let oldFilename = auth.currentUser?.avatarFilename,
               !oldFilename.isEmpty,
               let oldURL = MediaURL.url(userID: updatedUser.id, filename: oldFilename) {
                KingfisherManager.shared.cache.removeImage(forKey: oldURL.absoluteString)
            }
            
            auth.currentUser = updatedUser
        } catch is CancellationError {
            // Ignore cancellation; the request may have already completed on the server.
        } catch let error as APIError where error == .cancelled {
            // Ignore cancellation.
        } catch {
            avatarErrorMessage = error.localizedDescription
            showAvatarError = true
        }
    }
    
    private func compressImageForAvatar(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSize: CGFloat = 1024
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }
}

// MARK: - Profile Post Detail View

struct ProfilePostDetailView: View {
    let post: Post
    let onDelete: () -> Void
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @Environment(\.dismiss) private var dismiss
    
    private var canDelete: Bool {
        AuthManager.shared.canDelete(contentUserID: post.user.id)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if post.isTextOnly {
                        textContentSection
                    } else {
                        imageSection
                    }
                    
                    if let caption = post.caption, !caption.isEmpty, !post.isTextOnly {
                        Text(caption)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    
                    HStack(spacing: 16) {
                        Label("\(post.likesCount)", systemImage: "heart")
                        Label("\(post.commentsCount)", systemImage: "bubble.right")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if canDelete {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .alert("Delete Post?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    deletePost()
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
    
    private var textContentSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            if let caption = post.caption, !caption.isEmpty {
                Text(caption)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            } else {
                Text("Text post")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(Color(.systemGray6))
    }
    
    private func deletePost() {
        guard canDelete else { return }
        isDeleting = true
        Task {
            do {
                try await APIClient.shared.deletePost(id: post.id)
                await MainActor.run {
                    isDeleting = false
                    onDelete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
    
    private var imageSection: some View {
        Group {
            if let mediaFilename = post.mediaFilename,
               let url = MediaURL.url(userID: post.user.id, filename: mediaFilename) {
                KFImage(url)
                    .resizable()
                    .placeholder { Color(.systemGray4) }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
            } else {
                Color(.systemGray4)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }
}
