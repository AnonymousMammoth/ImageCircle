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
    
    private var lastUsedPassword: String?
    
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
        self.lastUsedPassword = password

        try KeychainHelper.shared.saveToken(response.token)
        self.token = response.token
        APIClient.shared.token = response.token
        self.currentUser = response.user
        self.isAuthenticated = true
    }
    
    /// Returns the password last used during login so a forced password change can use it as current_password.
    func lastPassword() -> String? {
        lastUsedPassword
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
        self.lastUsedPassword = nil
        APIClient.shared.token = nil
        // Do NOT clear server URL so the user can log in again quickly.
    }
}

struct LoginResponse: Codable {
    let token: String
    let user: User
    let expiresAt: String?
}

struct ChangePasswordResponse: Codable {
    let success: Bool
    let token: String
    let expiresAt: String?
}
