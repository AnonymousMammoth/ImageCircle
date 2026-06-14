package handlers

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/utils"
)

// CommentHandler handles comment endpoints.
type CommentHandler struct {
	DB *sql.DB
}

// CreateCommentRequest represents a request to create a comment.
type CreateCommentRequest struct {
	Text string `json:"text"`
}

// ListComments returns all comments for a post.
func (h *CommentHandler) ListComments(c *gin.Context) {
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid post id")
		return
	}

	// Verify post exists
	_, err = models.GetPostByID(h.DB, postID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve post")
		return
	}

	comments, err := models.GetCommentsByPost(h.DB, postID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve comments")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"comments": comments})
}

// CreateComment creates a new comment on a post.
func (h *CommentHandler) CreateComment(c *gin.Context) {
	userID := c.GetInt64("user_id")

	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid post id")
		return
	}

	var req CreateCommentRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Text = strings.TrimSpace(req.Text)
	if req.Text == "" {
		utils.RespondError(c, http.StatusBadRequest, "text is required")
		return
	}
	if len(req.Text) > 1000 {
		utils.RespondError(c, http.StatusBadRequest, "text must be at most 1000 characters")
		return
	}

	// Verify post exists
	_, err = models.GetPostByID(h.DB, postID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve post")
		return
	}

	comment, err := models.CreateComment(h.DB, postID, userID, req.Text)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create comment")
		return
	}

	utils.RespondCreated(c, comment)
}

// DeleteComment deletes a comment.
func (h *CommentHandler) DeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Get comment to check ownership
	comment, err := models.GetCommentByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "comment not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve comment")
		return
	}

	if !checkOwnership(c, comment.UserID) {
		utils.RespondError(c, http.StatusForbidden, "not authorized to delete this comment")
		return
	}

	if err := models.DeleteComment(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete comment")
		return
	}

	utils.RespondNoContent(c)
}
