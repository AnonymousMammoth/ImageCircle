//
//  StoryViewerView.swift
//  ImageCircle
//
//  Full-screen ephemeral story viewer with Instagram-style grouping and gestures.
//

import SwiftUI
import AVKit
import AVFoundation
import Combine
import Kingfisher

struct StoryViewerView: View {
    @State var groups: [StoryGroup]
    @Binding var isPresented: Bool
    let onStoriesChanged: () -> Void
    
    @State private var currentGroupIndex: Int
    @State private var currentStoryIndex: Int
    @State private var progress: CGFloat = 0
    @State private var isPaused = false
    @State private var dragOffset: CGSize = .zero
    @State private var viewedIds = Set<Int>()
    @State private var viewMarkingTask: Task<Void, Never>?
    @State private var photoStartTime: Date?
    @State private var photoElapsedBeforePause: CGFloat = 0
    @State private var isImageLoaded = false
    @State private var loadError: Error?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showReportSheet = false
    @State private var photoTimerCancellable: AnyCancellable?

    @StateObject private var videoState = VideoPlayerState()
    
    private let storyDuration: CGFloat = 5.0
    
    init(groups: [StoryGroup], groupIndex: Int, storyIndex: Int, isPresented: Binding<Bool>, onStoriesChanged: @escaping () -> Void = {}) {
        self._groups = State(initialValue: groups)
        self._currentGroupIndex = State(initialValue: groupIndex)
        self._currentStoryIndex = State(initialValue: storyIndex)
        self._isPresented = isPresented
        self.onStoriesChanged = onStoriesChanged
    }
    
    private var currentStory: Story? {
        groups[safe: currentGroupIndex]?.stories[safe: currentStoryIndex]
    }
    
    private var currentGroup: StoryGroup? {
        groups[safe: currentGroupIndex]
    }

