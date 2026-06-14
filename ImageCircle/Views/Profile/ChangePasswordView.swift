//
//  ChangePasswordView.swift
//  ImageCircle
//
//  Allows a logged-in user to change their password.
//

import SwiftUI

struct ChangePasswordView: View {
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false
    @Environment(\.dismiss) private var dismiss
    
    private var canSubmit: Bool {
        !currentPassword.isEmpty &&
        newPassword.count >= 6 &&
        newPassword == confirmPassword
    }
    
    var body: some View {
        Form {
            Section("Current Password") {
                SecureField("Current Password", text: $currentPassword)
                    .textContentType(.password)
            }
            
            Section("New Password") {
                SecureField("New Password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm New Password", text: $confirmPassword)
                    .textContentType(.newPassword)
            }
            
            Section {
                Button(action: submit) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        }
                        Text("Update Password")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!canSubmit || isLoading)
                .listRowBackground(canSubmit && !isLoading ? Color.pink : Color.pink.opacity(0.5))
                .foregroundStyle(.white)
            }
        }
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Could not change password.")
        }
        .alert("Success", isPresented: $showSuccess) {
            Button("Done", role: .cancel) { dismiss() }
        } message: {
            Text("Your password has been updated.")
        }
    }
    
    private func submit() {
        guard canSubmit else { return }
        isLoading = true
        Task {
            do {
                try await AuthManager.shared.changePassword(currentPassword: currentPassword, newPassword: newPassword)
                isLoading = false
                showSuccess = true
            } catch {
                isLoading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
