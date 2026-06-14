//
//  LoginView.swift
//  ImageCircle
//
//  Username/password login with server URL configuration.
//

import SwiftUI

struct LoginView: View {
    @State private var serverURL: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoading = false
    @State private var showForcePasswordChange = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private var canLogin: Bool {
        !serverURL.isEmpty && !username.isEmpty && !password.isEmpty
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 24) {
                    Spacer()
                    
                    Image(systemName: "circle.circle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 90, height: 90)
                        .foregroundStyle(.pink)
                    
                    Text("ImageCircle")
                        .font(.largeTitle.weight(.semibold))
                    
                    VStack(spacing: 16) {
                        TextField("Server URL", text: $serverURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        TextField("Username", text: $username)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    Button(action: login) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            Text("Log In")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canLogin ? Color.pink : Color.pink.opacity(0.5))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(!canLogin || isLoading)
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
            .onAppear {
                serverURL = UserDefaults.standard.string(forKey: "server_url") ?? ""
            }
            .alert("Login Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Invalid username or password.")
            }
            .fullScreenCover(isPresented: $showForcePasswordChange) {
                ForcePasswordChangeView(currentPassword: password)
                    .interactiveDismissDisabled()
            }
        }
    }
    
    private func login() {
        guard canLogin else { return }
        isLoading = true
        Task {
            do {
                try await AuthManager.shared.login(serverURL: serverURL, username: username, password: password)
                isLoading = false
                if AuthManager.shared.needsPasswordChange {
                    showForcePasswordChange = true
                }
            } catch let error as APIError where error == .unauthorized {
                isLoading = false
                errorMessage = "Invalid username or password."
                showError = true
            } catch {
                isLoading = false
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showError = true
            }
        }
    }
}
