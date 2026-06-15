package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/utils"
)

// LikeHandler handles like endpoints.
type LikeHandler struct {
	DB *sql.DB
}

// ToggleLike toggles a like on a post for the current user.
func (h *LikeHandler) ToggleLike(c *gin.Context) {
	userID := c.GetInt64("user_id")

	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid post id")
		return
	}

	liked, err := models.ToggleLike(h.DB, postID, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to toggle like")
		return
	}

	likeCount, err := models.GetLikeCount(h.DB, postID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to get like count")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"liked":      liked,
		"like_count": likeCount,
	})
}
