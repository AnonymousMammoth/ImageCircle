//
//  ViewExtensions.swift
//  ImageCircle
//
//  Shared view modifiers and helpers.
//

import SwiftUI
import Kingfisher

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

extension View {
    /// Standard async image placeholder with pink accent.
    func placeholderOverlay() -> some View {
        self
            .background(Color(.systemGray6))
            .overlay(
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .pink))
            )
    }
    
    /// Hide keyboard helper.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Media URL Helper

enum MediaURL {
    /// Builds a media URL like {base_url}/media/{user_id}/{filename}.
    static func url(userID: Int, filename: String) -> URL? {
        guard let base = UserDefaults.standard.string(forKey: "server_url"), !base.isEmpty,
              var url = URL(string: base) else { return nil }
        url.appendPathComponent("media/\(userID)/\(filename)")
        return url
    }
}

// MARK: - Avatar Helpers

@ViewBuilder
func placeholderAvatar(name: String) -> some View {
    Circle()
        .fill(Color(.systemGray4))
        .overlay(
            Text(initials(from: name))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        )
}

private func initials(from name: String) -> String {
    let parts = name.split(separator: " ")
    if parts.count > 1, let first = parts.first?.first, let last = parts.last?.first {
        return "\(first)\(last)".uppercased()
    }
    return String(name.prefix(2)).uppercased()
}

@ViewBuilder
func avatarImage(url: URL?) -> some View {
    if let url = url {
        KFImage(url)
            .resizable()
            .placeholder { Circle().fill(Color(.systemGray4)) }
            .aspectRatio(contentMode: .fill)
            .clipShape(Circle())
    } else {
        Circle()
            .fill(Color(.systemGray4))
            .overlay(Text("?").foregroundStyle(.secondary))
    }
}

// MARK: - Reusable Avatar

struct AvatarImage: View {
    let user: User
    let size: CGFloat
    
    var body: some View {
        Group {
            if let filename = user.avatarFilename,
               !filename.isEmpty,
               let url = MediaURL.url(userID: user.id, filename: filename) {
                KFImage(url)
                    .resizable()
                    .placeholder { placeholderAvatar(name: user.username) }
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderAvatar(name: user.username)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
