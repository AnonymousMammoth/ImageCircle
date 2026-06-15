//
//  StoriesTrayView.swift
//  ImageCircle
//
//  Horizontal tray of story circles with viewed/unviewed ring styling.
//

import SwiftUI
import Kingfisher

struct StoriesTrayView: View {
    let stories: [Story]
    let onStorySelected: (Story) -> Void
    var onAddStoryTapped: (() -> Void)? = nil
    var showAddButton: Bool = false
    
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
                if showAddButton {
                    AddStoryCircle(action: { onAddStoryTapped?() })
                }
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

struct AddStoryCircle: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.pink, lineWidth: 3)
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 50, height: 50)
                }
                
                Text("Add Story")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add story")
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
                    
                    avatarView(for: story.user)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
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
    
    private func avatarView(for user: User) -> some View {
        Group {
            if let filename = user.avatarFilename,
               !filename.isEmpty,
               let url = MediaURL.url(userID: user.id, filename: filename) {
                KFImage(url)
                    .resizable()
                    .placeholder { placeholderAvatar(name: user.username) }
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderAvatar(name: user.username)
            }
        }
    }
}
