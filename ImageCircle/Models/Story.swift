//
//  Story.swift
//  ImageCircle
//
//  Story model matching the backend API contract.
//  Stories are ephemeral; 404s during viewing should be handled gracefully.
//

import Foundation

struct Story: Codable, Identifiable, Hashable {
    let id: Int
    let user: User
    let mediaFilename: String
    let mediaURL: String?
    let thumbnailFilename: String?
    let thumbnailURL: String?
    let mediaType: String // "image" or "video"
    let createdAt: String
    let expiresAt: String
    let viewed: Bool
    let viewCount: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
        case mediaFilename
        case mediaURL
        case thumbnailFilename
        case thumbnailURL
        case mediaType
        case createdAt
        case expiresAt
        case viewed
        case viewCount
    }
    
    var isImage: Bool { mediaType == "image" }
    var isVideo: Bool { mediaType == "video" }
    
    /// Resolves the full media URL, preferring the server-provided URL and falling back to local construction.
    var resolvedMediaURL: URL? {
        if let urlString = mediaURL, !urlString.isEmpty,
           let url = URL(string: urlString) {
            return url
        }
        return MediaURL.url(userID: user.id, filename: mediaFilename)
    }
    
    /// Resolves the full thumbnail URL, preferring the server-provided URL and falling back to local construction.
    var resolvedThumbnailURL: URL? {
        if let urlString = thumbnailURL, !urlString.isEmpty,
           let url = URL(string: urlString) {
            return url
        }
        if let filename = thumbnailFilename, !filename.isEmpty {
            return MediaURL.url(userID: user.id, filename: filename)
        }
        return nil
    }
}
