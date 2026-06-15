//
//  NotificationsView.swift
//  ImageCircle
//
//  Lists likes and comments on the user's posts.
//

import SwiftUI
import Kingfisher

struct NotificationsView: View {
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedPost: Post?
    @State private var refreshTrigger = UUID()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(notifications) { notification in
                    Button(action: { loadPost(notification.post.id) }) {
                        HStack(spacing: 12) {
                            actorAvatar(for: notification.actor)
                                .frame(width: 44, height: 44)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(notificationText(for: notification))
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .foregroundStyle(.primary)

                                Text(notification.createdAt.relativeTimeFromISO())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            notificationThumbnail(for: notification.post)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if notifications.isEmpty && !isLoading {
                    ContentUnavailableView("No notifications yet", systemImage: "bell")
                }
            }
            .refreshable {
                await loadNotifications()
            }
            .task(id: refreshTrigger) {
                await loadNotifications()
            }
            .sheet(item: $selectedPost) { post in
                ProfilePostDetailView(post: post, onDelete: { refreshTrigger = UUID() })
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not load notifications.")
            }
        }
    }
    
    @ViewBuilder
    private func actorAvatar(for actor: NotificationActor) -> some View {
        AvatarImage(user: actor, size: 44)
    }

    @ViewBuilder
    private func notificationThumbnail(for post: NotificationPost) -> some View {
        if let url = resolvedPostURL(for: post) {
            KFImage(url)
                .resizable()
                .placeholder { Color(.systemGray4) }
                .aspectRatio(contentMode: .fill)
        } else {
            Image(systemName: "quote.bubble")
                .resizable()
                .scaledToFit()
                .padding(10)
                .foregroundStyle(.secondary)
                .background(Color(.systemGray4))
        }
    }

    private func resolvedPostURL(for post: NotificationPost) -> URL? {
        let candidates = [post.thumbnailURL, post.mediaURL].compactMap { $0 }
        guard let base = UserDefaults.standard.string(forKey: "server_url"), !base.isEmpty else { return nil }
        for path in candidates {
            guard !path.isEmpty else { continue }
            if let url = URL(string: path), url.scheme != nil {
                return url
            }
            if let url = URL(string: base + path) {
                return url
            }
        }
        return nil
    }
    
    private func notificationText(for notification: AppNotification) -> AttributedString {
        let actor = notification.actor.username
        let postPreview = notification.post.caption?.prefix(30) ?? "your post"
        let suffix: String
        if notification.isMentionPost {
            suffix = "mentioned you in a post: \(postPreview)"
        } else if notification.isMentionComment {
            let commentPreview = notification.comment?.text.prefix(30) ?? "a comment"
            suffix = "mentioned you in a comment: \(commentPreview)"
        } else if notification.isComment {
            suffix = "commented on \(postPreview)"
        } else {
            suffix = "liked \(postPreview)"
        }
        var attributed = AttributedString("\(actor) \(suffix)")
        if let range = attributed.range(of: actor) {
            attributed[range].font = .subheadline.weight(.semibold)
        }
        return attributed
    }
    
    private func loadNotifications() async {
        isLoading = true
        do {
            notifications = try await APIClient.shared.fetchNotifications()
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? APIError) == .cancelled {
                // Ignore cancellation.
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
        isLoading = false
    }
    
    private func loadPost(_ id: Int) {
        Task {
            do {
                selectedPost = try await APIClient.shared.fetchPost(id: id)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
