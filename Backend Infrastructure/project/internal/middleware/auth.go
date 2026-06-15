package middleware

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/utils"
)

// TokenBlacklistChecker is called by the auth middleware to verify whether a
// token has been revoked. The application should set this during startup.
var TokenBlacklistChecker func(tokenString string) (bool, error)

// contextKey defines typed keys for storing values in gin.Context.
type contextKey string

const (
	ctxUserID   contextKey = "user_id"
	ctxUsername contextKey = "username"
	ctxIsAdmin  contextKey = "is_admin"
)

// AuthRequired returns a middleware that validates the JWT Bearer token.
// It first checks the Authorization header, then falls back to a cookie named
// "circle_session" so that <img> tags and other browser-initiated requests can
// be authenticated. It sets user_id, username, and is_admin in the gin context.
// If the token is missing, invalid, expired, or blacklisted, it returns 401.
func AuthRequired(secret []byte) gin.HandlerFunc {
	return func(c *gin.Context) {
		tokenString := ""

		authHeader := c.GetHeader("Authorization")
		if authHeader != "" {
			parts := strings.SplitN(authHeader, " ", 2)
			if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
				tokenString = parts[1]
			}
		}

		if tokenString == "" {
			cookie, err := c.Cookie("circle_session")
			if err == nil && cookie != "" {
				tokenString = cookie
			}
		}

		// Fallback to a token query parameter for browser <img>/<video> tags in
		// environments where the HttpOnly cookie cannot be sent.
		if tokenString == "" {
			tokenString = c.Query("token")
		}

		if tokenString == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authorization required"})
			return
		}

		// Check token blacklist if a checker has been configured
		if TokenBlacklistChecker != nil {
			blacklisted, err := TokenBlacklistChecker(tokenString)
			if err != nil {
				c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "failed to validate token"})
				return
			}
			if blacklisted {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "token has been revoked"})
				return
			}
		}

		claims, err := utils.ValidateToken(tokenString, secret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid or expired token"})
			return
		}

		c.Set(string(ctxUserID), claims.UserID)
		c.Set(string(ctxUsername), claims.Username)
		c.Set(string(ctxIsAdmin), claims.IsAdmin)

		c.Next()
	}
}

// AdminRequired returns a middleware that checks if the authenticated user is an admin.
// Must be used after AuthRequired. Returns 403 if the user is not an admin.
func AdminRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		isAdmin, exists := c.Get(string(ctxIsAdmin))
		if !exists {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "authentication required"})
			return
		}

		adminFlag, ok := isAdmin.(bool)
		if !ok || !adminFlag {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "admin access required"})
			return
		}

		c.Next()
	}
}

// GetUserID extracts the user ID from the gin context.
// Returns 0 if not set.
func GetUserID(c *gin.Context) int64 {
	val, exists := c.Get(string(ctxUserID))
	if !exists {
		return 0
	}
	id, ok := val.(int64)
	if !ok {
		return 0
	}
	return id
}

// GetUsername extracts the username from the gin context.
// Returns empty string if not set.
func GetUsername(c *gin.Context) string {
	val, exists := c.Get(string(ctxUsername))
	if !exists {
		return ""
	}
	name, ok := val.(string)
	if !ok {
		return ""
	}
	return name
}

// GetIsAdmin extracts the admin flag from the gin context.
// Returns false if not set.
func GetIsAdmin(c *gin.Context) bool {
	val, exists := c.Get(string(ctxIsAdmin))
	if !exists {
		return false
	}
	admin, ok := val.(bool)
	if !ok {
		return false
	}
	return admin
}
