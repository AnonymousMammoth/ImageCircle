//
//  TextPostComposerView.swift
//  ImageCircle
//
//  Composer for text-only posts (Twitter-style).
//  Assumes backend accepts POST /api/posts with JSON body { "caption": "..." }.
//

import SwiftUI

struct TextPostComposerView: View {
    let onComplete: () -> Void
    
    @State private var text: String = ""
    @State private var isPosting = false
    @State private var uploadProgress: Double = 0
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    
    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
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
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isPosting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: post) {
                        if isPosting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Post")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canPost || isPosting)
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("Try Again") { post() }
                Button("Cancel", role: .cancel) { dismiss() }
            } message: {
                Text(errorMessage ?? "Could not post.")
            }
        }
    }
    
    private func post() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isPosting = true
        uploadProgress = 0.5
        Task {
            do {
                _ = try await APIClient.shared.createTextPost(caption: trimmed)
                uploadProgress = 1.0
                isPosting = false
                onComplete()
                dismiss()
            } catch {
                isPosting = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
