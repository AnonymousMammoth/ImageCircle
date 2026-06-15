package handlers

import (
	"database/sql"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/storage"
	"circle/internal/utils"
)

// UserHandler handles user management endpoints.
type UserHandler struct {
	DB           *sql.DB
	MediaStore   *storage.MediaStore
	PasswordCost int
}

// CreateUserRequest represents a request to create a new user.
type CreateUserRequest struct {
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
	IsAdmin     bool   `json:"is_admin"`
}

// UpdateMeRequest represents a request to update the current user.
type UpdateMeRequest struct {
	DisplayName string `json:"display_name"`
}

// checkOwnership returns true if the requesting user owns the content or is an admin.
func checkOwnership(c *gin.Context, contentUserID int64) bool {
	userID := c.GetInt64("user_id")
	isAdmin := c.GetBool("is_admin")
	return userID == contentUserID || isAdmin
}

// CreateUser creates a new user (admin only).
func (h *UserHandler) CreateUser(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Username = sanitizeUsername(req.Username)
	req.DisplayName = sanitizeDisplayName(req.DisplayName)

	if req.Username == "" {
		utils.RespondError(c, http.StatusBadRequest, "username is required")
		return
	}
	if req.DisplayName == "" {
		utils.RespondError(c, http.StatusBadRequest, "display_name is required")
		return
	}
	if len(req.Username) < 3 || len(req.Username) > 30 {
		utils.RespondError(c, http.StatusBadRequest, "username must be 3-30 characters")
		return
	}

	tempPassword, err := utils.GenerateTemporaryPassword()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate temporary password")
		return
	}

	passwordHash, err := utils.HashPassword(tempPassword, h.PasswordCost)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	user, err := models.CreateUser(h.DB, req.Username, req.DisplayName, passwordHash, req.IsAdmin)
	if err != nil {
		if isUniqueViolation(err) {
			utils.RespondError(c, http.StatusBadRequest, "username already exists")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to create user")
		return
	}

	user.PasswordHash = ""
	utils.RespondCreated(c, gin.H{
		"user":               user,
		"temporary_password": tempPassword,
	})
}

// ListUsers returns all users (admin only).
func (h *UserHandler) ListUsers(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	users, err := models.GetAllUsers(h.DB)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve users")
		return
	}

	// Strip password hashes
	for _, u := range users {
		u.PasswordHash = ""
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"users": users})
}

// SearchUsers searches for users by username or display name.
func (h *UserHandler) SearchUsers(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	if q == "" {
		utils.RespondJSON(c, http.StatusOK, gin.H{"users": []*models.User{}})
		return
	}

	users, err := models.SearchUsers(h.DB, q)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to search users")
		return
	}

	for _, u := range users {
		u.PasswordHash = ""
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"users": users})
}

// GetMe returns the current authenticated user.
func (h *UserHandler) GetMe(c *gin.Context) {
	userID := c.GetInt64("user_id")

	user, err := models.GetUserByID(h.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, user)
}

// UpdateMe updates the current authenticated user's profile.
func (h *UserHandler) UpdateMe(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req UpdateMeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.DisplayName = sanitizeDisplayName(req.DisplayName)
	if req.DisplayName == "" {
		utils.RespondError(c, http.StatusBadRequest, "display_name is required")
		return
	}

	user, err := models.GetUserByID(h.DB, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	user.DisplayName = req.DisplayName
	if err := models.UpdateUser(h.DB, user); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to update user")
		return
	}

	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, user)
}

// DeleteUser deletes a user and all their content (admin only).
func (h *UserHandler) DeleteUser(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Prevent self-deletion
	if id == c.GetInt64("user_id") {
		utils.RespondError(c, http.StatusBadRequest, "cannot delete your own account")
		return
	}

	// Get user's media files before deletion for cleanup
	mediaFiles, err := getUserMediaFiles(h.DB, id)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user media")
		return
	}

	if err := models.DeleteUser(h.DB, id); err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete user")
		return
	}

	// Clean up media files after successful DB deletion
	for _, mf := range mediaFiles {
		_ = h.MediaStore.DeleteMedia(mf)
	}

	utils.RespondNoContent(c)
}

// ResetPassword generates a new temporary password for a user (admin only).
func (h *UserHandler) ResetPassword(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Check user exists
	_, err = models.GetUserByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	tempPassword, err := utils.GenerateTemporaryPassword()
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to generate temporary password")
		return
	}

	passwordHash, err := utils.HashPassword(tempPassword, h.PasswordCost)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to hash password")
		return
	}

	if err := models.UpdatePassword(h.DB, id, passwordHash, true); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to reset password")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"temporary_password": tempPassword,
	})
}

