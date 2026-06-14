//
//  StoriesTrayView.swift
//  ImageCircle
//
//  Horizontal tray of story circles with viewed/unviewed ring styling.
//

import SwiftUI

struct StoriesTrayView: View {
    let stories: [Story]
    let onStorySelected: (Story) -> Void
    
    /// Deduplicates stories by user so each friend appears once in the tray.
    private var uniqueUserStories: [Story] {
        var seen = Set<Int>()
        return stories.filter { story in
            if seen.contains(story.user.id) { return false }
            seen.insert(story.user.id)
            return true
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(uniqueUserStories) { story in
                    StoryCircle(story: story) {
                        onStorySelected(story)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}

struct StoryCircle: View {
    let story: Story
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(unviewedGradient, lineWidth: story.viewed ? 0 : 3)
                        .frame(width: 60, height: 60)
                    
                    placeholderAvatar(name: story.user.username)
                        .frame(width: 50, height: 50)
                }
                
                Text(story.user.username.prefix(8))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(story.viewed ? "Viewed" : "Unviewed") story from \(story.user.username)")
    }
    
    private var unviewedGradient: LinearGradient {
        LinearGradient(
            colors: [Color.pink, Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
