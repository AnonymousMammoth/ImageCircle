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
    private func actorAvatar(for user: User) -> some View {
        AvatarImage(user: user, size: 44)
    }
    
    private func notificationText(for notification: AppNotification) -> AttributedString {
        let actor = notification.actor.username
        let postPreview = notification.post.caption?.prefix(30) ?? "your post"
        let suffix = notification.isComment ? "commented on \(postPreview)" : "liked \(postPreview)"
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
