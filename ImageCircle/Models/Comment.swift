//
//  Comment.swift
//  ImageCircle
//
//  Comment model matching the backend API contract.
//

import Foundation

struct Comment: Codable, Identifiable, Hashable {
    let id: Int
    let user: User
    let text: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case user
        case text
        case createdAt
    }
}
