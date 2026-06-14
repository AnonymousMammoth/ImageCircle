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
        case mediaFilename
        case thumbnailFilename
        case mediaType
        case createdAt
        case expiresAt
        case viewed
    }
    
    var isImage: Bool { mediaType == "image" }
    var isVideo: Bool { mediaType == "video" }
}
