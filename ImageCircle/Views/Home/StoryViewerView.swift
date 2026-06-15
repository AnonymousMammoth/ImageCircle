//
//  StoryViewerView.swift
//  ImageCircle
//
//  Full-screen ephemeral story viewer with progress, gestures, and auto-advance.
//

import SwiftUI
import AVKit
import Combine
import Kingfisher

struct StoryViewerView: View {
    let stories: [Story]
    @Binding var isPresented: Bool
    @State private var currentIndex: Int
    @State private var progress: CGFloat = 0
    @State private var isPaused = false
    @State private var dragOffset: CGSize = .zero
    @State private var viewedIds = Set<Int>()
    @State private var photoTimer: Timer?
    @State private var viewMarkingTask: Task<Void, Never>?
    @State private var photoStartTime: Date?
    @State private var photoElapsedBeforePause: CGFloat = 0
    @State private var isImageLoaded = false
    @State private var loadError: Error?
    
    @StateObject private var videoState = VideoPlayerState()
    
    private let storyDuration: CGFloat = 5.0
    
    init(stories: [Story], startIndex: Int, isPresented: Binding<Bool>) {
        self.stories = stories
        self._currentIndex = State(initialValue: startIndex)
        self._isPresented = isPresented
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            content
                .opacity(1 - abs(dragOffset.height) / 400.0)
                .offset(y: dragOffset.height)
            
            overlayControls
        }
        .gesture(dragGesture)
        .onAppear {
            preloadStories()
            setupCurrentStory()
        }
        .onDisappear {
            invalidatePhotoTimer()
            viewMarkingTask?.cancel()
            videoState.reset()
        }
        .onChange(of: currentIndex) { _, _ in
            progress = 0
            isImageLoaded = false
            loadError = nil
            setupCurrentStory()
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                pauseCurrentStory()
            } else {
                resumeCurrentStory()
            }
        }
        .onChange(of: videoState.didFinish) { _, finished in
            if finished {
                videoState.didFinish = false
                nextStory()
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let story = stories[safe: currentIndex] {
            if story.isImage {
                if let url = story.resolvedMediaURL {
                    KFImage(url)
                        .resizable()
                        .placeholder { loadingPlaceholder }
                        .onSuccess { _ in
                            Task { @MainActor in
                                isImageLoaded = true
                                if !isPaused { resumePhotoTimer() }
                            }
                        }
                        .onFailure { error in
                            Task { @MainActor in
                                loadError = error
                            }
                        }
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    errorPlaceholder(message: "Invalid story URL")
                }
            } else if story.isVideo {
                if let url = story.resolvedMediaURL {
                    VideoPlayer(player: videoState.player)
                        .id("story-\(story.id)-\(url.absoluteString)")
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(videoState.player == nil ? loadingPlaceholder : nil)
                } else {
                    errorPlaceholder(message: "Invalid story URL")
                }
            } else {
                errorPlaceholder(message: "Unknown story type")
            }
        } else {
            Color.black
        }
    }
    
    private var loadingPlaceholder: some View {
        ZStack {
            Color.black
            ProgressView()
                .scaleEffect(1.5)
                .tint(.white)
        }
    }
    
    private func errorPlaceholder(message: String) -> some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(message)
                    .foregroundStyle(.white)
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
    
    private var overlayControls: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                progressBar
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.horizontal, 12)
                
                HStack {
                    tapZone(width: geo.size.width * 0.33, action: { previousStory() }, label: "Previous story")
                    tapZone(width: geo.size.width * 0.67, action: { nextStory() }, label: "Next story")
                }
                .frame(maxHeight: .infinity)
                
                VStack {
                    HStack {
                        closeButton
                        Spacer()
                    }
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.horizontal, 12)
                    
                    Spacer()
                    
                    if let story = stories[safe: currentIndex] {
                        HStack(spacing: 10) {
                            avatarView(for: story.user)
                                .frame(width: 36, height: 36)
                            Text(story.user.username)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .shadow(radius: 4)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                    }
                }
            }
        }
    }
    
    private var closeButton: some View {
        Button(action: { isPresented = false }) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .accessibilityLabel("Close stories")
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
                    .clipShape(Circle())
            } else {
                placeholderAvatar(name: user.username)
            }
        }
    }
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<stories.count, id: \.self) { index in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.3))
                        
                        if index < currentIndex {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                        } else if index == currentIndex {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                }
                .frame(height: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }
    
    private func tapZone(width: CGFloat, action: @escaping () -> Void, label: String) -> some View {
        Color.clear
            .frame(width: width)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.3, pressing: { pressing in
                isPaused = pressing
            }, perform: {})
            .accessibilityLabel(label)
            .accessibilityHint("Double tap and hold to pause")
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation
                    isPaused = true
                }
            }
            .onEnded { value in
                isPaused = false
                if value.translation.height > 120 {
                    withAnimation(.easeOut) {
                        isPresented = false
                    }
                } else {
                    withAnimation { dragOffset = .zero }
                }
            }
    }
    
    private func setupCurrentStory() {
        guard let story = stories[safe: currentIndex] else {
            isPresented = false
            return
        }
        
        invalidatePhotoTimer()
        viewMarkingTask?.cancel()
        markViewed(story)
        
        if story.isVideo, let url = story.resolvedMediaURL {
            videoState.reset()
            videoState.load(url: url)
        } else {
            videoState.reset()
            progress = 0
            photoElapsedBeforePause = 0
            photoStartTime = nil
            // Don't start timer until image finishes loading (handled in onSuccess).
        }
        
        preloadStories()
    }
    
    private func pauseCurrentStory() {
        invalidatePhotoTimer()
        videoState.pause()
        if let startTime = photoStartTime {
            photoElapsedBeforePause += CGFloat(Date().timeIntervalSince(startTime))
            photoStartTime = nil
        }
    }
    
    private func resumeCurrentStory() {
        if let story = stories[safe: currentIndex] {
            if story.isVideo {
                videoState.play()
            } else if isImageLoaded {
                resumePhotoTimer()
            }
        }
    }
    
    private func startPhotoTimer() {
        invalidatePhotoTimer()
        photoStartTime = Date()
        photoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard !isPaused else { return }
            let elapsed = photoElapsedBeforePause + CGFloat(Date().timeIntervalSince(photoStartTime ?? Date()))
            progress = min(elapsed / storyDuration, 1.0)
            if elapsed >= storyDuration {
                timer.invalidate()
                photoTimer = nil
                nextStory()
            }
        }
    }
    
    private func resumePhotoTimer() {
        startPhotoTimer()
    }
    
    private func invalidatePhotoTimer() {
        photoTimer?.invalidate()
        photoTimer = nil
        if let startTime = photoStartTime {
            photoElapsedBeforePause += CGFloat(Date().timeIntervalSince(startTime))
            photoStartTime = nil
        }
    }
    
    private func markViewed(_ story: Story) {
        guard !viewedIds.contains(story.id), !story.viewed else { return }
        viewedIds.insert(story.id)
        viewMarkingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled,
                      currentIndex < stories.count,
                      stories[currentIndex].id == story.id else { return }
                try? await APIClient.shared.markStoryViewed(id: story.id)
            } catch {
                // Cancelled or sleep failed; ignore.
            }
        }
    }
    
    private func nextStory() {
        invalidatePhotoTimer()
        if currentIndex < stories.count - 1 {
            currentIndex += 1
        } else {
            isPresented = false
        }
    }
    
    private func previousStory() {
        invalidatePhotoTimer()
        if currentIndex > 0 {
            currentIndex -= 1
        } else {
            // Restart current story from beginning.
            progress = 0
            photoElapsedBeforePause = 0
            setupCurrentStory()
        }
    }
    
    private func preloadStories() {
        let end = min(currentIndex + 4, stories.count)
        let urls = stories[currentIndex..<end].compactMap { story in
            story.resolvedMediaURL
        }
        ImagePrefetcher(urls: urls).start()
    }
}

// MARK: - Safe Index

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Video Player State

final class VideoPlayerState: ObservableObject {
    @Published var player: AVPlayer?
    @Published var didFinish = false
    private var finishedObserver: NSObjectProtocol?
    
    func load(url: URL) {
        reset()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        self.player = player
        
        finishedObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.didFinish = true
        }
        
        player.play()
    }
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func reset() {
        player?.pause()
        player = nil
        didFinish = false
        if let observer = finishedObserver {
            NotificationCenter.default.removeObserver(observer)
            finishedObserver = nil
        }
    }
}
