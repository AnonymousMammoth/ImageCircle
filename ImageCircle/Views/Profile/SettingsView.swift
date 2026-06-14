//
//  SettingsView.swift
//  ImageCircle
//
//  Profile settings sheet with change password, admin panel, and logout.
//

import SwiftUI
import Kingfisher

struct SettingsView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var showChangePassword = false
    @State private var showAdmin = false
    @State private var showLogoutConfirm = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    NavigationLink(destination: ChangePasswordView()) {
                        Label("Change Password", systemImage: "lock")
                    }
                    
                    HStack {
                        Label("Server", systemImage: "network")
                        Spacer()
                        Text(auth.serverURL)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                if auth.isAdmin {
                    Section("Admin") {
                        NavigationLink(destination: AdminView()) {
                            Label("Admin Panel", systemImage: "shield.lefthalf.filled")
                        }
                    }
                }
                
                Section("Danger") {
                    Button(role: .destructive, action: { showLogoutConfirm = true }) {
                        Label("Log Out", systemImage: "arrow.right.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Log Out?", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Log Out", role: .destructive) {
                    Task {
                        await AuthManager.shared.logout()
                        KingfisherManager.shared.cache.clearDiskCache()
                        KingfisherManager.shared.cache.clearMemoryCache()
                        dismiss()
                    }
                }
            } message: {
                Text("This will clear your session and cached images.")
            }
        }
    }
}
