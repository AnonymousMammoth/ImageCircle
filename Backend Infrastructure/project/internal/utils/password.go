package utils

import (
	"crypto/rand"
	"fmt"
	"strings"
	"unicode"

	"golang.org/x/crypto/bcrypt"
)

const (
	lowerChars   = "abcdefghijklmnopqrstuvwxyz"
	upperChars   = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	digitChars   = "0123456789"
	specialChars = "!@#$%^&*"
	allChars     = lowerChars + upperChars + digitChars + specialChars
)

// HashPassword generates a bcrypt hash of the password using the specified cost.
func HashPassword(password string, cost int) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), cost)
	if err != nil {
		return "", fmt.Errorf("failed to hash password: %w", err)
	}
	return string(hash), nil
}

// VerifyPassword compares a plaintext password with a bcrypt hash.
// Returns true if the password matches the hash.
func VerifyPassword(password, hash string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password))
	return err == nil
}

// GenerateTemporaryPassword generates a random 12-character temporary password
// containing a mix of lowercase, uppercase, digits, and special characters.
func GenerateTemporaryPassword() (string, error) {
	const length = 12

	// Ensure at least one of each character type
	result := make([]byte, length)

	// Read random bytes for each position
	randomBytes := make([]byte, length)
	if _, err := rand.Read(randomBytes); err != nil {
		return "", fmt.Errorf("failed to generate random bytes: %w", err)
	}

	// Fill with random characters from all allowed character sets
	for i := 0; i < length; i++ {
		result[i] = allChars[randomBytes[i]%byte(len(allChars))]
	}

	// Guarantee at least one of each character type by replacing first 4 positions
	result[0] = lowerChars[randomBytes[0]%byte(len(lowerChars))]
	result[1] = upperChars[randomBytes[1]%byte(len(upperChars))]
	result[2] = digitChars[randomBytes[2]%byte(len(digitChars))]
	result[3] = specialChars[randomBytes[3]%byte(len(specialChars))]

	return string(result), nil
}

// ValidatePasswordStrength checks that a password meets minimum strength requirements:
//   - At least 8 characters
//   - At least one uppercase letter
//   - At least one lowercase letter
//   - At least one digit
func ValidatePasswordStrength(password string) error {
	if len(password) < 8 {
		return fmt.Errorf("password must be at least 8 characters long")
	}

	var (
		hasUpper bool
		hasLower bool
		hasDigit bool
	)

	for _, r := range password {
		switch {
		case unicode.IsUpper(r):
			hasUpper = true
		case unicode.IsLower(r):
			hasLower = true
		case unicode.IsDigit(r):
			hasDigit = true
		}
	}

	var missing []string
	if !hasUpper {
		missing = append(missing, "uppercase letter")
	}
	if !hasLower {
		missing = append(missing, "lowercase letter")
	}
	if !hasDigit {
		missing = append(missing, "digit")
	}

	if len(missing) > 0 {
		return fmt.Errorf("password must contain at least one %s", strings.Join(missing, ", "))
	}

	return nil
}
