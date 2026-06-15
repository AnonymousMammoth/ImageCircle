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

// ListNotifications returns likes, comments, and explicit notifications for the current user.
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

// UnreadCount returns the number of unread explicit notifications for the current user.
func (h *NotificationHandler) UnreadCount(c *gin.Context) {
	userID := c.GetInt64("user_id")

	count, err := models.GetUnreadNotificationCount(h.DB, userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve unread count")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"count": count})
}

// createMentionNotifications parses @username mentions in text and inserts a
// notification for each valid, non-blocked user other than the actor.
func createMentionNotifications(db *sql.DB, actorID int64, ntype string, postID, commentID int64, text string) {
	usernames := utils.ExtractMentions(text)
	if len(usernames) == 0 {
		return
	}

	for _, username := range usernames {
		user, err := models.GetUserByUsername(db, username)
		if err != nil || user == nil || user.ID == actorID {
			continue
		}

		// Respect blocks in either direction.
		if blocked, _ := models.IsBlocked(db, user.ID, actorID); blocked {
			continue
		}
		if blocked, _ := models.IsBlocked(db, actorID, user.ID); blocked {
			continue
		}

		_ = models.CreateNotification(db, user.ID, actorID, ntype, postID, commentID, text)
	}
}
