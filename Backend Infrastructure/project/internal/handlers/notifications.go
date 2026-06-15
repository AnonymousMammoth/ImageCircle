package handlers

import (
	"database/sql"
	"net/http"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/utils"
)

// NotificationHandler handles notification endpoints.
type NotificationHandler struct {
	DB *sql.DB
}

// ListNotifications returns likes and comments on the current user's posts.
func (h *NotificationHandler) ListNotifications(c *gin.Context) {
	userID := c.GetInt64("user_id")

	page := utils.GetPagination(c)
	notifications, err := models.GetNotifications(h.DB, userID, page.Limit, page.Offset)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve notifications")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"notifications": notifications})
}
