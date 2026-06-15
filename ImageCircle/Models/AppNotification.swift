//
//  AppNotification.swift
//  ImageCircle
//
//  In-app notification returned by GET /api/notifications.
//

import Foundation

struct AppNotification: Codable, Identifiable {
    let id: String
    let type: String
    let actor: NotificationActor
    let post: NotificationPost
    let comment: NotificationComment?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case actor
        case post
        case comment
        case createdAt = "created_at"
    }

    var isLike: Bool { type == "like" }
    var isComment: Bool { type == "comment" }
    var isMentionPost: Bool { type == "mention_post" }
    var isMentionComment: Bool { type == "mention_comment" }
}

/// Minimal, privacy-safe actor used in notification payloads.
struct NotificationActor: Codable, Identifiable {
    let id: Int
    let username: String
    let displayName: String
    let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
    }
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
        case createdAt = "created_at"
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
        case createdAt = "created_at"
    }
}

