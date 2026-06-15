//
//  SearchView.swift
//  ImageCircle
//
//  User search with debounced API calls.
//

import SwiftUI
import Combine

struct SearchView: View {
    @State private var query: String = ""
    @StateObject private var searchTask = DebounceTask()
    @State private var results: [User] = []
    @State private var isSearching = false
    @State private var selectedUser: User?
    @State private var showProfile = false
    
    var body: some View {
        NavigationStack {
            List(results) { user in
                Button(action: {
                    selectedUser = user
                    showProfile = true
                }) {
                    HStack(spacing: 12) {
                        placeholderAvatar(name: user.username)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.username)
                                .font(.headline)
                            Text(user.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("Search")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by username")
            .onChange(of: query) { _, newValue in
                searchTask.debounce(interval: 0.3) {
                    await performSearch(query: newValue)
                }
            }
            .overlay {
                if results.isEmpty && !query.isEmpty && !isSearching {
                    ContentUnavailableView("No users found", systemImage: "magnifyingglass")
                } else if query.isEmpty {
                    ContentUnavailableView("Search for friends", systemImage: "magnifyingglass")
                }
            }
            .navigationDestination(isPresented: $showProfile) {
                if let user = selectedUser {
                    ProfileView(user: user)
                }
            }
            .onDisappear {
                searchTask.cancel()
            }
        }
    }
    
    private func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await MainActor.run { results = [] }
            return
        }
        await MainActor.run { isSearching = true }
        do {
            let users = try await APIClient.shared.searchUsers(query: trimmed)
            await MainActor.run { results = users }
        } catch {
            await MainActor.run { results = [] }
        }
        await MainActor.run { isSearching = false }
    }
}

// MARK: - Debounce Helper

@MainActor
final class DebounceTask: ObservableObject {
    private var task: Task<Void, Never>?
    
    func debounce(interval: TimeInterval, action: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await action()
            } catch {
                // Cancelled
            }
        }
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}
