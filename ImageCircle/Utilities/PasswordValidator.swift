//
//  PasswordValidator.swift
//  ImageCircle
//
//  Shared password-strength rules for iOS change-password flows.
//

import Foundation

enum PasswordValidator {
    /// Minimum password length enforced as a floor for any submission.
    static let minimumLength = 6
    /// Stronger minimum length recommended for user-chosen passwords.
    static let strongMinimumLength = 8

    static func isStrong(_ password: String) -> Bool {
        guard password.count >= strongMinimumLength else { return false }
        let uppercase = CharacterSet.uppercaseLetters
        let lowercase = CharacterSet.lowercaseLetters
        let digits = CharacterSet.decimalDigits

        let hasUppercase = password.rangeOfCharacter(from: uppercase) != nil
        let hasLowercase = password.rangeOfCharacter(from: lowercase) != nil
        let hasDigit = password.rangeOfCharacter(from: digits) != nil

        return hasUppercase && hasLowercase && hasDigit
    }

    static func strengthHint(for password: String) -> String {
        if password.isEmpty { return "" }
        if isStrong(password) { return "Password looks good." }
        return "Use at least \(strongMinimumLength) characters with an uppercase letter, a lowercase letter, and a number."
    }
}
