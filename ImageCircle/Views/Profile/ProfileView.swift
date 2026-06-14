//
//  ProfileView.swift
//  ImageCircle
//
//  User profile with avatar, stats, and a grid of posts.
//

import SwiftUI
import Kingfisher

struct ProfileView: View {
    let user: User?
    
    @StateObject private var auth = AuthManager.shared
    @State private var posts: [Post] = []
    @State private var selectedPost: Post?
    @State private var showSettings = false
    @State private var isLoading = false
    
    private var isCurrentUser: Bool {
        guard let user = user, let current = auth.currentUser else { return true }
        return user.id == current.id
    }
    
    private var displayUser: User? {
        user ?? auth.currentUser
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                profileHeader
                statsRow
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
            FullScreenImageView(post: post)
        }
        .task {
            await loadPosts()
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 12) {
            placeholderAvatar(name: displayUser?.username ?? "")
                .frame(width: 80, height: 80)
            
            Text(displayUser?.username ?? "")
                .font(.title2.weight(.semibold))
            
            Text(displayUser?.displayName ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 16)
    }
    
    private var statsRow: some View {
        HStack {
            Spacer()
            VStack {
                Text("\(posts.count)")
                    .font(.headline.weight(.semibold))
                Text("posts")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
    
    private var postGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 3), spacing: 1) {
            ForEach(posts) { post in
                Button(action: { selectedPost = post }) {
                    if let filename = post.thumbnailFilename ?? post.mediaFilename,
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
    
    private func loadPosts() async {
        // The backend contract does not include a user posts endpoint.
        // For the current user, we filter the feed; for others, posts remain empty until an endpoint is added.
        guard isCurrentUser else { return }
        do {
            let feed = try await APIClient.shared.fetchFeed()
            posts = feed.filter { $0.user.id == displayUser?.id }
        } catch {
            posts = []
        }
    }
}

// MARK: - Full Screen Image Viewer

struct FullScreenImageView: View {
    let post: Post
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let mediaFilename = post.mediaFilename,
                   let url = MediaURL.url(userID: post.user.id, filename: mediaFilename) {
                    KFImage(url)
                        .resizable()
                        .placeholder { Color.black }
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
        }
    }
}
