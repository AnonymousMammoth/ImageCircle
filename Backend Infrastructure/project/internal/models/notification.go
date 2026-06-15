package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Notification represents an activity item for the owner of a post
// (a like or a comment from another user).
type Notification struct {
	ID        int64                `json:"id"`
	Type      string               `json:"type"`
	Actor     *User                `json:"actor"`
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

// GetNotifications returns likes and comments on the given user's posts,
// ordered by created_at descending and paginated by limit/offset.
func GetNotifications(db *sql.DB, userID int64, limit, offset int) ([]*Notification, error) {
	query := `
		SELECT * FROM (
			SELECT
				l.id, 'like' AS type, l.created_at,
				actor.id, actor.username, actor.display_name, actor.is_admin, actor.password_change_required, actor.avatar_filename, actor.created_at,
				p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
				NULL AS comment_id, NULL AS comment_text, NULL AS comment_created_at
			FROM likes l
			JOIN posts p ON l.post_id = p.id
			JOIN users actor ON l.user_id = actor.id
			WHERE p.user_id = ?

			UNION ALL

			SELECT
				c.id, 'comment' AS type, c.created_at,
				actor.id, actor.username, actor.display_name, actor.is_admin, actor.password_change_required, actor.avatar_filename, actor.created_at,
				p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
				c.id, c.text, c.created_at
			FROM comments c
			JOIN posts p ON c.post_id = p.id
			JOIN users actor ON c.user_id = actor.id
			WHERE p.user_id = ?
		)
		ORDER BY created_at DESC
		LIMIT ? OFFSET ?
	`

	rows, err := db.Query(query, userID, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query notifications: %w", err)
	}
	defer rows.Close()

	return scanNotifications(rows)
}

func scanNotifications(rows *sql.Rows) ([]*Notification, error) {
	notifications := make([]*Notification, 0)

	for rows.Next() {
		var n Notification
		var actor User
		var post NotificationPost
		var actorAvatar, mediaFilename, thumbnailFilename sql.NullString
		var actorCreatedAt sql.NullTime
		var actorPasswordChangeRequiredInt int
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
			&actor.IsAdmin,
			&actorPasswordChangeRequiredInt,
			&actorAvatar,
			&actorCreatedAt,
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

		actor.PasswordChangeRequired = actorPasswordChangeRequiredInt != 0
		actor.AvatarFilename = actorAvatar.String
		actor.AvatarURL = BuildAvatarURL(actor.ID, actor.AvatarFilename)
		actor.CreatedAt = actorCreatedAt.Time
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
