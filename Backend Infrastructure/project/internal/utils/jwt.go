package utils

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

// TokenExpiry is the JWT token lifetime (30 days).
const TokenExpiry = 30 * 24 * time.Hour

// Claims represents the JWT claims for Circle.
type Claims struct {
	UserID   int64  `json:"sub"`
	Username string `json:"username"`
	IsAdmin  bool   `json:"is_admin"`
	jwt.RegisteredClaims
}

// GenerateToken creates a new JWT token with HS256.
// Returns the signed token string and the expiry time.
func GenerateToken(userID int64, username string, isAdmin bool, secret []byte) (string, time.Time, error) {
	expiry := time.Now().UTC().Add(TokenExpiry)

	claims := Claims{
		UserID:   userID,
		Username: username,
		IsAdmin:  isAdmin,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   fmt.Sprintf("%d", userID),
			ExpiresAt: jwt.NewNumericDate(expiry),
			IssuedAt:  jwt.NewNumericDate(time.Now().UTC()),
			NotBefore: jwt.NewNumericDate(time.Now().UTC()),
			ID:        uuid.NewString(),
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(secret)
	if err != nil {
		return "", time.Time{}, fmt.Errorf("failed to sign token: %w", err)
	}

	return tokenString, expiry, nil
}

// ValidateToken parses and validates a JWT token string.
// Returns the claims if the token is valid and not expired.
func ValidateToken(tokenString string, secret []byte) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(token *jwt.Token) (interface{}, error) {
		// Enforce HS256 only
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return secret, nil
	})
	if err != nil {
		return nil, fmt.Errorf("invalid token: %w", err)
	}

	if !token.Valid {
		return nil, fmt.Errorf("token is not valid")
	}

	claims, ok := token.Claims.(*Claims)
	if !ok {
		return nil, fmt.Errorf("invalid claims structure")
	}

	return claims, nil
}

// GenerateSecureSecret generates a cryptographically secure 64-byte random secret.
// Returns the secret as a hex-encoded string for easy storage.
func GenerateSecureSecret() ([]byte, error) {
	b := make([]byte, 64)
	if _, err := rand.Read(b); err != nil {
		return nil, fmt.Errorf("failed to generate random secret: %w", err)
	}
	return []byte(hex.EncodeToString(b)), nil
}
