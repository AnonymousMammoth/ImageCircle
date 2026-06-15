//
//  CreateComposerView.swift
//  ImageCircle
//
//  Create tab composer: defaults to the user's photo library, with toggles for
//  text-only posts and a button to capture a new photo.
//

import SwiftUI
import Photos
import PhotosUI

enum CreateComposerMode {
    case photo
    case text
}

struct CreateComposerView: View {
    let onFinished: (Bool) -> Void
    
    @State private var mode: CreateComposerMode = .photo
    @State private var assets: [PHAsset] = []
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var selectedImage: UIImage?
    @State private var selectedImageData: Data?
    @State private var caption: String = ""
    @State private var text: String = ""
    @State private var isPosting = false
    @State private var showCamera = false
    @State private var showError = false
    @State private var errorMessage: String?
    @State private var uploadProgress: Double = 0
    @Environment(\.dismiss) private var dismiss
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Create", selection: $mode) {
                    Text("Photo").tag(CreateComposerMode.photo)
                    Text("Text").tag(CreateComposerMode.text)
                }
                .pickerStyle(.segmented)
                .padding()
                
                if mode == .photo {
                    photoSection
                } else {
                    textSection
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        onFinished(false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showCamera = true }) {
                        Image(systemName: "camera.fill")
                    }
                    .disabled(mode != .photo)
                    .accessibilityLabel("Take photo")
                }
            }
            .task {
                await requestPhotoAccess()
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .photo, authorizationStatus == .authorized {
                    loadRecentPhotos()
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPhotoPicker { image in
                    showCamera = false
                    if let image = image {
                        Task { @MainActor in
                            selectedImage = image
                            selectedImageData = await compressPhotoForCreate(image)
                        }
                    }
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { selectedImage != nil },
                    set: { if !$0 { selectedImage = nil; selectedImageData = nil; caption = "" } }
                )
            ) {
                selectedImageSheet
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Something went wrong.")
            }
        }
    }
    
    // MARK: - Photo Section
    
    @ViewBuilder
    private var photoSection: some View {
        if authorizationStatus == .authorized {
            if assets.isEmpty {
                emptyPhotoState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets, id: \.localIdentifier) { asset in
                            PhotoGridCell(asset: asset) {
                                selectAsset(asset)
                            }
                        }
                    }
                }
            }
        } else if authorizationStatus == .notDetermined {
            Spacer()
            ProgressView()
            Spacer()
        } else {
            photoPermissionPlaceholder
        }
    }
    
    private var emptyPhotoState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("No photos found.")
                .foregroundStyle(.secondary)
            Button("Take a Photo") {
                showCamera = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.pink)
            Spacer()
        }
    }
    
    private var photoPermissionPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "photo")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Photo library access is needed to create image posts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Text Section
    
    private var textSection: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                placeholderAvatar(name: AuthManager.shared.currentUser?.username ?? "")
                    .frame(width: 40, height: 40)
                
                TextEditor(text: $text)
                    .font(.body)
                    .frame(minHeight: 120, alignment: .top)
                    .scrollContentBackground(.hidden)
            }
            .padding()
            
            Spacer()
            
            if isPosting {
                ProgressView(value: uploadProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .pink))
                    .padding(.horizontal)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: postText) {
                    if isPosting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Post")
                            .fontWeight(.semibold)
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                .buttonStyle(.borderedProminent)
                .tint(.pink)
            }
        }
    }
    
    // MARK: - Photo Selection
    
    private func requestPhotoAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run {
            authorizationStatus = status
        }
        if status == .authorized {
            loadRecentPhotos()
        }
    }
    
    private func loadRecentPhotos() {
        PhotoLibraryCache.shared.fetchRecentPhotos { fetched in
            Task { @MainActor in
                self.assets = fetched
            }
        }
    }
    
    private func selectAsset(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 2048, height: 2048),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image = image else { return }
            Task { @MainActor in
                selectedImage = image
                selectedImageData = await compressPhotoForCreate(image)
            }
        }
    }
    
    private var selectedImageSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
                }
                
                TextField("Write a caption...", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)
                    .padding()
                
                Spacer()
                
                if isPosting {
                    ProgressView(value: uploadProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .pink))
                        .padding(.horizontal)
                }
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        selectedImage = nil
                        selectedImageData = nil
                        caption = ""
                    }
                    .disabled(isPosting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: postPhoto) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isPosting)
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
            }
        }
    }
    
    // MARK: - Posting
    
    private func postPhoto() {
        guard let imageData = selectedImageData else { return }
        isPosting = true
        uploadProgress = 0.2
        Task {
            do {
                guard let image = UIImage(data: imageData) else {
                    throw NSError(domain: "CreateComposer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected image."])
                }
                let thumbData = squareThumbnailData(from: image)
                uploadProgress = 0.4
                _ = try await APIClient.shared.createPost(
                    caption: caption,
                    imageData: imageData,
                    thumbnailData: thumbData
                ) { progress in
                    Task { @MainActor in
                        self.uploadProgress = 0.4 + 0.6 * progress
                    }
                }
                uploadProgress = 1.0
                isPosting = false
                selectedImage = nil
                selectedImageData = nil
                caption = ""
                onFinished(true)
            } catch {
                isPosting = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
    
    private func postText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        uploadProgress = 0.5
        Task {
            do {
                _ = try await APIClient.shared.createTextPost(caption: trimmed)
                uploadProgress = 1.0
                isPosting = false
                text = ""
                onFinished(true)
            } catch {
                isPosting = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Photo Grid Cell

struct PhotoGridCell: View {
    let asset: PHAsset
    let action: () -> Void
    
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemGray5)
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
            .onTapGesture(perform: action)
            .task {
                loadThumbnail(size: CGSize(width: geo.size.width * 2, height: geo.size.width * 2))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
    
    private func loadThumbnail(size: CGSize) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: size,
            contentMode: .aspectFill,
            options: options
        ) { loaded, _ in
            Task { @MainActor in
                self.image = loaded
            }
        }
    }
}

// MARK: - Compression Helpers

private func compressPhotoForCreate(_ image: UIImage) async -> Data {
    let maxDimension: CGFloat = 2048
    let size = image.size
    let scale = min(1.0, maxDimension / max(size.width, size.height))
    let newSize = CGSize(width: size.width * scale, height: size.height * scale)
    
    return await Task.detached(priority: .userInitiated) {
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85) ?? Data()
    }.value
}

// MARK: - Camera Photo Picker

struct CameraPhotoPicker: UIViewControllerRepresentable {
    let onComplete: (UIImage?) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPhotoPicker
        
        init(_ parent: CameraPhotoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage
            parent.onComplete(image)
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            parent.onComplete(nil)
        }
    }
}

// MARK: - Photo Library Cache

final class PhotoLibraryCache {
    static let shared = PhotoLibraryCache()
    
    private var assets: [PHAsset]?
    private var isFetching = false
    private var waiters: [@MainActor ([PHAsset]) -> Void] = []
    
    func fetchRecentPhotos(limit: Int = 60, completion: @escaping @MainActor ([PHAsset]) -> Void) {
        if let assets = assets {
            Task { @MainActor in completion(assets) }
            return
        }
        waiters.append(completion)
        guard !isFetching else { return }
        isFetching = true
        
        Task.detached(priority: .userInitiated) { [weak self] in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = limit
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            let result = PHAsset.fetchAssets(with: options)
            let fetched = result.objects(at: IndexSet(integersIn: 0..<result.count))
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.assets = fetched
                self.isFetching = false
                let handlers = self.waiters
                self.waiters.removeAll()
                handlers.forEach { $0(fetched) }
            }
        }
    }
    
    func invalidate() {
        assets = nil
    }
}

// MARK: - Thumbnail Helpers

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
