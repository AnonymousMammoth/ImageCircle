//
//  AdminView.swift
//  ImageCircle
//
//  Admin-only user management panel.
//

import SwiftUI
import Kingfisher

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

            Section("Moderation") {
                NavigationLink("Review Content") {
                    ContentReviewView()
                }
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
            AvatarImage(user: user, size: 32)
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
                
                Text("This temporary password will be cleared from the pasteboard 30 seconds after copying.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [password] in
            if UIPasteboard.general.string == password {
                UIPasteboard.general.string = ""
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}

struct ContentReviewView: View {
    @State private var selectedType: ContentType = .post
    @State private var items: [Any] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var page = 1
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var itemToDelete: DeletableItem?
    @State private var showDeleteConfirm = false
    
    private let pageSize = 20
    
    enum ContentType: String, CaseIterable, Identifiable {
        case post = "post"
        case story = "story"
        case comment = "comment"
        
        var id: String { rawValue }
        var label: String {
            switch self {
            case .post: return "Posts"
            case .story: return "Stories"
            case .comment: return "Comments"
            }
        }
    }
    
    struct DeletableItem: Identifiable {
        let id: Int
        let type: ContentType
        let title: String
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("Type", selection: $selectedType) {
                ForEach(ContentType.allCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            List {
                ForEach(0..<items.count, id: \.self) { index in
                    contentRow(for: items[index])
                        .onAppear {
                            if index >= items.count - 5 && hasMore && !isLoading {
                                loadMore()
                            }
                        }
                }
                
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Review Content")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedType) { _, _ in
            resetAndLoad()
        }
        .onAppear {
            resetAndLoad()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Could not load content.")
        }
        .alert("Delete Content?", isPresented: $showDeleteConfirm, presenting: itemToDelete) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        } message: { item in
            Text("Are you sure you want to delete \(item.title)? This cannot be undone.")
        }
    }
    
    @ViewBuilder
    private func contentRow(for item: Any) -> some View {
        if let post = item as? Post {
            postRow(post)
        } else if let story = item as? Story {
            storyRow(story)
        } else if let comment = item as? Comment {
            commentRow(comment)
        } else {
            EmptyView()
        }
    }
    
    private func postRow(_ post: Post) -> some View {
        HStack(spacing: 12) {
            let mediaURL = post.thumbnailFilename.flatMap { MediaURL.url(userID: post.user.id, filename: $0) }
                ?? post.mediaFilename.flatMap { MediaURL.url(userID: post.user.id, filename: $0) }
            if let url = mediaURL {
                KFImage(url)
                    .resizable()
                    .placeholder { Color.gray }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
                    .overlay(Text("Text").font(.caption))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(post.user.username)
                    .font(.subheadline.weight(.semibold))
                Text(post.caption?.isEmpty == false ? post.caption! : "No caption")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(post.createdAt.relativeTimeFromISO())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                prepareDelete(id: post.id, type: .post, title: "this post")
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func storyRow(_ story: Story) -> some View {
        HStack(spacing: 12) {
            if let url = story.resolvedThumbnailURL ?? story.resolvedMediaURL {
                KFImage(url)
                    .resizable()
                    .placeholder { Color.gray }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 60)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(story.user.username)
                    .font(.subheadline.weight(.semibold))
                Text(story.mediaType.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(story.createdAt.relativeTimeFromISO())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                prepareDelete(id: story.id, type: .story, title: "this story")
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func commentRow(_ comment: Comment) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.user.username)
                    .font(.subheadline.weight(.semibold))
                Text(comment.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                Text(comment.createdAt.relativeTimeFromISO())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                prepareDelete(id: comment.id, type: .comment, title: "this comment")
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func prepareDelete(id: Int, type: ContentType, title: String) {
        itemToDelete = DeletableItem(id: id, type: type, title: title)
        showDeleteConfirm = true
    }
    
    private func resetAndLoad() {
        page = 1
        hasMore = true
        items = []
        loadMore()
    }
    
    private func loadMore() {
        guard !isLoading && hasMore else { return }
        isLoading = true
        
        Task {
            do {
                let newItems = try await APIClient.shared.adminListContent(type: selectedType.rawValue, page: page, limit: pageSize)
                await MainActor.run {
                    items.append(contentsOf: newItems)
                    hasMore = newItems.count == pageSize
                    page += 1
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
    
    private func deleteItem(_ item: DeletableItem) {
        Task {
            do {
                switch item.type {
                case .post:
                    try await APIClient.shared.adminDeletePost(id: item.id)
                case .story:
                    try await APIClient.shared.adminDeleteStory(id: item.id)
                case .comment:
                    try await APIClient.shared.adminDeleteComment(id: item.id)
                }
                await MainActor.run {
                    items.removeAll { ($0 as? Post)?.id == item.id || ($0 as? Story)?.id == item.id || ($0 as? Comment)?.id == item.id }
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
