//
//  User.swift
//  ImageCircle
//
//  User model matching the backend API contract.
//  Backend uses snake_case; Swift uses camelCase.
//

import Foundation

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let username: String
    let displayName: String
    let isAdmin: Bool
    let passwordChangeRequired: Bool
    let avatarFilename: String?
    let avatarURL: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case isAdmin
        case passwordChangeRequired
        case avatarFilename
        case avatarURL = "avatarUrl"
        case createdAt
    }
}
