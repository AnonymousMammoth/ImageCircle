//
//  AppNotification.swift
//  ImageCircle
//
//  In-app notification returned by GET /api/notifications.
//

import Foundation

struct AppNotification: Codable, Identifiable {
    let id: Int
    let type: String
    let actor: User
    let post: NotificationPost
    let comment: NotificationComment?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case type
        case actor
        case post
        case comment
        case createdAt
    }
    
    var isLike: Bool { type == "like" }
    var isComment: Bool { type == "comment" }
}

/// Minimal post representation used in notification payloads.
struct NotificationPost: Codable, Identifiable {
    let id: Int
    let userId: Int
    let caption: String?
    let mediaURL: String?
    let thumbnailURL: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case caption
        case mediaURL = "media_url"
        case thumbnailURL = "thumbnail_url"
        case createdAt
    }
}

/// Minimal comment representation used in notification payloads.
struct NotificationComment: Codable, Identifiable {
    let id: Int
    let text: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
    }
}
