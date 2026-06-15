//
//  ForcePasswordChangeView.swift
//  ImageCircle
//
//  Non-dismissible full-screen cover shown after first login with a temporary password.
//

import SwiftUI

struct ForcePasswordChangeView: View {
    let currentPassword: String
    
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    
    private var canSubmit: Bool {
        newPassword.count >= PasswordValidator.minimumLength &&
        PasswordValidator.isStrong(newPassword) &&
        newPassword == confirmPassword
    }

    private var passwordHint: String {
        PasswordValidator.strengthHint(for: newPassword)
    }

    private var showPasswordHint: Bool {
        !newPassword.isEmpty && !PasswordValidator.isStrong(newPassword)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "lock.shield")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 70, height: 70)
                        .foregroundStyle(.pink)
                    
                    Text("Change Your Password")
                        .font(.title2.weight(.semibold))
                    
                    Text("Your account was created with a temporary password. Set your own to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 16) {
                        SecureField("New Password", text: $newPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        SecureField("Confirm New Password", text: $confirmPassword)
                            .textContentType(.newPassword)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        if showPasswordHint {
                            Text(passwordHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    Button(action: submit) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Set Password")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSubmit ? Color.pink : Color.pink.opacity(0.5))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canSubmit || isLoading)
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Could not change password.")
            }
        }
    }
    
    private func submit() {
        guard canSubmit else { return }
        isLoading = true
        Task {
            do {
                try await AuthManager.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
