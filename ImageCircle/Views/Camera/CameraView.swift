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
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var showLibrary = false
    @State private var didPublish = false
    @State private var pendingPhotoWorkItem: DispatchWorkItem?
    @Environment(\.dismiss) private var dismiss
    
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { camera.switchCamera() }) {
                        Image(systemName: "camera.rotate")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .disabled(camera.isRecording)
                    .accessibilityLabel("Switch camera")
                }
            }
            .onAppear {
                Task { await camera.checkPermissionAndSetup() }
            }
            .onDisappear {
                cancelPendingPhotoCapture()
                camera.stopSession()
            }
            .alert("Camera Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not access camera.")
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { capturedImage != nil || capturedVideoURL != nil },
                    set: { if !$0 { capturedImage = nil; capturedVideoURL = nil } }
                ),
                onDismiss: {
                    if didPublish {
                        didPublish = false
                        onFinished(true)
                    }
                }
            ) {
                if let image = capturedImage {
                    MediaPreviewView(
                        image: image,
                        videoURL: nil,
                        mode: .photo,
                        onComplete: { didPublish = true }
                    )
                } else if let videoURL = capturedVideoURL {
                    MediaPreviewView(
                        image: nil,
                        videoURL: videoURL,
                        mode: .video,
                        onComplete: { didPublish = true }
                    )
                }
            }
            .sheet(isPresented: $showLibrary, onDismiss: { showLibrary = false }) {
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
                    camera.clearError()
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
                        
                        if camera.isRecording {
                            Circle()
                                .trim(from: 0, to: camera.recordingProgress)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .frame(width: 92, height: 92)
                                .rotationEffect(.degrees(-90))
                        }
                    }
                    .contentShape(Circle())
                    .onLongPressGesture(
                        minimumDuration: 0.3,
                        maximumDistance: 40,
                        pressing: { pressing in
                            if pressing {
                                // Touch down: schedule a photo capture after the long-press window.
                                schedulePhotoCapture()
                            } else {
                                // Touch up / cancelled.
                                if camera.isRecording || isHoldingVideo {
                                    stopVideoRecording()
                                } else if let item = pendingPhotoWorkItem {
                                    item.cancel()
                                    pendingPhotoWorkItem = nil
                                    capturePhoto()
                                }
                            }
                        },
                        perform: {
                            // Long-press threshold reached — start video and cancel the pending photo.
                            cancelPendingPhotoCapture()
                            if !camera.isRecording {
                                startVideoRecording()
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
    
    private func schedulePhotoCapture() {
        cancelPendingPhotoCapture()
        let item = DispatchWorkItem { [self] in
            self.pendingPhotoWorkItem = nil
            if !self.camera.isRecording && !self.isHoldingVideo {
                self.capturePhoto()
            }
        }
        pendingPhotoWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: item)
    }
    
    private func cancelPendingPhotoCapture() {
        pendingPhotoWorkItem?.cancel()
        pendingPhotoWorkItem = nil
    }
    
    private func capturePhoto() {
        guard capturedImage == nil && capturedVideoURL == nil else { return }
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
        Task {
            do {
                try await camera.startRecording()
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
}

// MARK: - Camera Capture Manager

final class CameraCaptureManager: NSObject, ObservableObject {
    let session = AVCaptureSession()
    
    @Published var hasPermission = false
    @Published var isRecording = false
    @Published var recordingProgress: CGFloat = 0
    @Published var errorMessage: String?
    
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    private let sessionQueue = DispatchQueue(label: "com.mattmarsh.imagecircle.camera.session")
    private let stateLock = NSLock()
    private var photoContinuation: CheckedContinuation<UIImage?, Error>?
    private var videoContinuation: CheckedContinuation<URL?, Never>?
    private var videoRecordingURL: URL?
    private var recordingTimer: Timer?
    
    private let maxVideoDuration: CGFloat = 30
    private let videoTimerInterval: CGFloat = 0.05
    
    func clearError() {
        errorMessage = nil
    }
    
    func checkPermissionAndSetup() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await MainActor.run { hasPermission = true }
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { hasPermission = granted }
            if granted {
                await setupSession()
            }
        default:
            await MainActor.run { hasPermission = false }
        }
        
        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
    
    private func setupSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                defer { continuation.resume() }
                guard let self = self else { return }
                self.configureSession()
                self.session.startRunning()
            }
        }
    }
    
    private func configureSession() {
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
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = error.localizedDescription
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }
    
    func switchCamera() {
        guard !isRecording else { return }
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            defer { self.session.commitConfiguration() }
            
            guard let currentInput = self.videoDeviceInput else { return }
            self.session.removeInput(currentInput)
            
            let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                if self.session.canAddInput(currentInput) {
                    self.session.addInput(currentInput)
                }
                return
            }
            self.session.addInput(input)
            self.videoDeviceInput = input
        }
    }
    
    private func startRecordingProgressTimer() {
        var elapsed: CGFloat = 0
        recordingTimer?.invalidate()
        recordingProgress = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: videoTimerInterval, repeats: true) { [weak self] timer in
            guard let self = self, self.isRecording else {
                timer.invalidate()
                return
            }
            elapsed += self.videoTimerInterval
            self.recordingProgress = min(elapsed / self.maxVideoDuration, 1.0)
            if elapsed >= self.maxVideoDuration {
                timer.invalidate()
                Task { await self.stopRecording() }
            }
        }
    }
    
    private func stopRecordingProgressTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingProgress = 0
    }
    
    func capturePhoto() async throws -> UIImage? {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera unavailable"]))
                    return
                }
                self.setPhotoContinuation(continuation)
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
                DispatchQueue.main.async { [weak self] in
                    self?.isRecording = true
                    self?.startRecordingProgressTimer()
                }
                continuation.resume()
            }
        }
    }
    
    func stopRecording() async -> URL? {
        guard isRecording else { return nil }
        
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                self.setVideoContinuation(continuation)
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                } else {
                    let url = self.videoRecordingURL
                    _ = self.clearVideoContinuation()
                    DispatchQueue.main.async { [weak self] in
                        self?.stopRecordingProgressTimer()
                    }
                    continuation.resume(returning: url)
                }
            }
        }
    }
    
    // MARK: - Continuation locking
    
    private func setPhotoContinuation(_ continuation: CheckedContinuation<UIImage?, Error>) {
        stateLock.lock()
        photoContinuation = continuation
        stateLock.unlock()
    }
    
    private func clearPhotoContinuation() -> CheckedContinuation<UIImage?, Error>? {
        stateLock.lock()
        let c = photoContinuation
        photoContinuation = nil
        stateLock.unlock()
        return c
    }
    
    private func setVideoContinuation(_ continuation: CheckedContinuation<URL?, Never>) {
        stateLock.lock()
        videoContinuation = continuation
        stateLock.unlock()
    }
    
    private func clearVideoContinuation() -> CheckedContinuation<URL?, Never>? {
        stateLock.lock()
        let c = videoContinuation
        videoContinuation = nil
        stateLock.unlock()
        return c
    }
}

extension CameraCaptureManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async { [weak self] in
                self?.clearPhotoContinuation()?.resume(throwing: error)
            }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async { [weak self] in
                self?.clearPhotoContinuation()?.resume(throwing: NSError(domain: "Camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not process photo"]))
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.clearPhotoContinuation()?.resume(returning: image)
        }
    }
}

extension CameraCaptureManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.stopRecordingProgressTimer()
            if let error = error {
                self?.errorMessage = error.localizedDescription
                self?.clearVideoContinuation()?.resume(returning: nil)
            } else {
                self?.clearVideoContinuation()?.resume(returning: outputFileURL)
            }
        }
    }
}

// MARK: - Camera Preview

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        uiView.videoPreviewLayer.frame = uiView.bounds
    }
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
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
