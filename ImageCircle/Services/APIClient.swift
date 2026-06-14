//
//  APIClient.swift
//  ImageCircle
//
//  URLSession-based backend client. All endpoints assume /api prefix.
//  Uploads use multipart/form-data with client-side compression.
//

import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case invalidURL
    case invalidResponse
    case decodingError(Error)
    case serverError(Int, String?)
    case unauthorized
    case forbidden
    case networkFailure(Error)
    case noData
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL."
        case .invalidResponse: return "Unexpected response from server."
        case .decodingError: return "Failed to parse server response."
        case .serverError(let code, let msg):
            if let msg = msg, !msg.isEmpty { return msg }
            return "Server error (\(code))."
        case .unauthorized: return "Session expired. Please log in again."
        case .forbidden: return "You don't have permission to do that."
        case .networkFailure: return "Cannot connect to server. Check your URL and network."
        case .noData: return "No data returned from server."
        case .cancelled: return "Request cancelled."
        }
    }
    
    static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.decodingError, .decodingError),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.networkFailure, .networkFailure),
             (.noData, .noData),
             (.cancelled, .cancelled):
            return true
        case (.serverError(let lc, let lm), .serverError(let rc, let rm)):
            return lc == rc && lm == rm
        default:
            return false
        }
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()
    
    var baseURLString: String {
        get { UserDefaults.standard.string(forKey: "server_url") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "server_url") }
    }
    
    var token: String?
    
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let session: URLSession
    private let uploadSession: URLSession
    
    private init() {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = 120
        uploadConfig.timeoutIntervalForResource = 300
        self.uploadSession = URLSession(configuration: uploadConfig)
    }
    
    // MARK: - Base URL
    
    private func baseURL() throws -> URL {
        let urlString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }
        return url
    }
    
    private func apiURL(path: String) throws -> URL {
        let base = try baseURL()
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return base.appendingPathComponent("api/\(trimmedPath)")
    }
    
    // MARK: - Request Builder
    
    private func request(for url: URL, method: String = "GET", body: Data? = nil, contentType: String = "application/json") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ImageCircle-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token = token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }
    
    // MARK: - JSON Response Handling
    
    private func perform<T: Decodable>(_ request: URLRequest, session: URLSession? = nil, retry: Bool = true) async throws -> T {
        let activeSession = session ?? self.session
        do {
            let (data, response) = try await activeSession.data(for: request)
            return try await handleResponse(data: data, response: response)
        } catch let error as APIError {
            throw error
        } catch {
            if Task.isCancelled { throw APIError.cancelled }
            if retry && shouldRetry(error) {
                try await Task.sleep(nanoseconds: 500_000_000)
                return try await perform(request, session: session, retry: false)
            }
            throw APIError.networkFailure(error)
        }
    }
    
    private func performVoid(_ request: URLRequest, session: URLSession? = nil, retry: Bool = true) async throws {
        let activeSession = session ?? self.session
        do {
            let (data, response) = try await activeSession.data(for: request)
            _ = try await handleResponse(data: data, response: response, allowEmpty: true) as EmptyResponse
        } catch let error as APIError {
            throw error
        } catch {
            if Task.isCancelled { throw APIError.cancelled }
            if retry && shouldRetry(error) {
                try await Task.sleep(nanoseconds: 500_000_000)
                try await performVoid(request, session: session, retry: false)
                return
            }
            throw APIError.networkFailure(error)
        }
    }
    
    private func handleResponse<T: Decodable>(data: Data, response: URLResponse, allowEmpty: Bool = false) async throws -> T {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // MARK: - Temporary Debug Logging
        let urlString = http.url?.absoluteString ?? "unknown"
        let statusCode = http.statusCode
        let bodyString = String(data: data, encoding: .utf8) ?? "<non-UTF8 data>"
        print("[TEMP DEBUG] Response URL: \(urlString)")
        print("[TEMP DEBUG] HTTP Status: \(statusCode)")
        print("[TEMP DEBUG] Response Body: \(bodyString)")
        // MARK: - End Temporary Debug Logging

        switch http.statusCode {
        case 200...299:
            if allowEmpty && data.isEmpty {
                // Decode an empty struct when no body is expected.
                if let empty = EmptyResponse() as? T {
                    return empty
                }
            }
            do {
                return try jsonDecoder.decode(T.self, from: data)
            } catch {
                // MARK: - Temporary Debug Logging
                print("[TEMP DEBUG] JSON decoding failed for \(urlString): \(error)")
                if let decodingError = error as? DecodingError {
                    print("[TEMP DEBUG] DecodingError details: \(decodingError)")
                }
                // MARK: - End Temporary Debug Logging
                throw APIError.decodingError(error)
            }
        case 401:
            await AuthManager.shared.logout()
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        default:
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(http.statusCode, message)
        }
    }
    
    private func shouldRetry(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .timedOut, .networkConnectionLost, .dnsLookupFailed, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
    
    private struct EmptyResponse: Decodable {}
    
    private struct PostsResponse: Codable {
        let posts: [Post]
    }
    
    private struct CommentsResponse: Codable {
        let comments: [Comment]
    }
    
    private struct StoriesResponse: Codable {
        let stories: [Story]
    }
    
    private struct UsersResponse: Codable {
        let users: [User]
    }
    
    private struct LikeResponse: Codable {
        let liked: Bool
        let likeCount: Int
        
        enum CodingKeys: String, CodingKey {
            case liked
            case likeCount
        }
    }
    
    // MARK: - Auth Endpoints
    
    func login(username: String, password: String) async throws -> LoginResponse {
        let url = try apiURL(path: "auth/login")
        let body = ["username": username, "password": password]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }
    
    func changePassword(currentPassword: String, newPassword: String) async throws -> ChangePasswordResponse {
        let url = try apiURL(path: "auth/change-password")
        let body = ["current_password": currentPassword, "new_password": newPassword]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }
    
    func logout() async throws {
        let url = try apiURL(path: "auth/logout")
        let req = request(for: url, method: "POST")
        try await performVoid(req)
    }
    
    func fetchMe() async throws -> User {
        let url = try apiURL(path: "users/me")
        let req = request(for: url)
        return try await perform(req)
    }

    func fetchUserPosts(userID: Int) async throws -> [Post] {
        let url = try apiURL(path: "users/\(userID)/posts")
        let req = request(for: url)
        let response: PostsResponse = try await perform(req)
        return response.posts
    }

    func updateAvatar(imageData: Data, filename: String = "avatar.jpg") async throws -> User {
        let url = try apiURL(path: "users/me/avatar")
        let boundary = UUID().uuidString
        var req = request(for: url, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)")
        req.httpBody = buildMultipartBody(boundary: boundary, fields: [:], fileData: imageData, fileField: "avatar", filename: filename, mimeType: "image/jpeg")
        return try await perform(req, session: uploadSession)
    }
    
    // MARK: - Feed & Posts
    
    func fetchFeed() async throws -> [Post] {
        let url = try apiURL(path: "posts")
        let req = request(for: url)
        let response: PostsResponse = try await perform(req)
        return response.posts
    }
    
    func toggleLike(id: Int) async throws -> (liked: Bool, likeCount: Int) {
        let url = try apiURL(path: "posts/\(id)/like")
        let req = request(for: url, method: "POST")
        let response: LikeResponse = try await perform(req)
        return (response.liked, response.likeCount)
    }
    
    func fetchComments(postID: Int) async throws -> [Comment] {
        let url = try apiURL(path: "posts/\(postID)/comments")
        let req = request(for: url)
        let response: CommentsResponse = try await perform(req)
        return response.comments
    }
    
    func postComment(postID: Int, text: String) async throws -> Comment {
        let url = try apiURL(path: "posts/\(postID)/comments")
        let body = ["text": text]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }
    
    // MARK: - Stories
    
    func fetchStories() async throws -> [Story] {
        let url = try apiURL(path: "stories")
        let req = request(for: url)
        let response: StoriesResponse = try await perform(req)
        return response.stories
    }
    
    func markStoryViewed(id: Int) async throws {
        let url = try apiURL(path: "stories/\(id)/view")
        let req = request(for: url, method: "POST")
        try await performVoid(req)
    }
    
    // MARK: - Search
    
    func searchUsers(query: String) async throws -> [User] {
        let baseURL = try apiURL(path: "users/search")
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "q", value: encodedQuery)]
        guard let url = components.url else { throw APIError.invalidURL }
        let req = request(for: url)
        let response: UsersResponse = try await perform(req)
        return response.users
    }
    
    // MARK: - Admin
    
    func adminFetchUsers() async throws -> [User] {
        let url = try apiURL(path: "users")
        let req = request(for: url)
        let response: UsersResponse = try await perform(req)
        return response.users
    }
    
    func adminCreateUser(username: String, displayName: String) async throws -> CreateUserResponse {
        let url = try apiURL(path: "users")
        let body = ["username": username, "display_name": displayName]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }
    
    func adminDeleteUser(id: Int) async throws {
        let url = try apiURL(path: "users/\(id)")
        let req = request(for: url, method: "DELETE")
        try await performVoid(req)
    }
    
    func adminResetPassword(id: Int) async throws -> ResetPasswordResponse {
        let url = try apiURL(path: "users/\(id)/reset-password")
        let req = request(for: url, method: "POST")
        return try await perform(req)
    }
    
    func adminToggleAdmin(id: Int) async throws -> User {
        let url = try apiURL(path: "users/\(id)/toggle-admin")
        let req = request(for: url, method: "POST")
        return try await perform(req)
    }
    
    // MARK: - Multipart Uploads
    
    /// Uploads a compressed photo to the feed.
    func createPost(caption: String?, imageData: Data, filename: String = "image.jpg") async throws -> Post {
        let url = try apiURL(path: "posts")
        let boundary = UUID().uuidString
        var req = request(for: url, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)")
        req.httpBody = buildMultipartBody(boundary: boundary, fields: ["caption": caption ?? ""], fileData: imageData, fileField: "media", filename: filename, mimeType: "image/jpeg")
        return try await perform(req, session: uploadSession)
    }
    
    /// Creates a text-only post.
    /// Assumes the backend accepts `POST /api/posts` with JSON body `{ "caption": "..." }`
    /// and returns a Post with no media_filename. Update this if the backend contract differs.
    func createTextPost(caption: String) async throws -> Post {
        let url = try apiURL(path: "posts")
        let body = ["caption": caption]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req, session: uploadSession)
    }
    
    /// Uploads a story image or video with optional thumbnail.
    func createStory(mediaType: String, mediaData: Data, mediaFilename: String, thumbnailData: Data? = nil, thumbnailFilename: String? = nil) async throws -> Story {
        let url = try apiURL(path: "stories")
        let boundary = UUID().uuidString
        var req = request(for: url, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)")
        
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"media_type\"\r\n\r\n")
        body.appendString("\(mediaType)\r\n")
        
        // Media file
        let mimeType = mediaType == "video" ? "video/mp4" : "image/jpeg"
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"media\"; filename=\"\(mediaFilename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(mediaData)
        body.appendString("\r\n")
        
        // Optional thumbnail
        if let thumbData = thumbnailData, let thumbFilename = thumbnailFilename {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"thumbnail\"; filename=\"\(thumbFilename)\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(thumbData)
            body.appendString("\r\n")
        }
        
        body.appendString("--\(boundary)--\r\n")
        req.httpBody = body
        return try await perform(req, session: uploadSession)
    }
    
    private func buildMultipartBody(boundary: String, fields: [String: String], fileData: Data, fileField: String, filename: String, mimeType: String) -> Data {
        var body = Data()
        for (key, value) in fields {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

struct CreateUserResponse: Codable {
    let user: User
    let temporaryPassword: String
    
    enum CodingKeys: String, CodingKey {
        case user
        case temporaryPassword
    }
}

struct ResetPasswordResponse: Codable {
    let temporaryPassword: String
    
    enum CodingKeys: String, CodingKey {
        case temporaryPassword
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
