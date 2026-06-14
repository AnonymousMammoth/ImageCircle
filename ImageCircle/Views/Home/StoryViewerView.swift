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
    
    @StateObject private var videoState = VideoPlayerState()
    
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
        .onChange(of: currentIndex) {
            progress = 0
            setupCurrentStory()
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                invalidatePhotoTimer()
                videoState.pause()
            } else {
                if let story = stories[safe: currentIndex], story.isImage {
                    resumePhotoTimer()
                }
                videoState.play()
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
            if story.isImage, let url = MediaURL.url(userID: story.user.id, filename: story.mediaFilename) {
                KFImage(url)
                    .resizable()
                    .placeholder { Color.black }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if story.isVideo {
                VideoPlayer(player: videoState.player)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.black
            }
        } else {
            Color.black
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
                
                if let story = stories[safe: currentIndex] {
                    VStack {
                        Spacer()
                        HStack {
                            placeholderAvatar(name: story.user.username)
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
        
        if story.isVideo, let url = MediaURL.url(userID: story.user.id, filename: story.mediaFilename) {
            videoState.load(url: url)
        } else {
            videoState.reset()
            startPhotoTimer()
        }
        
        preloadStories()
    }
    
    private func startPhotoTimer() {
        invalidatePhotoTimer()
        progress = 0
        let startTime = Date()
        photoTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            guard !isPaused else { return }
            let elapsed = CGFloat(Date().timeIntervalSince(startTime))
            progress = min(elapsed / 5.0, 1.0)
            if elapsed >= 5.0 {
                timer.invalidate()
                photoTimer = nil
                nextStory()
            }
        }
    }
    
    private func resumePhotoTimer() {
        // Re-start from current progress to keep simple behavior.
        startPhotoTimer()
    }
    
    private func invalidatePhotoTimer() {
        photoTimer?.invalidate()
        photoTimer = nil
    }
    
    private func markViewed(_ story: Story) {
        guard !viewedIds.contains(story.id), !story.viewed else { return }
        viewedIds.insert(story.id)
        viewMarkingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
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
        }
    }
    
    private func preloadStories() {
        let end = min(currentIndex + 4, stories.count)
        let urls = stories[currentIndex..<end].compactMap { story in
            MediaURL.url(userID: story.user.id, filename: story.mediaFilename)
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
