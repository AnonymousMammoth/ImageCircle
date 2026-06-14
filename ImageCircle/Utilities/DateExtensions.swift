//
//  DateExtensions.swift
//  ImageCircle
//
//  Date parsing and relative formatting helpers.
//

import Foundation

extension Date {
    /// Parses ISO8601 strings from the backend.
    static func fromISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    /// Returns a short relative string like "just now", "5m", "2h", "1d".
    func relativeTime() -> String {
        let interval = -timeIntervalSinceNow
        if interval < 10 { return "just now" }
        if interval < 60 { return "\(Int(interval))s" }
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }
}

extension String {
    /// Convenience to format a backend ISO8601 string into a relative time display.
    func relativeTimeFromISO() -> String {
        guard let date = Date.fromISO8601(self) else { return self }
        return date.relativeTime()
    }
}
