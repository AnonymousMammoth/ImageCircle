//
//  StoriesTrayView.swift
//  ImageCircle
//
//  Horizontal tray of story circles with viewed/unviewed ring styling.
//

import SwiftUI
import Kingfisher

struct StoriesTrayView: View {
    let groups: [StoryGroup]
    let onStorySelected: (Int, Int) -> Void
    var onAddStoryTapped: (() -> Void)? = nil
    var showAddButton: Bool = false
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                if showAddButton {
                    AddStoryCircle(action: { onAddStoryTapped?() })
                }
                ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                    StoryCircle(group: group) {
                        onStorySelected(index, 0)
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
    let group: StoryGroup
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(unviewedGradient, lineWidth: group.isViewed ? 0 : 3)
                        .frame(width: 60, height: 60)
                    
                    avatarView(for: group.user)
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                }
                
                Text(group.user.username.prefix(8))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(group.isViewed ? "Viewed" : "Unviewed") story from \(group.user.username)")
    }
    
    private var unviewedGradient: LinearGradient {
        LinearGradient(
            colors: [Color.pink, Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private func avatarView(for user: User) -> some View {
        AvatarImage(user: user, size: 50)
    }
}
