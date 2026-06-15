//
//  CameraView.swift
//  ImageCircle
//
//  Story-first camera with tap-to-photo, hold-to-video, and library picker.
//

import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import Combine

enum CaptureMode {
    case photo
    case video
    case text
}

struct CameraView: View {
    let onFinished: (Bool) -> Void
    
    @StateObject private var camera = CameraCaptureManager()
    @State private var isHoldingVideo = false
    @State private var videoProgress: CGFloat = 0
    @State private var selectedLibraryItem: PhotosPickerItem?
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showLibrary = false
    @Environment(\.dismiss) private var dismiss
    
    private let maxVideoDuration: CGFloat = 30
    private let videoTimerInterval: CGFloat = 0.05
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if camera.hasPermission {
                    cameraPreview
                    captureOverlay
                } else {
                    permissionPlaceholder
                }
                
                if camera.isRecording {
                    recordingIndicator
                }
            }
            .navigationTitle("Add Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        camera.stopSession()
                        onFinished(false)
                    }
                }
            }
            .onAppear {
                Task { await camera.checkPermissionAndSetup() }
            }
            .onDisappear {
                camera.stopSession()
            }
            .alert("Camera Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not access camera.")
            }
            .fullScreenCover(isPresented: Binding(
                get: { capturedImage != nil || capturedVideoURL != nil },
                set: { if !$0 { capturedImage = nil; capturedVideoURL = nil } }
            )) {
                if let image = capturedImage {
                    MediaPreviewView(
                        image: image,
                        videoURL: nil,
                        mode: .photo,
                        onComplete: { onFinished(true) }
                    )
                } else if let videoURL = capturedVideoURL {
                    MediaPreviewView(
                        image: nil,
                        videoURL: videoURL,
                        mode: .video,
                        onComplete: { onFinished(true) }
                    )
                }
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { image, videoURL in
                    if let image = image {
                        capturedImage = image
                    } else if let videoURL = videoURL {
                        capturedVideoURL = videoURL
                    }
                }
            }
            .onChange(of: camera.errorMessage) { _, message in
                if let message = message {
                    errorMessage = message
                    showError = true
                }
            }
        }
    }
    
    private var cameraPreview: some View {
        CameraPreviewView(session: camera.session)
            .ignoresSafeArea()
    }
    
    private var captureOverlay: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 24) {
                HStack(spacing: 40) {
                    Spacer()
                    
                    // Library button
                    Button(action: { showLibrary = true }) {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                            Text("Library")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                    }
                    
                    // Shutter button
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 82, height: 82)
                        
                        Circle()
                            .fill(isHoldingVideo ? Color.red : Color.white)
                            .frame(width: 70, height: 70)
                            .scaleEffect(isHoldingVideo ? 0.85 : 1.0)
                            .animation(.easeInOut(duration: 0.15), value: isHoldingVideo)
                        
                        if isHoldingVideo {
                            Circle()
                                .trim(from: 0, to: videoProgress)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 92, height: 92)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .contentShape(Circle())
                    .gesture(
                        LongPressGesture(minimumDuration: 0.3, maximumDistance: 40)
                            .onEnded { _ in
                                stopVideoRecording()
                            }
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onChanged { value in
                                switch value {
                                case .first(true):
                                    // Tap detected — take photo after a brief delay so a long press can win.
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                        if !isHoldingVideo && !camera.isRecording {
                                            capturePhoto()
                                        }
                                    }
                                case .second(true, _):
                                    // Long press detected — start video.
                                    if !camera.isRecording {
                                        startVideoRecording()
                                    }
                                default:
                                    break
                                }
                            }
                    )
                    
                    Spacer()
                }
                
                Text(isHoldingVideo ? "Recording..." : "Tap for photo • Hold for video")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.bottom, 40)
            .padding(.horizontal)
        }
    }
    
    private var recordingIndicator: some View {
        VStack {
            HStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                Text("REC")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            .padding(12)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
            .padding(.top, 60)
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var permissionPlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Camera access is required to create stories.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    private func capturePhoto() {
        Task {
            do {
                if let image = try await camera.capturePhoto() {
                    capturedImage = image
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func startVideoRecording() {
        isHoldingVideo = true
        videoProgress = 0
        Task {
            do {
                try await camera.startRecording()
                startVideoProgressTimer()
            } catch {
                isHoldingVideo = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func stopVideoRecording() {
        isHoldingVideo = false
        Task {
            if let url = await camera.stopRecording() {
                capturedVideoURL = url
            }
        }
    }
    
    private func startVideoProgressTimer() {
        var elapsed: CGFloat = 0
        Timer.scheduledTimer(withTimeInterval: videoTimerInterval, repeats: true) { timer in
            guard camera.isRecording else {
                timer.invalidate()
                return
            }
            elapsed += videoTimerInterval
            videoProgress = min(elapsed / maxVideoDuration, 1.0)
            if elapsed >= maxVideoDuration {
                timer.invalidate()
                stopVideoRecording()
            }
        }
    }
}

// MARK: - Camera Capture Manager

@MainActor
final class CameraCaptureManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    
    @Published var hasPermission = false
    @Published var isRecording = false
    @Published var errorMessage: String?
    
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoContinuation: CheckedContinuation<UIImage?, Error>?
    private var videoContinuation: CheckedContinuation<URL?, Never>?
    private var videoRecordingURL: URL?
    
    private let sessionQueue = DispatchQueue(label: "com.mattmarsh.imagecircle.camera.session")
    
    func checkPermissionAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            hasPermission = true
            await configureSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            hasPermission = granted
            if granted {
                await configureSession()
            }
        default:
            hasPermission = false
        }
        
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
    
    private func configureSession() async {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        session.sessionPreset = .high
        
        do {
            // Video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                throw NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Back camera not found"])
            }
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
            }
            
            // Audio input for video
            if let audioDevice = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
            
            // Photo output
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
            
            // Movie output
            movieOutput.maxRecordedDuration = CMTime(seconds: 30, preferredTimescale: 600)
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        } catch {
            self.errorMessage = error.localizedDescription
            return
        }
        
        startSession()
    }
    
    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
    
    func capturePhoto() async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera unavailable"]))
                    return
                }
                self.photoContinuation = continuation
                let settings = AVCapturePhotoSettings()
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
    }
    
    func startRecording() async throws {
        guard !isRecording else { return }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("story_\(UUID().uuidString)")
            .appendingPathExtension("mov")
        videoRecordingURL = url
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera unavailable"]))
                    return
                }
                if self.movieOutput.isRecording {
                    continuation.resume()
                    return
                }
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                DispatchQueue.main.async {
                    self.isRecording = true
                }
                continuation.resume()
            }
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return videoRecordingURL }
        
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.videoContinuation = continuation
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                } else {
                    continuation.resume(returning: self.videoRecordingURL)
                }
            }
        }
    }
}

extension CameraCaptureManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.photoContinuation?.resume(throwing: error)
                self.photoContinuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
                self.photoContinuation?.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not process photo"]))
                self.photoContinuation = nil
                return
            }
            self.photoContinuation?.resume(returning: image)
            self.photoContinuation = nil
        }
    }
}

extension CameraCaptureManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        Task { @MainActor in
            self.isRecording = false
            if let error = error {
                self.errorMessage = error.localizedDescription
                self.videoContinuation?.resume(returning: nil)
            } else {
                self.videoContinuation?.resume(returning: outputFileURL)
            }
            self.videoContinuation = nil
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.previewLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Library Picker

struct LibraryPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?, URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: LibraryPicker
        
        init(_ parent: LibraryPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            
            if let mediaType = info[.mediaType] as? String {
                if mediaType == UTType.image.identifier, let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                    parent.onComplete(image, nil)
                } else if mediaType == UTType.movie.identifier, let url = info[.mediaURL] as? URL {
                    parent.onComplete(nil, url)
                }
            }
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onComplete(nil, nil)
        }
    }
}
