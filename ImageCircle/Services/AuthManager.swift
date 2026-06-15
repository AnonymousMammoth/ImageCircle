//
//  AuthManager.swift
//  ImageCircle
//
//  Central auth state holder. Token lives in Keychain; server URL lives in UserDefaults.
//

import Foundation
import Combine

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var token: String?
    @Published var currentUser: User?
    @Published var isAuthenticated: Bool = false
    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "server_url")
        }
    }
    
    var isAdmin: Bool { currentUser?.isAdmin ?? false }
    var needsPasswordChange: Bool { currentUser?.passwordChangeRequired ?? false }
    
    /// Whether the current user can delete content owned by another user.
    func canDelete(contentUserID: Int) -> Bool {
        guard let currentUser = currentUser else { return false }
        return currentUser.id == contentUserID || currentUser.isAdmin
    }
    
    private init() {
        self.serverURL = UserDefaults.standard.string(forKey: "server_url") ?? ""
    }
    
    /// Called once on app launch to restore a previous session.
    func loadStoredCredentials() async {
        do {
            let storedToken = try KeychainHelper.shared.readToken()
            self.token = storedToken
            APIClient.shared.token = storedToken
            
            // Validate token by fetching current user.
            let user = try await APIClient.shared.fetchMe()
            self.currentUser = user
            self.isAuthenticated = true
            await BlockListStore.shared.fetch()
        } catch {
            // Token missing or invalid; remain logged out.
            await logout()
        }
    }
    
    func login(serverURL: String, username: String, password: String) async throws {
        var normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        normalizedURL = normalizedURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercasedURL = normalizedURL.lowercased()
        if !lowercasedURL.hasPrefix("http://") && !lowercasedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
        }

        self.serverURL = normalizedURL
        UserDefaults.standard.set(normalizedURL, forKey: "server_url")
        APIClient.shared.baseURLString = normalizedURL

        let response = try await APIClient.shared.login(username: username, password: password)

        try KeychainHelper.shared.saveToken(response.token)
        self.token = response.token
        APIClient.shared.token = response.token
        self.currentUser = response.user
        self.isAuthenticated = true
        await BlockListStore.shared.fetch()
    }

    func changePassword(currentPassword: String, newPassword: String) async throws {
        let response = try await APIClient.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
        try KeychainHelper.shared.saveToken(response.token)
        self.token = response.token
        APIClient.shared.token = response.token
        // Refresh current user so passwordChangeRequired flips to false.
        self.currentUser = try await APIClient.shared.fetchMe()
    }
    
    func logout() async {
        // Best-effort server logout; ignore errors.
        if let token = self.token {
            APIClient.shared.token = token
            try? await APIClient.shared.logout()
        }
        
        try? KeychainHelper.shared.deleteToken()
        self.token = nil
        self.currentUser = nil
        self.isAuthenticated = false
        APIClient.shared.token = nil
        BlockListStore.shared.clear()
        // Do NOT clear server URL so the user can log in again quickly.
    }
}

struct LoginResponse: Codable {
    let token: String
    let user: User
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case token
        case user
        case expiresAt = "expires_at"
    }
}

struct ChangePasswordResponse: Codable {
    let success: Bool
    let token: String
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case success
        case token
        case expiresAt = "expires_at"
    }
}