    private func isCurrentUser(_ story: Story) -> Bool {
        story.user.id == AuthManager.shared.currentUser?.id
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            content
                .opacity(1 - abs(dragOffset.height) / 400.0)
                .offset(y: dragOffset.height)
            
            overlayControls
            
            if isDeleting {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .overlay(
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Deleting...")
                                .foregroundStyle(.white)
                        }
                    )
            }
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
        .onChange(of: currentStoryIndex) { _, _ in
            resetStoryState()
            setupCurrentStory()
        }
        .onChange(of: currentGroupIndex) { _, _ in
            resetStoryState()
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
        .alert("Delete Story?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteCurrentStory()
            }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showReportSheet) {
            if let story = currentStory {
                ReportSheetView(
                    targetType: .story,
                    targetID: story.id,
                    reportedUserID: story.user.id,
                    reportedUserName: story.user.username
                )
            }
        }
    }
    
    private func resetStoryState() {
        progress = 0
        isImageLoaded = false
        loadError = nil
    }
    
    @ViewBuilder
    private var content: some View {
        if let story = currentStory {
            if loadError != nil {
                errorPlaceholder(message: "Could not load story")
            } else if story.isImage {
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
                if videoState.loadError != nil {
                    errorPlaceholder(message: "Could not load video")
                } else if let url = story.resolvedMediaURL {
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
            errorPlaceholder(message: "Story unavailable")
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
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundStyle(.white)
                Text(message)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Close") { isPresented = false }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
            }
        }
    }
    
    private var overlayControls: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                progressBar
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.horizontal, 12)
                
                bottomInfo
                    .padding(.bottom, geo.safeAreaInsets.bottom + 24)
                
                tapZones(width: geo.size.width, safeAreaTop: geo.safeAreaInsets.top)
                
                topBar
                    .padding(.top, geo.safeAreaInsets.top + 16)
                    .padding(.horizontal, 12)
            }
        }
    }
    
    private var bottomInfo: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                if let user = currentGroup?.user {
                    avatarView(for: user)
                        .frame(width: 36, height: 36)
                    Text(user.username)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 4)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var topBar: some View {
        HStack {
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
            }
            .accessibilityLabel("Close stories")
            .allowsHitTesting(true)

            Spacer()
                .allowsHitTesting(false)

            if let story = currentStory, (!isCurrentUser(story) || AuthManager.shared.canDelete(contentUserID: story.user.id)) {
                Menu {
                    if !isCurrentUser(story) {
                        Button {
                            showReportSheet = true
                        } label: {
                            Label("Report...", systemImage: "exclamationmark.bubble")
                        }
                    }
                    if AuthManager.shared.canDelete(contentUserID: story.user.id) {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete Story", systemImage: "trash")
                        }
                        .disabled(isDeleting)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .allowsHitTesting(true)
            }
        }
    }
    
    private func tapZones(width: CGFloat, safeAreaTop: CGFloat) -> some View {
        HStack(spacing: 0) {
            tapZone(width: width * 0.33, action: { previousStory() }, label: "Previous story")
            tapZone(width: width * 0.67, action: { nextStory() }, label: "Next story")
        }
        .padding(.top, safeAreaTop + 80)
        .frame(maxHeight: .infinity)
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
    }
    
    private var progressBar: some View {
        HStack(spacing: 4) {
            if let group = currentGroup {
                ForEach(0..<group.stories.count, id: \.self) { index in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.3))
                            
                            if index < currentStoryIndex {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white)
                            } else if index == currentStoryIndex {
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
    }
    
    private func avatarView(for user: User) -> some View {
        AvatarImage(user: user, size: 36)
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
        guard currentStory != nil else {
            isPresented = false
            return
        }
        
        invalidatePhotoTimer()
        viewMarkingTask?.cancel()
        if let story = currentStory {
            markViewed(story)
        }
        
        if let story = currentStory, story.isVideo, let url = story.resolvedMediaURL {
            videoState.reset()
            videoState.load(url: url)
        } else {
            videoState.reset()
            progress = 0
            photoElapsedBeforePause = 0
            photoStartTime = nil
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
        if let story = currentStory, story.isVideo {
            videoState.play()
        } else if isImageLoaded {
            resumePhotoTimer()
        }
    }
    
    private func startPhotoTimer() {
        invalidatePhotoTimer()
        photoStartTime = Date()
        photoTimerCancellable = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                guard !isPaused else { return }
                let elapsed = photoElapsedBeforePause + CGFloat(Date().timeIntervalSince(photoStartTime ?? Date()))
                progress = min(elapsed / storyDuration, 1.0)
                if elapsed >= storyDuration {
                    invalidatePhotoTimer()
                    nextStory()
                }
            }
    }
    
    private func resumePhotoTimer() {
        startPhotoTimer()
    }
    
    private func invalidatePhotoTimer() {
        photoTimerCancellable?.cancel()
        photoTimerCancellable = nil
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
                      let current = currentStory,
                      current.id == story.id else { return }
                try? await APIClient.shared.markStoryViewed(id: story.id)
            } catch {
                // Cancelled or sleep failed; ignore.
            }
        }
    }
    
    private func nextStory() {
        invalidatePhotoTimer()
        guard let group = currentGroup else {
            isPresented = false
            return
        }
        if currentStoryIndex < group.stories.count - 1 {
            currentStoryIndex += 1
        } else if currentGroupIndex < groups.count - 1 {
            currentGroupIndex += 1
            currentStoryIndex = 0
        } else {
            isPresented = false
        }
    }
    
    private func previousStory() {
        invalidatePhotoTimer()
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
        } else if currentGroupIndex > 0 {
            currentGroupIndex -= 1
            currentStoryIndex = max(groups[currentGroupIndex].stories.count - 1, 0)
        } else {
            progress = 0
            photoElapsedBeforePause = 0
            setupCurrentStory()
        }
    }
    
    private func deleteCurrentStory() {
        guard let story = currentStory else { return }
        isDeleting = true
        Task {
            do {
                try await APIClient.shared.deleteStory(id: story.id)
                await MainActor.run {
                    removeStory(story)
                    isDeleting = false
                    onStoriesChanged()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    loadError = error
                }
            }
        }
    }
    
    private func removeStory(_ story: Story) {
        var updatedGroups = groups
        guard updatedGroups.indices.contains(currentGroupIndex) else { return }
        updatedGroups[currentGroupIndex].stories.removeAll { $0.id == story.id }
        if updatedGroups[currentGroupIndex].stories.isEmpty {
            updatedGroups.remove(at: currentGroupIndex)
            if updatedGroups.isEmpty {
                isPresented = false
                return
            }
            if currentGroupIndex >= updatedGroups.count {
                currentGroupIndex = updatedGroups.count - 1
            }
            currentStoryIndex = 0
        } else {
            if currentStoryIndex >= updatedGroups[currentGroupIndex].stories.count {
                currentStoryIndex = updatedGroups[currentGroupIndex].stories.count - 1
            }
        }
        groups = updatedGroups
        resetStoryState()
        setupCurrentStory()
    }
    
    private func preloadStories() {
        let flatStories = groups.flatMap { $0.stories }
        guard let currentFlatIndex = flatStories.firstIndex(where: { $0.id == currentStory?.id }) else { return }
        let end = min(currentFlatIndex + 4, flatStories.count)
        let urls = flatStories[currentFlatIndex..<end].compactMap { $0.resolvedMediaURL }
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
    @Published var loadError: Error?
    private var finishedObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var downloadTask: Task<Void, Never>?
    private var localFileURL: URL?

    func load(url: URL) {
        reset()

        downloadTask = Task {
            do {
                let localURL = try await downloadMedia(url: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.localFileURL = localURL
                    let item = AVPlayerItem(url: localURL)
                    let player = AVPlayer(playerItem: item)
                    player.isMuted = false
                    self.player = player

                    self.finishedObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { [weak self] _ in
                        self?.didFinish = true
                    }

                    self.failedObserver = NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemFailedToPlayToEndTime,
                        object: item,
                        queue: .main
                    ) { [weak self] _ in
                        self?.loadError = URLError(.cannotLoadFromNetwork)
                    }

                    player.play()
                }
            } catch {
                await MainActor.run {
                    self.loadError = error
                }
            }
        }
    }

    private func downloadMedia(url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = APIClient.shared.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (tempURL, response) = try await APIClient.shared.session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let filename = UUID().uuidString + "-" + url.lastPathComponent
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func reset() {
        downloadTask?.cancel()
        downloadTask = nil
        player?.pause()
        player = nil
        didFinish = false
        loadError = nil
        if let observer = finishedObserver {
            NotificationCenter.default.removeObserver(observer)
            finishedObserver = nil
        }
        if let observer = failedObserver {
            NotificationCenter.default.removeObserver(observer)
            failedObserver = nil
        }
        if let localFileURL = localFileURL {
            try? FileManager.default.removeItem(at: localFileURL)
            self.localFileURL = nil
        }
    }
}
