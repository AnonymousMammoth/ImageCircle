//
//  AdminView.swift
//  ImageCircle
//
//  Admin-only user management panel.
//

import SwiftUI

struct AdminView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var users: [User] = []
    @State private var showAddUser = false
    @State private var showPasswordModal = false
    @State private var passwordToShow: String = ""
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var userToDelete: User?
    @State private var showDeleteConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: { showAddUser = true }) {
                        HStack {
                            Spacer()
                            Text("Add User")
                                .font(.headline)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.pink)
                    .foregroundStyle(.white)
                }
                
                Section("Users") {
                    ForEach(users) { user in
                        UserRow(user: user) {
                            resetPassword(for: user)
                        } toggleAdmin: {
                            toggleAdmin(for: user)
                        } delete: {
                            userToDelete = user
                            showDeleteConfirm = true
                        }
                    }
                }
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAddUser) {
                AddUserSheet(onUserCreated: { password in
                    passwordToShow = password
                    showPasswordModal = true
                    Task { await loadUsers() }
                })
            }
            .sheet(isPresented: $showPasswordModal) {
                PasswordModal(password: passwordToShow)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
            .alert("Delete User?", isPresented: $showDeleteConfirm, presenting: userToDelete) { user in
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    delete(user: user)
                }
            } message: { user in
                Text("Are you sure you want to delete @\(user.username)? This cannot be undone.")
            }
            .task {
                await loadUsers()
            }
        }
    }
    
    private func loadUsers() async {
        do {
            users = try await APIClient.shared.adminFetchUsers()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
        }
    }
    
    private func resetPassword(for user: User) {
        Task {
            do {
                let response = try await APIClient.shared.adminResetPassword(id: user.id)
                passwordToShow = response.temporaryPassword
                showPasswordModal = true
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
    
    private func toggleAdmin(for user: User) {
        guard let current = auth.currentUser, user.id != current.id else {
            errorMessage = "You cannot change your own admin status here."
            showError = true
            return
        }
        if user.isAdmin && users.filter({ $0.isAdmin }).count <= 1 {
            errorMessage = "There must be at least one admin."
            showError = true
            return
        }
        Task {
            do {
                _ = try await APIClient.shared.adminToggleAdmin(id: user.id)
                await loadUsers()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
    
    private func delete(user: User) {
        guard let current = auth.currentUser, user.id != current.id else {
            errorMessage = "You cannot delete your own account."
            showError = true
            return
        }
        Task {
            do {
                try await APIClient.shared.adminDeleteUser(id: user.id)
                await loadUsers()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - User Row

struct UserRow: View {
    let user: User
    let resetPassword: () -> Void
    let toggleAdmin: () -> Void
    let delete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            placeholderAvatar(name: user.username)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.username)
                        .font(.headline)
                    if user.isAdmin {
                        Text("ADMIN")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.pink.opacity(0.15))
                            .foregroundStyle(.pink)
                            .clipShape(Capsule())
                    }
                }
                Text(user.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: delete) {
                Label("Delete", systemImage: "trash")
            }
            .accessibilityLabel("Delete user \(user.username)")
        }
        .swipeActions(edge: .leading) {
            Button(action: resetPassword) {
                Label("Reset", systemImage: "key")
            }
            .tint(.indigo)
            .accessibilityLabel("Reset password for \(user.username)")
            Button(action: toggleAdmin) {
                Label(user.isAdmin ? "Demote" : "Promote", systemImage: "shield")
            }
            .tint(.orange)
            .accessibilityLabel("\(user.isAdmin ? "Remove admin from" : "Make admin") \(user.username)")
        }
    }
}

// MARK: - Add User Sheet

struct AddUserSheet: View {
    let onUserCreated: (String) -> Void
    
    @State private var username: String = ""
    @State private var displayName: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    
    private var canCreate: Bool {
        !username.isEmpty && !displayName.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("New User") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Display Name", text: $displayName)
                }
                
                Section {
                    Button(action: create) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Create User")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!canCreate || isLoading)
                    .listRowBackground(canCreate && !isLoading ? Color.pink : Color.pink.opacity(0.5))
                    .foregroundStyle(.white)
                }
            }
            .navigationTitle("Add User")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not create user.")
            }
        }
    }
    
    private func create() {
        guard canCreate else { return }
        isLoading = true
        Task {
            do {
                let response = try await APIClient.shared.adminCreateUser(username: username, displayName: displayName)
                isLoading = false
                dismiss()
                onUserCreated(response.temporaryPassword)
            } catch {
                isLoading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Password Modal

struct PasswordModal: View {
    let password: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "key.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60, height: 60)
                    .foregroundStyle(.pink)
                
                Text("Temporary Password")
                    .font(.title2.weight(.semibold))
                
                Text(password)
                    .font(.system(.body, design: .monospaced))
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .textSelection(.enabled)
                
                Button(action: copy) {
                    HStack {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Spacer()
            }
            .padding(24)
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func copy() {
        UIPasteboard.general.string = password
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
