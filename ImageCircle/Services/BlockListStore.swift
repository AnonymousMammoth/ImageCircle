//
//  BlockListStore.swift
//  ImageCircle
//
//  Lightweight in-memory store of blocked user IDs. Fetched on app launch/login.
//

import Foundation
import Combine

@MainActor
final class BlockListStore: ObservableObject {
    static let shared = BlockListStore()

    @Published private(set) var blockedUserIDs: Set<Int> = []

    var isEmpty: Bool { blockedUserIDs.isEmpty }

    func isBlocked(userID: Int) -> Bool {
        blockedUserIDs.contains(userID)
    }

    /// Loads the current user's block list from the backend.
    func fetch() async {
        do {
            let ids = try await APIClient.shared.fetchBlockedUsers()
            blockedUserIDs = Set(ids)
        } catch {
            // Best-effort; leave existing set on failure.
        }
    }

    func block(userID: Int) async throws {
        try await APIClient.shared.blockUser(id: userID)
        blockedUserIDs.insert(userID)
    }

    func unblock(userID: Int) async throws {
        try await APIClient.shared.unblockUser(id: userID)
        blockedUserIDs.remove(userID)
    }

    func clear() {
        blockedUserIDs.removeAll()
    }
}
