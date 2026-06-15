package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Post represents a user photo/video upload.
type Post struct {
	ID                int64     `json:"id"`
	UserID            int64     `json:"user_id"`
	User              *User     `json:"user,omitempty"`
	Caption           string    `json:"caption"`
	MediaFilename     string    `json:"media_filename"`
	MediaURL          string    `json:"media_url"`
	ThumbnailFilename string    `json:"thumbnail_filename"`
	ThumbnailURL      string    `json:"thumbnail_url"`
	LikeCount         int       `json:"likes_count"`
	CommentCount      int       `json:"comments_count"`
	HasLiked          bool      `json:"has_liked"`
	CreatedAt         time.Time `json:"created_at"`
}

// BuildMediaURL formats a media file URL.
func BuildMediaURL(userID int64, filename string) string {
	if filename == "" {
		return ""
	}
	return fmt.Sprintf("/media/%d/%s", userID, filename)
}

// BuildThumbnailURL formats a thumbnail file URL.
func BuildThumbnailURL(userID int64, filename string) string {
	if filename == "" {
		return ""
	}
	return fmt.Sprintf("/media/%d/%s", userID, filename)
}

// nullString returns a sql.NullString for an optional non-empty value.
func nullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

// CreatePost inserts a new post and returns the created record.
func CreatePost(db *sql.DB, userID int64, caption, mediaFilename, thumbnailFilename string) (*Post, error) {
	query := `
		INSERT INTO posts (user_id, caption, media_filename, thumbnail_filename)
		VALUES (?, ?, ?, ?)
	`
	result, err := db.Exec(query, userID, caption, nullString(mediaFilename), nullString(thumbnailFilename))
	if err != nil {
		return nil, fmt.Errorf("insert post: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetPostByID(db, id)
}

// GetPostByID retrieves a post by primary key with user info, like count, and comment count.
func GetPostByID(db *sql.DB, id int64) (*Post, error) {
	query := `
		SELECT
			p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
			(SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comment_count
		FROM posts p
		JOIN users u ON p.user_id = u.id
		WHERE p.id = ?
	`
	row := db.QueryRow(query, id)
	return scanPost(row, 0)
}

// GetPostByIDWithUserContext retrieves a post including whether the requesting user has liked it.
func GetPostByIDWithUserContext(db *sql.DB, id, requestingUserID int64) (*Post, error) {
	query := `
		SELECT
			p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
			(SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comment_count,
			EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = ?) AS has_liked
		FROM posts p
		JOIN users u ON p.user_id = u.id
		WHERE p.id = ?
	`
	row := db.QueryRow(query, requestingUserID, id)
	return scanPost(row, requestingUserID)
}

// GetFeed retrieves posts chronologically descending with engagement stats,
// paginated by limit and offset.
func GetFeed(db *sql.DB, requestingUserID int64, limit, offset int) ([]*Post, error) {
	query := `
		SELECT
			p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
			(SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comment_count,
			EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = ?) AS has_liked
		FROM posts p
		JOIN users u ON p.user_id = u.id
		ORDER BY p.created_at DESC
		LIMIT ? OFFSET ?
	`
	rows, err := db.Query(query, requestingUserID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query feed: %w", err)
	}
	defer rows.Close()

	return scanPosts(rows, requestingUserID)
}

// GetPostsByUser retrieves posts by a specific user with engagement stats,
// paginated by limit and offset.
func GetPostsByUser(db *sql.DB, userID, requestingUserID int64, limit, offset int) ([]*Post, error) {
	query := `
		SELECT
			p.id, p.user_id, p.caption, p.media_filename, p.thumbnail_filename, p.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM likes WHERE post_id = p.id) AS like_count,
			(SELECT COUNT(*) FROM comments WHERE post_id = p.id) AS comment_count,
			EXISTS(SELECT 1 FROM likes WHERE post_id = p.id AND user_id = ?) AS has_liked
		FROM posts p
		JOIN users u ON p.user_id = u.id
		WHERE p.user_id = ?
		ORDER BY p.created_at DESC
		LIMIT ? OFFSET ?
	`
	rows, err := db.Query(query, requestingUserID, userID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query posts by user: %w", err)
	}
	defer rows.Close()

	return scanPosts(rows, requestingUserID)
}

// DeletePost removes a post by primary key.
func DeletePost(db *sql.DB, id int64) error {
	query := `DELETE FROM posts WHERE id = ?`
	result, err := db.Exec(query, id)
	if err != nil {
		return fmt.Errorf("delete post: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return fmt.Errorf("rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return sql.ErrNoRows
	}

	return nil
}

// GetPostMediaFilename returns the media and thumbnail filenames for a post.
func GetPostMediaFilename(db *sql.DB, id int64) (string, string, error) {
	query := `SELECT media_filename, thumbnail_filename FROM posts WHERE id = ?`
	var mediaFilename, thumbnailFilename sql.NullString
	err := db.QueryRow(query, id).Scan(&mediaFilename, &thumbnailFilename)
	if err != nil {
		return "", "", fmt.Errorf("select media filename: %w", err)
	}
	return mediaFilename.String, thumbnailFilename.String, nil
}

// scanPost scans a single post row. If requestingUserID > 0, scans has_liked column.
func scanPost(row *sql.Row, requestingUserID int64) (*Post, error) {
	var p Post
	var u User
	var isAdminInt int
	var passwordChangeRequiredInt int
	var mediaFilename, thumbnailFilename, avatarFilename sql.NullString

	var scanTargets = []interface{}{
		&p.ID,
		&p.UserID,
		&p.Caption,
		&mediaFilename,
		&thumbnailFilename,
		&p.CreatedAt,
		&u.ID,
		&u.Username,
		&u.DisplayName,
		&isAdminInt,
		&passwordChangeRequiredInt,
		&avatarFilename,
		&u.CreatedAt,
		&p.LikeCount,
		&p.CommentCount,
	}

	if requestingUserID > 0 {
		scanTargets = append(scanTargets, &p.HasLiked)
	}

	err := row.Scan(scanTargets...)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("scan post: %w", err)
	}

	u.IsAdmin = isAdminInt != 0
	u.PasswordChangeRequired = passwordChangeRequiredInt != 0
	u.AvatarFilename = avatarFilename.String
	u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
	p.User = &u

	p.MediaFilename = mediaFilename.String
	p.ThumbnailFilename = thumbnailFilename.String
	p.MediaURL = BuildMediaURL(p.UserID, p.MediaFilename)
	p.ThumbnailURL = BuildThumbnailURL(p.UserID, p.ThumbnailFilename)

	return &p, nil
}

// scanPosts scans multiple post rows.
func scanPosts(rows *sql.Rows, requestingUserID int64) ([]*Post, error) {
	posts := make([]*Post, 0)

	for rows.Next() {
		var p Post
		var u User
		var isAdminInt int
		var passwordChangeRequiredInt int
		var mediaFilename, thumbnailFilename, avatarFilename sql.NullString

		var scanTargets = []interface{}{
			&p.ID,
			&p.UserID,
			&p.Caption,
			&mediaFilename,
			&thumbnailFilename,
			&p.CreatedAt,
			&u.ID,
			&u.Username,
			&u.DisplayName,
			&isAdminInt,
			&passwordChangeRequiredInt,
			&avatarFilename,
			&u.CreatedAt,
			&p.LikeCount,
			&p.CommentCount,
		}

		if requestingUserID > 0 {
			scanTargets = append(scanTargets, &p.HasLiked)
		}

		err := rows.Scan(scanTargets...)
		if err != nil {
			return nil, fmt.Errorf("scan post row: %w", err)
		}

		u.IsAdmin = isAdminInt != 0
		u.PasswordChangeRequired = passwordChangeRequiredInt != 0
		u.AvatarFilename = avatarFilename.String
		u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
		p.User = &u

		p.MediaFilename = mediaFilename.String
		p.ThumbnailFilename = thumbnailFilename.String
		p.MediaURL = BuildMediaURL(p.UserID, p.MediaFilename)
		p.ThumbnailURL = BuildThumbnailURL(p.UserID, p.ThumbnailFilename)

		posts = append(posts, &p)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return posts, nil
}
