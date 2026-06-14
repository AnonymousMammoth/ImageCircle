//
//  FeedFilter.swift
//  ImageCircle
//
//  Home feed filter segments. The backend does not yet expose a filter parameter,
//  so filtering is performed client-side. Once the backend supports ?type=mixed|images|text,
//  update APIClient.fetchFeed(filter:) and remove local filtering.
//

import Foundation

enum FeedFilter: String, CaseIterable, Identifiable {
    case mixed = "Mixed"
    case images = "Images"
    case text = "Text"
    
    var id: String { rawValue }
    
    /// Returns true if the post should be visible under this filter.
    func includes(_ post: Post) -> Bool {
        switch self {
        case .mixed:
            return true
        case .images:
            return !post.isTextOnly
        case .text:
            return post.isTextOnly
        }
    }
}
