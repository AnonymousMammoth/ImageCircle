//
//  Post.swift
//  ImageCircle
//
//  Feed post model matching the backend API contract.
//

import Foundation

struct Post: Codable, Identifiable, Hashable {
    let id: Int
    let user: User
    let caption: String?
    let mediaFilename: String?
    let thumbnailFilename: String?
    let createdAt: String
    let likesCount: Int
    let commentsCount: Int
    let hasLiked: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
        case caption
        case mediaFilename = "media_filename"
        case thumbnailFilename = "thumbnail_filename"
        case createdAt = "created_at"
        case likesCount = "likes_count"
        case commentsCount = "comments_count"
        case hasLiked = "has_liked"
    }
    
    /// A post is considered a text-only post when it has no media filename.
    var isTextOnly: Bool { mediaFilename == nil || mediaFilename?.isEmpty == true }
}
