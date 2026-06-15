//
//  Report.swift
//  ImageCircle
//
//  Report and block models matching the backend API contract.
//

import Foundation

enum ReportTargetType: String {
    case post = "post"
    case story = "story"
    case user = "user"
}

struct ReportResponse: Codable {
    let id: Int?
    let status: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case createdAt = "created_at"
    }
}

struct BlockedUsersResponse: Codable {
    let blockedUserIDs: [Int]

    enum CodingKeys: String, CodingKey {
        case blockedUserIDs = "blocked_user_ids"
    }
}
