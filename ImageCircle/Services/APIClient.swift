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
    private let uploadDelegate = UploadDelegate()
    
    private init() {
        let decoder = JSONDecoder()
        // Models use explicit CodingKeys that match the backend JSON field names.
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .iso8601
        self.jsonDecoder = decoder
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        self.jsonEncoder = encoder
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
        
        let uploadConfig = URLSessionConfiguration.default
        uploadConfig.timeoutIntervalForRequest = 120
        uploadConfig.timeoutIntervalForResource = 300
        uploadConfig.httpCookieStorage = HTTPCookieStorage.shared
        uploadConfig.httpShouldSetCookies = true
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        self.uploadSession = URLSession(configuration: uploadConfig, delegate: uploadDelegate, delegateQueue: delegateQueue)
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
            if Task.isCancelled || isCancellationError(error) { throw APIError.cancelled }
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
            if Task.isCancelled || isCancellationError(error) { throw APIError.cancelled }
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
    
    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let apiError = error as? APIError, apiError == .cancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }
    
    private func upload<T: Decodable>(_ request: URLRequest, fromFile fileURL: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws -> T {
        guard !Task.isCancelled else { throw APIError.cancelled }
        let taskBox = TaskBox()
        
        do {
            let (data, response) = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, URLResponse), Error>) in
                    let task = uploadSession.uploadTask(with: request, fromFile: fileURL)
                    taskBox.task = task
                    uploadDelegate.setProgressHandler(progress, for: task)
                    uploadDelegate.setCompletion(continuation, for: task)
                    task.resume()
                }
            } onCancel: {
                if let task = taskBox.task {
                    task.cancel()
                    uploadDelegate.setCompletion(nil, for: task)
                    uploadDelegate.setProgressHandler(nil, for: task)
                }
            }
            return try await handleResponse(data: data, response: response)
        } catch {
            if Task.isCancelled || isCancellationError(error) { throw APIError.cancelled }
            throw error
        }
    }
    
    private final class TaskBox {
        var task: URLSessionTask?
    }
    
    private struct EmptyResponse: Decodable {}

    private struct ReportRequestBody: Codable {
        let targetType: String
        let targetId: Int
        let reason: String

        enum CodingKeys: String, CodingKey {
            case targetType = "target_type"
            case targetId = "target_id"
            case reason
        }
    }

    private struct PostsResponse: Codable {
        let posts: [Post]
    }
    
    private struct CommentsResponse: Codable {
        let comments: [Comment]?
    }
    
    private struct StoriesResponse: Codable {
        let stories: [Story]
    }
    
    private struct UsersResponse: Codable {
        let users: [User]
    }
    
    private struct NotificationsResponse: Codable {
        let notifications: [AppNotification]
    }
    
    private struct LikeResponse: Codable {
        let liked: Bool
        let likeCount: Int

        enum CodingKeys: String, CodingKey {
            case liked
            case likeCount = "like_count"
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

    func updateAvatar(imageData: Data, filename: String = "avatar.jpg", progress: (@Sendable (Double) -> Void)? = nil) async throws -> User {
        let url = try apiURL(path: "users/me/avatar")
        let boundary = UUID().uuidString
        var req = request(for: url, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)")
        let body = buildMultipartBody(boundary: boundary, fields: [:], fileData: imageData, fileField: "avatar", filename: filename, mimeType: "image/jpeg")
        let (fileURL, cleanup) = try writeToTempFile(data: body, name: "upload-\(boundary).body")
        defer { cleanup() }
        return try await upload(req, fromFile: fileURL, progress: progress)
    }
    
    // MARK: - Feed & Posts
    
    /// Uploads a compressed photo to the feed with optional thumbnail and progress reporting (0.0...1.0).
    func createPost(caption: String?, imageData: Data, thumbnailData: Data? = nil, filename: String = "image.jpg", progress: (@Sendable (Double) -> Void)? = nil) async throws -> Post {
        let url = try apiURL(path: "posts")
        let boundary = UUID().uuidString
        var req = request(for: url, method: "POST", contentType: "multipart/form-data; boundary=\(boundary)")

        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"caption\"\r\n\r\n")
        body.appendString("\(caption ?? "")\r\n")

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"media\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.appendString("\r\n")

        if let thumbnailData = thumbnailData {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"thumbnail\"; filename=\"thumb.jpg\"\r\n")
            body.appendString("Content-Type: image/jpeg\r\n\r\n")
            body.append(thumbnailData)
            body.appendString("\r\n")
        }

        body.appendString("--\(boundary)--\r\n")

        let (fileURL, cleanup) = try writeToTempFile(data: body, name: "upload-\(boundary).body")
        defer { cleanup() }
        return try await upload(req, fromFile: fileURL, progress: progress)
    }
    
    func fetchFeed() async throws -> [Post] {
        let url = try apiURL(path: "posts")
        let req = request(for: url)
        let response: PostsResponse = try await perform(req)
        return response.posts
    }
    
    func fetchPost(id: Int) async throws -> Post {
        let url = try apiURL(path: "posts/\(id)")
        let req = request(for: url)
        return try await perform(req)
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
        return response.comments ?? []
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

    func fetchStories(userID: Int) async throws -> [Story] {
        let url = try apiURL(path: "users/\(userID)/stories")
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
    
    func fetchNotifications() async throws -> [AppNotification] {
        let url = try apiURL(path: "notifications")
        let req = request(for: url)
        let response: NotificationsResponse = try await perform(req)
        return response.notifications
    }

    // MARK: - Reports & Blocks

    func createReport(targetType: String, targetID: Int, reason: String) async throws -> ReportResponse {
        let url = try apiURL(path: "reports")
        let body = ReportRequestBody(targetType: targetType, targetId: targetID, reason: reason)
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }

    func fetchBlockedUsers() async throws -> [Int] {
        let url = try apiURL(path: "users/me/blocked")
        let req = request(for: url)
        let response: BlockedUsersResponse = try await perform(req)
        return response.blockedUserIDs
    }

    func blockUser(id: Int) async throws {
        let url = try apiURL(path: "users/\(id)/block")
        let req = request(for: url, method: "POST")
        try await performVoid(req)
    }

    func unblockUser(id: Int) async throws {
        let url = try apiURL(path: "users/\(id)/block")
        let req = request(for: url, method: "DELETE")
        try await performVoid(req)
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
    
    // MARK: - Delete
    
    func deletePost(id: Int) async throws {
        let url = try apiURL(path: "posts/\(id)")
        let req = request(for: url, method: "DELETE")
        try await performVoid(req)
    }
    
    func deleteStory(id: Int) async throws {
        let url = try apiURL(path: "stories/\(id)")
        let req = request(for: url, method: "DELETE")
        try await performVoid(req)
    }
    
    func deleteComment(id: Int) async throws {
        let url = try apiURL(path: "comments/\(id)")
        let req = request(for: url, method: "DELETE")
        try await performVoid(req)
    }
    
    // MARK: - Multipart Uploads
    

    
    private func writeToTempFile(data: Data, name: String) throws -> (URL, () -> Void) {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: fileURL, options: .atomic)
        return (fileURL, { try? FileManager.default.removeItem(at: fileURL) })
    }
    
    /// Creates a text-only post.
    /// Assumes the backend accepts `POST /api/posts` with JSON body `{ "caption": "..." }`
    /// and returns a Post with no media_filename. Update this if the backend contract differs.
    func createTextPost(caption: String) async throws -> Post {
        let url = try apiURL(path: "posts")
        let body = ["caption": caption]
        let data = try jsonEncoder.encode(body)
        let req = request(for: url, method: "POST", body: data)
        return try await perform(req)
    }
    
    /// Uploads a story image or video with optional thumbnail and optional progress reporting.
    func createStory(mediaType: String, mediaData: Data, mediaFilename: String, thumbnailData: Data? = nil, thumbnailFilename: String? = nil, progress: (@Sendable (Double) -> Void)? = nil) async throws -> Story {
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
        let (fileURL, cleanup) = try writeToTempFile(data: body, name: "upload-\(boundary).body")
        defer { cleanup() }
        return try await upload(req, fromFile: fileURL, progress: progress)
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
        case temporaryPassword = "temporary_password"
    }
}

struct ResetPasswordResponse: Codable {
    let temporaryPassword: String

    enum CodingKeys: String, CodingKey {
        case temporaryPassword = "temporary_password"
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - Upload Delegate

/// Delegate that reports upload progress and captures the response for async upload tasks.
private final class UploadDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private var progressHandlers: [Int: @Sendable (Double) -> Void] = [:]
    private var completions: [Int: CheckedContinuation<(Data, URLResponse), Error>] = [:]
    private var responseData: [Int: Data] = [:]
    private let lock = NSLock()
    
    func setProgressHandler(_ handler: (@Sendable (Double) -> Void)?, for task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        progressHandlers[task.taskIdentifier] = handler
    }
    
    func setCompletion(_ completion: CheckedContinuation<(Data, URLResponse), Error>?, for task: URLSessionTask) {
        lock.lock()
        defer { lock.unlock() }
        if let completion = completion {
            completions[task.taskIdentifier] = completion
            responseData[task.taskIdentifier] = Data()
        } else {
            completions.removeValue(forKey: task.taskIdentifier)
            responseData.removeValue(forKey: task.taskIdentifier)
            progressHandlers.removeValue(forKey: task.taskIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        lock.lock()
        let handler = progressHandlers[task.taskIdentifier]
        lock.unlock()
        handler?(progress)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        responseData[dataTask.taskIdentifier]?.append(data)
        lock.unlock()
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let completion = completions.removeValue(forKey: task.taskIdentifier)
        let data = responseData.removeValue(forKey: task.taskIdentifier) ?? Data()
        progressHandlers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        
        guard let completion = completion else { return }
        
        if let error = error {
            completion.resume(throwing: error)
        } else if let response = task.response {
            completion.resume(returning: (data, response))
        } else {
            completion.resume(throwing: APIError.invalidResponse)
        }
    }
}
