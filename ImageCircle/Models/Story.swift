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
    let thumbnailFilename: String?
    let mediaType: String // "image" or "video"
    let createdAt: String
    let expiresAt: String
    let viewed: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
        case mediaFilename = "media_filename"
        case thumbnailFilename = "thumbnail_filename"
        case mediaType = "media_type"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case viewed
    }
    
    var isImage: Bool { mediaType == "image" }
    var isVideo: Bool { mediaType == "video" }
}
