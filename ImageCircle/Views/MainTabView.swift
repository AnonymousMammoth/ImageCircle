//
//  MainTabView.swift
//  ImageCircle
//
//  Root tab interface. Admin tab is only visible to admins.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var selectedTab = 0
    @State private var refreshFeedTrigger = UUID()
    
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
            
            CameraView(onFinished: { shouldRefresh in
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
            
            ProfileView(user: auth.currentUser)
                .tabItem {
                    Image(systemName: selectedTab == 3 ? "person.fill" : "person")
                    Text("Profile")
                }
                .tag(3)
            
            if auth.isAdmin {
                AdminView()
                    .tabItem {
                        Image(systemName: "shield.lefthalf.filled")
                        Text("Admin")
                    }
                    .tag(4)
            }
        }
        .tint(.pink)
    }
}
