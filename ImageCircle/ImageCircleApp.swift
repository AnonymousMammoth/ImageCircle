//
//  ImageCircleApp.swift
//  ImageCircle
//
//  App entry point. Restores Keychain token on launch and routes to login or main tabs.
//

import SwiftUI
import AVFoundation

import Kingfisher

/// Adds the current JWT to media download requests so Kingfisher can load
/// authenticated /media/* URLs even if the shared session cookie is not present.
struct MediaAuthRequestModifier: ImageDownloadRequestModifier {
    func modified(for request: URLRequest) -> URLRequest? {
        guard let url = request.url,
              url.path.hasPrefix("/media/"),
              let token = APIClient.shared.token else {
            return request
        }
        var mutableRequest = request
        mutableRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return mutableRequest
    }
}

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

        // Attach the JWT to all Kingfisher media downloads as a fallback/primary auth method.
        KingfisherManager.shared.defaultOptions = [.requestModifier(MediaAuthRequestModifier())]

        // Ensure story and preview videos play with audible audio.
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
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
