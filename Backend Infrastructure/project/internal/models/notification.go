package models

import (
	"database/sql"
	"fmt"
	"strings"
	"time"
)

// NotificationActor is a minimal, privacy-safe actor representation used in
// notification payloads. It intentionally omits admin flags and account status.
type NotificationActor struct {
	ID          int64  `json:"id"`
	Username    string `json:"username"`
	DisplayName string `json:"display_name"`
	AvatarURL   string `json:"avatar_url"`
}

// Notification represents an activity item for the owner of a post
// (a like, comment, or @mention from another user).
type Notification struct {
	ID        string               `json:"id"`
	Type      string               `json:"type"`
	Actor     *NotificationActor   `json:"actor"`
	Post      *NotificationPost    `json:"post"`
	Comment   *NotificationComment `json:"comment,omitempty"`
	CreatedAt time.Time            `json:"created_at"`
}

// NotificationPost is a minimal post representation used in notifications.
type NotificationPost struct {
	ID           int64     `json:"id"`
	UserID       int64     `json:"user_id"`
	Caption      string    `json:"caption"`
	MediaURL     string    `json:"media_url"`
	ThumbnailURL string    `json:"thumbnail_url"`
	CreatedAt    time.Time `json:"created_at"`
}

// NotificationComment is a minimal comment representation used in notifications.
type NotificationComment struct {
	ID        int64     `json:"id"`
	Text      string    `json:"text"`
	CreatedAt time.Time `json:"created_at"`
}

// GetNotifications returns likes, comments, and explicit notifications for the
// given user, ordered by created_at descending and paginated by limit/offset.
func GetNotifications(db *sql.DB, userID int64, limit, offset int) ([]*Notification, error) {
	query := `
		SELECT * FROM (
			SELECT
				'like:' || l.id AS id, 'like' AS type, l.created_at,
				actor.id, actor.username, actor.display_name, actor.avatar_filename,
				p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
				NULL AS comment_id, NULL AS comment_text, NULL AS comment_created_at
			FROM likes l
			JOIN posts p ON l.post_id = p.id
			JOIN users actor ON l.user_id = actor.id
			WHERE p.user_id = ?

			UNION ALL

			SELECT
				'comment:' || c.id AS id, 'comment' AS type, c.created_at,
				actor.id, actor.username, actor.display_name, actor.avatar_filename,
				p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
				c.id, c.text, c.created_at
			FROM comments c
			JOIN posts p ON c.post_id = p.id
			JOIN users actor ON c.user_id = actor.id
			WHERE p.user_id = ?

			UNION ALL

			SELECT
				n.type || ':' || n.id AS id, n.type, n.created_at,
				actor.id, actor.username, actor.display_name, actor.avatar_filename,
				p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
				c.id, c.text, c.created_at
			FROM notifications n
			JOIN users actor ON n.actor_id = actor.id
			JOIN posts p ON n.post_id = p.id
			LEFT JOIN comments c ON n.comment_id = c.id
			WHERE n.user_id = ?
		)
		ORDER BY created_at DESC
		LIMIT ? OFFSET ?
	`

	rows, err := db.Query(query, userID, userID, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	return scanNotifications(rows)
}

// GetUnreadNotificationCount returns the number of unread explicit notifications
// for the given user.
func GetUnreadNotificationCount(db *sql.DB, userID int64) (int, error) {
	var count int
	query := `SELECT COUNT(*) FROM notifications WHERE user_id = ? AND is_read = 0`
	if err := db.QueryRow(query, userID).Scan(&count); err != nil {
		return 0, fmt.Errorf("count unread notifications: %w", err)
	}
	return count, nil
}

// CreateNotification inserts an explicit notification row.
func CreateNotification(db *sql.DB, recipientID, actorID int64, ntype string, postID, commentID int64, textPreview string) error {
	var postIDVal, commentIDVal sql.NullInt64
	if postID > 0 {
		postIDVal = sql.NullInt64{Int64: postID, Valid: true}
	}
	if commentID > 0 {
		commentIDVal = sql.NullInt64{Int64: commentID, Valid: true}
	}
	preview := textPreview
	if len(preview) > 200 {
		preview = preview[:200]
	}
	preview = strings.TrimSpace(preview)

	_, err := db.Exec(`
		INSERT INTO notifications (user_id, actor_id, type, post_id, comment_id, text_preview)
		VALUES (?, ?, ?, ?, ?, ?)
	`, recipientID, actorID, ntype, postIDVal, commentIDVal, preview)
	if err != nil {
		return fmt.Errorf("insert notification: %w", err)
	}
	return nil
}

func scanNotifications(rows *sql.Rows) ([]*Notification, error) {
	notifications := make([]*Notification, 0)

	for rows.Next() {
		var n Notification
		var actor NotificationActor
		var post NotificationPost
		var actorAvatar, mediaFilename, thumbnailFilename sql.NullString
		var commentID sql.NullInt64
		var commentText sql.NullString
		var commentCreatedAt sql.NullTime

		err := rows.Scan(
			&n.ID,
			&n.Type,
			&n.CreatedAt,
			&actor.ID,
			&actor.Username,
			&actor.DisplayName,
			&actorAvatar,
			&post.ID,
			&post.UserID,
			&post.Caption,
			&mediaFilename,
			&thumbnailFilename,
			&post.CreatedAt,
			&commentID,
			&commentText,
			&commentCreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scan notification row: %w", err)
		}

		actor.AvatarURL = BuildAvatarURL(actor.ID, actorAvatar.String)
		n.Actor = &actor

		post.MediaURL = BuildMediaURL(post.UserID, mediaFilename.String)
		post.ThumbnailURL = BuildThumbnailURL(post.UserID, thumbnailFilename.String)
		n.Post = &post

		if commentID.Valid {
			n.Comment = &NotificationComment{
				ID:        commentID.Int64,
				Text:      commentText.String,
				CreatedAt: commentCreatedAt.Time,
			}
		}

		notifications = append(notifications, &n)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return notifications, nil
}
