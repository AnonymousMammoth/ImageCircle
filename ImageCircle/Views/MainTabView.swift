//
//  MainTabView.swift
//  ImageCircle
//
//  Root tab interface. Admin tab is only visible to admins.
//

import SwiftUI

struct MainTabView: View {
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedTab = 0
    @State private var refreshFeedTrigger = UUID()
    @State private var unreadCount: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(refreshTrigger: $refreshFeedTrigger)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("Home")
                }
                .tag(0)
            
            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .tag(1)
            
            CreateComposerView(onFinished: { shouldRefresh in
                if shouldRefresh {
                    refreshFeedTrigger = UUID()
                }
                selectedTab = 0
            })
                .tabItem {
                    Image(systemName: "plus.square.fill")
                        .environment(\.symbolVariants, .fill)
                    Text("Create")
                }
                .tag(2)
            
            NotificationsView()
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "bell.fill" : "bell")
                    Text("Notifications")
                }
                .badge(unreadCount)
                .tag(3)
            
            NavigationStack {
                ProfileView(user: auth.currentUser)
            }
            .tabItem {
                Image(systemName: selectedTab == 4 ? "person.fill" : "person")
                Text("Profile")
            }
            .tag(4)
            
            if auth.isAdmin {
                AdminView()
                    .tabItem {
                        Image(systemName: "shield.lefthalf.filled")
                        Text("Admin")
                    }
                    .tag(5)
            }
        }
        .tint(.pink)
        .onAppear {
            updateUnreadCount()
        }
        .onChange(of: selectedTab) { _, _ in
            if selectedTab == 3 {
                updateUnreadCount()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationsDidRead)) { _ in
            unreadCount = 0
        }
    }

    private func updateUnreadCount() {
        Task {
            do {
                let count = try await APIClient.shared.fetchUnreadNotificationCount()
                await MainActor.run {
                    unreadCount = count
                }
            } catch {
                // Silently ignore badge fetch failures.
            }
        }
    }
}

extension Notification.Name {
    static let notificationsDidRead = Notification.Name("notificationsDidRead")
}
