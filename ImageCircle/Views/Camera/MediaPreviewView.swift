//
//  MediaPreviewView.swift
//  ImageCircle
//
//  Preview captured media, compress it, and upload as a post or story.
//

import SwiftUI
import AVKit
import AVFoundation
import Photos

struct MediaPreviewView: View {
    let image: UIImage?
    let videoURL: URL?
    let mode: CaptureMode
    let onComplete: () -> Void
    
    @State private var caption: String = ""
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showCancelConfirm = false
    @State private var retryAsFeed: Bool = false
    @State private var videoPlayer: AVPlayer?
    @State private var uploadTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    mediaDisplay
                    
                    if mode == .photo {
                        TextField("Write a caption...", text: $caption, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...3)
                            .padding()
                            .background(Color(.systemBackground))
                    }
                    
                    actionButtons
                        .padding()
                        .background(Color(.systemBackground))
                }
                
                if isUploading {
                    uploadOverlay
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if isUploading {
                            showCancelConfirm = true
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isUploading)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("Try Again") { startUpload(asFeed: retryAsFeed) }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(errorMessage ?? "Upload failed.")
            }
            .confirmationDialog("Cancel upload?", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                Button("Cancel Upload", role: .destructive) {
                    uploadTask?.cancel()
                    dismiss()
                }
                Button("Keep Uploading", role: .cancel) {}
            }
            .onAppear {
                if let videoURL = videoURL {
                    videoPlayer = AVPlayer(url: videoURL)
                    videoPlayer?.play()
                }
            }
            .onDisappear {
                videoPlayer?.pause()
                videoPlayer = nil
                uploadTask?.cancel()
            }
        }
    }
    
    @ViewBuilder
    private var mediaDisplay: some View {
        if let image = image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let player = videoPlayer {
            VideoPlayer(player: player)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if mode == .photo {
                Button(action: { startUpload(asFeed: true) }) {
                    HStack {
                        Image(systemName: "photo")
                        Text("Post to Feed")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.pink)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            Button(action: { startUpload(asFeed: false) }) {
                HStack {
                    Image(systemName: mode == .photo ? "circle.hexagongrid" : "video.bubble")
                    Text(mode == .photo ? "Add to Story" : "Add Video to Story")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(mode == .photo ? Color.pink.opacity(0.15) : Color.pink)
                .foregroundStyle(mode == .photo ? .pink : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    private var uploadOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView(value: uploadProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .pink))
                    .frame(width: 200)
                Text("Uploading... \(Int(uploadProgress * 100))%")
                    .foregroundStyle(.white)
                    .font(.subheadline)
            }
        }
    }
    
    private func startUpload(asFeed: Bool) {
        guard !isUploading else { return }
        retryAsFeed = asFeed
        isUploading = true
        uploadProgress = 0
        
        uploadTask = Task {
            do {
                if asFeed, let image = image {
                    uploadProgress = 0.1
                    let data = try await compressPhoto(image)
                    let thumbData = squareThumbnailData(from: image)
                    uploadProgress = 0.2
                    _ = try await APIClient.shared.createPost(
                        caption: caption,
                        imageData: data,
                        thumbnailData: thumbData
                    ) { progress in
                        Task { @MainActor in
                            self.uploadProgress = 0.2 + 0.8 * progress
                        }
                    }
                } else if let image = image {
                    uploadProgress = 0.1
                    let data = try await compressPhoto(image)
                    uploadProgress = 0.2
                    _ = try await APIClient.shared.createStory(mediaType: "image", mediaData: data, mediaFilename: "story.jpg") { progress in
                        Task { @MainActor in
                            self.uploadProgress = 0.2 + 0.8 * progress
                        }
                    }
                } else if let videoURL = videoURL {
                    uploadProgress = 0.1
                    let (videoData, thumbnailData) = try await compressVideo(videoURL)
                    uploadProgress = 0.2
                    _ = try await APIClient.shared.createStory(
                        mediaType: "video",
                        mediaData: videoData,
                        mediaFilename: "story.mp4",
                        thumbnailData: thumbnailData,
                        thumbnailFilename: "thumb.jpg"
                    ) { progress in
                        Task { @MainActor in
                            self.uploadProgress = 0.2 + 0.8 * progress
                        }
                    }
                }
                uploadProgress = 1.0
                isUploading = false
                onComplete()
                dismiss()
            } catch {
                isUploading = false
                if Task.isCancelled || error is CancellationError {
                    // User cancelled; don't show an error.
                    dismiss()
                    return
                }
                if let apiError = error as? APIError, apiError == .cancelled {
                    dismiss()
                    return
                }
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
    
    /// Creates a center-cropped square JPEG thumbnail, max 512px.
    private func squareThumbnailData(from image: UIImage, maxPixelSize: CGFloat = 512) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let minDim = min(width, height)
        
        let cropRect = CGRect(
            x: (width - minDim) / 2,
            y: (height - minDim) / 2,
            width: minDim,
            height: minDim
        )
        
        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        
        let scale = min(1.0, maxPixelSize / minDim)
        let newSize = CGSize(width: minDim * scale, height: minDim * scale)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            UIImage(cgImage: croppedCG, scale: 1.0, orientation: image.imageOrientation)
                .draw(in: CGRect(origin: .zero, size: newSize))
        }
        
        return resized.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - Compression Helpers

/// Resizes photo so longest edge <= 2048, JPEG quality 0.85, strips GPS.
func compressPhoto(_ image: UIImage) async throws -> Data {
    let maxDimension: CGFloat = 2048
    let size = image.size
    let scale = min(1.0, maxDimension / max(size.width, size.height))
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    
    return try await Task.detached(priority: .userInitiated) {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else {
            throw APIError.invalidResponse
        }
        return data
    }.value
}

/// Exports video to H.264/AAC MP4, 1080p max, and generates a thumbnail.
func compressVideo(_ url: URL) async throws -> (Data, Data?) {
    let asset = AVAsset(url: url)
    let preset = AVAssetExportPreset1920x1080
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
        throw APIError.invalidResponse
    }
    
    let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("exported_\(UUID().uuidString).mp4")
    try? FileManager.default.removeItem(at: outputURL)
    
    session.outputFileType = .mp4
    session.outputURL = outputURL
    session.shouldOptimizeForNetworkUse = true
    
    await session.export()
    
    guard session.status == .completed else {
        throw APIError.networkFailure(session.error ?? NSError(domain: "export", code: -1))
    }
    
    let videoData = try Data(contentsOf: outputURL)
    let thumbnailData = try? await generateThumbnail(for: outputURL)
    return (videoData, thumbnailData)
}

/// Generates a JPEG thumbnail at 1 second, max 512px edge.
func generateThumbnail(for videoURL: URL) async throws -> Data {
    let asset = AVAsset(url: videoURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 512, height: 512)
    
    let time = CMTime(seconds: 1.0, preferredTimescale: 600)
    let result = try await generator.image(at: time)
    let uiImage = UIImage(cgImage: result.image)
    guard let data = uiImage.jpegData(compressionQuality: 0.85) else { throw APIError.invalidResponse }
    return data
}
