//
//  ImageCircleApp.swift
//  ImageCircle
//
//  App entry point. Restores Keychain token on launch and routes to login or main tabs.
//

import SwiftUI

import Kingfisher

@main
struct ImageCircleApp: App {
    @StateObject private var auth = AuthManager.shared
    @State private var isLoading = true
    
    init() {
        // Share the same cookie storage as the API client so authenticated
        // media requests (/media/*) include the session cookie set by login.
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        KingfisherManager.shared.downloader.sessionConfiguration = config
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isLoading {
                    splashView
                } else if auth.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .task {
                await AuthManager.shared.loadStoredCredentials()
                isLoading = false
            }
        }
    }
    
    private var splashView: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "circle.circle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.pink)
                Text("ImageCircle")
                    .font(.largeTitle.weight(.semibold))
            }
        }
    }
}
