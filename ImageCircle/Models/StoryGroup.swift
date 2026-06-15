//
//  StoryGroup.swift
//  ImageCircle
//
//  Groups active stories by user so the viewer can behave like Instagram stories.
//

import Foundation

struct StoryGroup: Identifiable {
    let user: User
    var stories: [Story]
    
    var id: Int { user.id }
    
    var isViewed: Bool {
        stories.allSatisfy { $0.viewed }
    }
}

extension Array where Element == Story {
    /// Groups stories by user, preserving descending order within each group.
    func groupedByUser() -> [StoryGroup] {
        let grouped = Dictionary(grouping: self) { $0.user.id }
        return grouped
            .values
            .map { stories in
                let sorted = stories.sorted { $0.createdAt > $1.createdAt }
                return StoryGroup(user: sorted[0].user, stories: sorted)
            }
            .sorted { lhs, rhs in
                lhs.stories[0].createdAt > rhs.stories[0].createdAt
            }
    }
}
