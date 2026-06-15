package handlers

import (
	"database/sql"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/utils"
)

// AuthHandler handles authentication endpoints.
type AuthHandler struct {
	DB           *sql.DB
	JWTSecret    []byte
	PasswordCost int
}

// LoginRequest represents a login request.
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// ChangePasswordRequest represents a password change request.
type ChangePasswordRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// SetupRequest represents a one-time initial admin setup request.
type SetupRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// Login authenticates a user and returns a JWT token.
func (h *AuthHandler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || req.Password == "" {
		utils.RespondError(c, http.StatusBadRequest, "username and password required")
		return
	}

	user, err := models.GetUserByUsername(h.DB, req.Username)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusUnauthorized, "invalid credentials")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "authentication failed")
		return
	}

	if !utils.VerifyPassword(req.Password, user.PasswordHash) {
		utils.RespondError(c, http.StatusUnauthorized, "invalid credentials")
		return
	}

	token, expiry, err := utils.GenerateToken(user.ID, user.Username, user.IsAdmin, h.JWTSecret)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	// Store session in DB for token revocation support
	if err := models.CreateSession(h.DB, user.ID, token, expiry); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create session")
		return
	}

	// Return user without password hash
	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, gin.H{
		"token":   token,
		"user":    user,
		"expires_at": expiry.Format(time.RFC3339),
	})
}

// Refresh generates a new JWT token with extended expiry and revokes the current token.
func (h *AuthHandler) Refresh(c *gin.Context) {
	userID := c.GetInt64("user_id")
	username := c.GetString("username")
	isAdmin := c.GetBool("is_admin")

	// Extract and revoke the current token so it cannot be used again.
	authHeader := c.GetHeader("Authorization")
	if authHeader != "" {
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && strings.EqualFold(parts[0], "Bearer") {
			tokenString := parts[1]
			_ = models.DeleteSessionByToken(h.DB, tokenString)
		}
	}

	token, expiry, err := utils.GenerateToken(userID, username, isAdmin, h.JWTSecret)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	// Store new session
	if err := models.CreateSession(h.DB, userID, token, expiry); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create session")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"token":      token,
		"expires_at": expiry.Format(time.RFC3339),
	})
}

// ChangePassword allows an authenticated user to change their password.
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.CurrentPassword == "" || req.NewPassword == "" {
		utils.RespondError(c, http.StatusBadRequest, "current_password and new_password required")
		return
	}

	// Validate new password strength
	if err := utils.ValidatePasswordStrength(req.NewPassword); err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	// Get current user to verify current password
	user, err := models.GetUserByID(h.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	if !utils.VerifyPassword(req.CurrentPassword, user.PasswordHash) {
		utils.RespondError(c, http.StatusUnauthorized, "current password is incorrect")
		return
	}

	// Hash new password
	newHash, err := utils.HashPassword(req.NewPassword, h.PasswordCost)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	// Update password and clear change-required flag
	if err := models.UpdatePassword(h.DB, userID, newHash, false); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to update password")
		return
	}

	// Invalidate all existing sessions for this user
	if err := models.DeleteSessionsForUser(h.DB, userID); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to invalidate sessions")
		return
	}

	// Generate a fresh session token
	token, expiry, err := utils.GenerateToken(user.ID, user.Username, user.IsAdmin, h.JWTSecret)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	if err := models.CreateSession(h.DB, user.ID, token, expiry); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create session")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"token":   token,
		"success": true,
		"expires_at": expiry.Format(time.RFC3339),
	})
}

// Setup performs one-time initial admin setup. It creates the first admin user
// when no users exist and returns an auth token.
func (h *AuthHandler) Setup(c *gin.Context) {
	var req SetupRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || req.Password == "" {
		utils.RespondError(c, http.StatusBadRequest, "username and password required")
		return
	}

	// One-time setup: only allowed when there are no users.
	var userCount int64
	if err := h.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&userCount); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to check setup status")
		return
	}
	if userCount > 0 {
		utils.RespondError(c, http.StatusForbidden, "setup already complete")
		return
	}

	if err := utils.ValidatePasswordStrength(req.Password); err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	passwordHash, err := utils.HashPassword(req.Password, h.PasswordCost)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	user, err := models.CreateUser(h.DB, req.Username, req.Username, passwordHash, true)
	if err != nil {
		if isUniqueViolation(err) {
			utils.RespondError(c, http.StatusBadRequest, "username already exists")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to create admin user")
		return
	}

	token, expiry, err := utils.GenerateToken(user.ID, user.Username, user.IsAdmin, h.JWTSecret)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate token")
		return
	}

	if err := models.CreateSession(h.DB, user.ID, token, expiry); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create session")
		return
	}

	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, gin.H{
		"token":      token,
		"user":       user,
		"expires_at": expiry.Format(time.RFC3339),
	})
}

// Logout blacklists the current JWT token.
func (h *AuthHandler) Logout(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		utils.RespondError(c, http.StatusBadRequest, "authorization header required")
		return
	}

	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		utils.RespondError(c, http.StatusBadRequest, "invalid authorization header format")
		return
	}

	tokenString := parts[1]

	// Delete the session to blacklist the token
	if err := models.DeleteSession(h.DB, tokenString); err != nil {
		if err == sql.ErrNoRows {
			// Token wasn't tracked as a session, still treat as success
			utils.RespondNoContent(c)
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to logout")
		return
	}

	utils.RespondNoContent(c)
}
