//
//  CameraView.swift
//  ImageCircle
//
//  v1 create flow using UIImagePickerController for media and a native composer for text.
//

import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers

enum CaptureMode: String, CaseIterable {
    case photo = "Photo"
    case video = "Video"
    case text = "Text"
}

struct CameraView: View {
    let onPostCreated: () -> Void
    
    @State private var mode: CaptureMode = .photo
    @State private var showImagePicker = false
    @State private var showPhotoLibrary = false
    @State private var showTextComposer = false
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Picker("Mode", selection: $mode) {
                    ForEach(CaptureMode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                Spacer()
                
                if mode == .text {
                    textCaptureUI
                } else {
                    mediaCaptureUI
                }
                
                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(sourceType: .camera, mediaType: mode == .photo ? .photo : .video) { image, videoURL in
                    if let image = image {
                        capturedImage = image
                    } else if let videoURL = videoURL {
                        capturedVideoURL = videoURL
                    }
                }
            }
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePicker(sourceType: .photoLibrary, mediaType: .photo) { image, _ in
                    if let image = image {
                        capturedImage = image
                    }
                }
            }
            .sheet(isPresented: $showTextComposer) {
                TextPostComposerView {
                    onPostCreated()
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { capturedImage != nil || capturedVideoURL != nil },
                set: { if !$0 { capturedImage = nil; capturedVideoURL = nil } }
            )) {
                if let image = capturedImage {
                    MediaPreviewView(
                        image: image,
                        videoURL: nil,
                        mode: mode,
                        onComplete: {
                            onPostCreated()
                        }
                    )
                } else if let videoURL = capturedVideoURL {
                    MediaPreviewView(
                        image: nil,
                        videoURL: videoURL,
                        mode: mode,
                        onComplete: {
                            onPostCreated()
                        }
                    )
                }
            }
            .alert("Camera Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not access camera.")
            }
        }
    }
    
    private var mediaCaptureUI: some View {
        VStack(spacing: 16) {
            Button(action: { showImagePicker = true }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 80, height: 80)
                    Circle()
                        .stroke(Color.pink, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    Image(systemName: mode == .photo ? "camera" : "video.fill")
                        .font(.title)
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityLabel(mode == .photo ? "Take photo" : "Record video")
            
            Text(mode == .photo ? "Tap to capture photo" : "Tap to record video")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(action: { showPhotoLibrary = true }) {
                Label("Choose from Library", systemImage: "photo.on.rectangle")
                    .font(.subheadline)
            }
            .padding(.top, 24)
            .accessibilityLabel("Choose photo from library")
        }
    }
    
    private var textCaptureUI: some View {
        VStack(spacing: 16) {
            Button(action: { showTextComposer = true }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 80, height: 80)
                    Circle()
                        .stroke(Color.pink, lineWidth: 4)
                        .frame(width: 80, height: 80)
                    Image(systemName: "text.bubble")
                        .font(.title)
                        .foregroundStyle(.pink)
                }
            }
            .accessibilityLabel("Write text post")
            
            Text("Tap to write a post")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - UIImagePickerController Wrapper

enum ImagePickerMediaType {
    case photo
    case video
}

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let mediaType: ImagePickerMediaType
    let onComplete: (UIImage?, URL?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.delegate = context.coordinator
        picker.mediaTypes = mediaType == .photo
            ? [UTType.image.identifier]
            : [UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = 30
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
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