// ToggleAdmin toggles the admin status of a user (admin only).
func (h *UserHandler) ToggleAdmin(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Prevent self-lockout
	if id == c.GetInt64("user_id") {
		utils.RespondError(c, http.StatusBadRequest, "cannot toggle your own admin status")
		return
	}

	if err := models.ToggleAdmin(h.DB, id); err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to toggle admin status")
		return
	}

	user, err := models.GetUserByID(h.DB, id)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve updated user")
		return
	}

	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, user)
}

// GetUserPosts returns posts for a specific user, paginated by ?page and ?limit.
func (h *UserHandler) GetUserPosts(c *gin.Context) {
	requestingUserID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Check the requested user exists
	if _, err := models.GetUserByID(h.DB, id); err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	page := utils.GetPagination(c)
	posts, err := models.GetPostsByUser(h.DB, id, requestingUserID, page.Limit, page.Offset)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve posts")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"posts": posts})
}

// UpdateAvatar uploads and sets the current user's avatar.
func (h *UserHandler) UpdateAvatar(c *gin.Context) {
	userID := c.GetInt64("user_id")

	if err := c.Request.ParseMultipartForm(10 << 20); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "failed to parse form")
		return
	}

	file, header, err := c.Request.FormFile("avatar")
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "avatar file is required")
		return
	}
	defer file.Close()

	_, filename, err := h.MediaStore.SaveMedia(userID, file, header, 10<<20)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	user, err := models.GetUserByID(h.DB, userID)
	if err != nil {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + filename)
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	// Delete old avatar file if present
	if user.AvatarFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + user.AvatarFilename)
	}

	user.AvatarFilename = filename
	if err := models.UpdateUser(h.DB, user); err != nil {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + filename)
		utils.RespondError(c, http.StatusInternalServerError, "failed to update avatar")
		return
	}

	user.PasswordHash = ""
	utils.RespondJSON(c, http.StatusOK, user)
}

// GetUserStories returns active stories for a specific user, paginated by ?page and ?limit.
func (h *UserHandler) GetUserStories(c *gin.Context) {
	requestingUserID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	if _, err := models.GetUserByID(h.DB, id); err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "user not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve user")
		return
	}

	page := utils.GetPagination(c)
	stories, err := models.GetStoriesByUser(h.DB, id, requestingUserID, page.Limit, page.Offset)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve stories")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"stories": stories})
}

// GetStats returns platform statistics (admin only).
func (h *UserHandler) GetStats(c *gin.Context) {
	if !c.GetBool("is_admin") {
		utils.RespondError(c, http.StatusForbidden, "admin access required")
		return
	}

	var totalUsers, totalPosts, activeStories int

	err := h.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&totalUsers)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve stats")
		return
	}

	err = h.DB.QueryRow(`SELECT COUNT(*) FROM posts`).Scan(&totalPosts)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve stats")
		return
	}

	err = h.DB.QueryRow(`SELECT COUNT(*) FROM stories WHERE expires_at > datetime('now')`).Scan(&activeStories)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve stats")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"total_users":    totalUsers,
		"total_posts":    totalPosts,
		"active_stories": activeStories,
	})
}

// sanitizeUsername trims and validates a username.
func sanitizeUsername(s string) string {
	return strings.TrimSpace(s)
}

// sanitizeDisplayName trims a display name.
func sanitizeDisplayName(s string) string {
	return strings.TrimSpace(s)
}

// isUniqueViolation checks if an error is a SQLite unique constraint violation.
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	return strings.Contains(err.Error(), "UNIQUE constraint failed")
}

// getUserMediaFiles retrieves all media file paths for a user from posts and stories.
func getUserMediaFiles(db *sql.DB, userID int64) ([]string, error) {
	var files []string

	rows, err := db.Query(`SELECT media_filename FROM posts WHERE user_id = ?`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var fn string
		if err := rows.Scan(&fn); err != nil {
			return nil, err
		}
		if fn != "" {
			files = append(files, fmt.Sprintf("%d/%s", userID, fn))
		}
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	rows2, err := db.Query(`SELECT media_filename FROM stories WHERE user_id = ?`, userID)
	if err != nil {
		return nil, err
	}
	defer rows2.Close()

	for rows2.Next() {
		var fn string
		if err := rows2.Scan(&fn); err != nil {
			return nil, err
		}
		if fn != "" {
			files = append(files, fmt.Sprintf("%d/%s", userID, fn))
		}
	}
	if err := rows2.Err(); err != nil {
		return nil, err
	}

	return files, nil
}
