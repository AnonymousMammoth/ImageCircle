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
    @State private var showSettings = false
    @State private var isLoading = false
    @State private var filter: FeedFilter = .mixed
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var errorMessage: String?
    @State private var showError = false
    
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
            ProfilePostDetailView(post: post)
        }
        .task {
            await loadPosts()
        }
        .onChange(of: auth.currentUser) { _ in
            Task { await loadPosts() }
        }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
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
            if let filename = displayUser?.avatarFilename,
               !filename.isEmpty,
               let url = MediaURL.url(userID: displayUser?.id ?? 0, filename: filename) {
                KFImage(url)
                    .resizable()
                    .placeholder { placeholderAvatar(name: displayUser?.username ?? "") }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
            } else {
                placeholderAvatar(name: displayUser?.username ?? "")
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
                .onChange(of: selectedPhotoItem) { newItem in
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(filteredPosts) { post in
                Button(action: { selectedPost = post }) {
                    if post.isTextOnly {
                        textPostCell(for: post)
                    } else if let filename = post.thumbnailFilename ?? post.mediaFilename,
                              let url = MediaURL.url(userID: post.user.id, filename: filename) {
                        KFImage(url)
                            .resizable()
                            .placeholder { Color(.systemGray4) }
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity, minHeight: 0)
                            .aspectRatio(1, contentMode: .fill)
                            .clipped()
                    } else {
                        Color(.systemGray4)
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View post \(post.id)")
            }
        }
    }
    
    private func textPostCell(for post: Post) -> some View {
        ZStack {
            Color(.systemGray6)
                .aspectRatio(1, contentMode: .fill)
            
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
    }
    
    private func loadPosts() async {
        guard let displayUser = displayUser else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Try the dedicated user-posts endpoint first (added in newer backends).
            posts = try await APIClient.shared.fetchUserPosts(userID: displayUser.id)
        } catch {
            // Fall back to filtering the global feed for older backends.
            do {
                let feed = try await APIClient.shared.fetchFeed()
                posts = feed.filter { $0.user.id == displayUser.id }
            } catch {
                posts = []
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func uploadAvatar(from item: PhotosPickerItem?) async {
        guard let item = item else { return }
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                errorMessage = "Could not load selected photo."
                showError = true
                return
            }
            _ = try await APIClient.shared.updateAvatar(imageData: data)
            // Refresh current user to show new avatar
            let updatedUser = try await APIClient.shared.fetchMe()
            auth.currentUser = updatedUser
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Profile Post Detail View

struct ProfilePostDetailView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
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
