package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Story represents ephemeral photo/video content.
type Story struct {
	ID                int64     `json:"id"`
	UserID            int64     `json:"user_id"`
	User              *User     `json:"user,omitempty"`
	MediaFilename     string    `json:"media_filename"`
	MediaURL          string    `json:"media_url"`
	ThumbnailFilename string    `json:"thumbnail_filename"`
	ThumbnailURL      string    `json:"thumbnail_url"`
	MediaType         string    `json:"media_type"`
	CreatedAt         time.Time `json:"created_at"`
	ExpiresAt         time.Time `json:"expires_at"`
	Viewed            bool      `json:"viewed"`
	ViewCount         int       `json:"view_count"`
}

// CreateStory inserts a new story and returns the created record.
func CreateStory(db *sql.DB, userID int64, mediaFilename, thumbnailFilename, mediaType string, expiresAt time.Time) (*Story, error) {
	query := `
		INSERT INTO stories (user_id, media_filename, thumbnail_filename, media_type, expires_at)
		VALUES (?, ?, ?, ?, ?)
	`
	result, err := db.Exec(query, userID, mediaFilename, thumbnailFilename, mediaType, expiresAt)
	if err != nil {
		return nil, fmt.Errorf("insert story: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetStoryByID(db, id)
}

// GetActiveStories retrieves non-expired stories not viewed by the requesting user,
// ordered by created_at descending. Includes user info and view count.
func GetActiveStories(db *sql.DB, requestingUserID int64) ([]*Story, error) {
	query := `
		SELECT
			s.id, s.user_id, s.media_filename, s.thumbnail_filename, s.media_type, s.created_at, s.expires_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.created_at,
			(SELECT COUNT(*) FROM story_views WHERE story_id = s.id) AS view_count
		FROM stories s
		JOIN users u ON s.user_id = u.id
		WHERE s.expires_at > datetime('now')
		  AND s.user_id != ?
		  AND NOT EXISTS (
			  SELECT 1 FROM story_views sv
			  WHERE sv.story_id = s.id AND sv.user_id = ?
		  )
		ORDER BY s.created_at DESC
	`
	rows, err := db.Query(query, requestingUserID, requestingUserID)
	if err != nil {
		return nil, fmt.Errorf("query active stories: %w", err)
	}
	defer rows.Close()

	// All returned rows are unviewed because of the NOT EXISTS filter.
	return scanStories(rows, 0)
}

// GetStoriesByUser retrieves active stories for a specific user.
func GetStoriesByUser(db *sql.DB, userID, requestingUserID int64) ([]*Story, error) {
	query := `
		SELECT
			s.id, s.user_id, s.media_filename, s.thumbnail_filename, s.media_type, s.created_at, s.expires_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM story_views WHERE story_id = s.id) AS view_count,
			EXISTS(SELECT 1 FROM story_views WHERE story_id = s.id AND user_id = ?) AS viewed
		FROM stories s
		JOIN users u ON s.user_id = u.id
		WHERE s.user_id = ?
		  AND s.expires_at > datetime('now')
		ORDER BY s.created_at DESC
	`
	rows, err := db.Query(query, requestingUserID, userID)
	if err != nil {
		return nil, fmt.Errorf("query user stories: %w", err)
	}
	defer rows.Close()

	stories, err := scanStories(rows, requestingUserID)
	if err != nil {
		return nil, err
	}

	// Own stories should always appear unviewed in the tray.
	if userID == requestingUserID {
		for _, s := range stories {
			s.Viewed = false
		}
	}
	return stories, nil
}

// GetStoryByID retrieves a story by primary key with user info.
func GetStoryByID(db *sql.DB, id int64) (*Story, error) {
	query := `
		SELECT
			s.id, s.user_id, s.media_filename, s.thumbnail_filename, s.media_type, s.created_at, s.expires_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM story_views WHERE story_id = s.id) AS view_count
		FROM stories s
		JOIN users u ON s.user_id = u.id
		WHERE s.id = ?
	`
	row := db.QueryRow(query, id)
	return scanStory(row, 0)
}

// GetStoryByIDWithUserContext retrieves a story including whether the requesting user has viewed it.
func GetStoryByIDWithUserContext(db *sql.DB, id, requestingUserID int64) (*Story, error) {
	query := `
		SELECT
			s.id, s.user_id, s.media_filename, s.thumbnail_filename, s.media_type, s.created_at, s.expires_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM story_views WHERE story_id = s.id) AS view_count,
			EXISTS(SELECT 1 FROM story_views WHERE story_id = s.id AND user_id = ?) AS viewed
		FROM stories s
		JOIN users u ON s.user_id = u.id
		WHERE s.id = ?
	`
	row := db.QueryRow(query, requestingUserID, id)
	return scanStory(row, requestingUserID)
}

// MarkStoryViewed records that a user has viewed a story. Ignores duplicate views.
func MarkStoryViewed(db *sql.DB, storyID, userID int64) error {
	query := `
		INSERT OR IGNORE INTO story_views (story_id, user_id)
		VALUES (?, ?)
	`
	_, err := db.Exec(query, storyID, userID)
	if err != nil {
		return fmt.Errorf("mark story viewed: %w", err)
	}
	return nil
}

// DeleteStory removes a story by primary key.
func DeleteStory(db *sql.DB, id int64) error {
	query := `DELETE FROM stories WHERE id = ?`
	result, err := db.Exec(query, id)
	if err != nil {
		return fmt.Errorf("delete story: %w", err)
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

// GetExpiredStories retrieves stories where expires_at has passed.
func GetExpiredStories(db *sql.DB) ([]*Story, error) {
	query := `
		SELECT
			s.id, s.user_id, s.media_filename, s.thumbnail_filename, s.media_type, s.created_at, s.expires_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at,
			(SELECT COUNT(*) FROM story_views WHERE story_id = s.id) AS view_count
		FROM stories s
		JOIN users u ON s.user_id = u.id
		WHERE s.expires_at <= datetime('now')
		ORDER BY s.created_at DESC
	`
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("query expired stories: %w", err)
	}
	defer rows.Close()

	return scanStories(rows, 0)
}

// GetStoryMediaFilename returns the media and thumbnail filenames for a story.
func GetStoryMediaFilename(db *sql.DB, id int64) (string, string, error) {
	query := `SELECT media_filename, thumbnail_filename FROM stories WHERE id = ?`
	var mediaFilename, thumbnailFilename string
	err := db.QueryRow(query, id).Scan(&mediaFilename, &thumbnailFilename)
	if err != nil {
		return "", "", fmt.Errorf("select story media filename: %w", err)
	}
	return mediaFilename, thumbnailFilename, nil
}

// scanStory scans a single story row.
func scanStory(row *sql.Row, requestingUserID int64) (*Story, error) {
	var s Story
	var u User
	var isAdminInt int
	var passwordChangeRequiredInt int
	var avatarFilename sql.NullString

	scanTargets := []interface{}{
		&s.ID,
		&s.UserID,
		&s.MediaFilename,
		&s.ThumbnailFilename,
		&s.MediaType,
		&s.CreatedAt,
		&s.ExpiresAt,
		&u.ID,
		&u.Username,
		&u.DisplayName,
		&u.PasswordHash,
		&isAdminInt,
		&passwordChangeRequiredInt,
		&avatarFilename,
		&u.CreatedAt,
		&s.ViewCount,
	}

	if requestingUserID > 0 {
		scanTargets = append(scanTargets, &s.Viewed)
	}

	err := row.Scan(scanTargets...)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("scan story: %w", err)
	}

	u.IsAdmin = isAdminInt != 0
	u.PasswordChangeRequired = passwordChangeRequiredInt != 0
	u.AvatarFilename = avatarFilename.String
	u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
	s.User = &u

	s.MediaURL = BuildMediaURL(s.UserID, s.MediaFilename)
	if s.ThumbnailFilename != "" {
		s.ThumbnailURL = BuildThumbnailURL(s.UserID, s.ThumbnailFilename)
	}

	return &s, nil
}

// scanStories scans multiple story rows.
func scanStories(rows *sql.Rows, requestingUserID int64) ([]*Story, error) {
	var stories []*Story

	for rows.Next() {
		var s Story
		var u User
		var isAdminInt int
		var passwordChangeRequiredInt int
		var avatarFilename sql.NullString

		scanTargets := []interface{}{
			&s.ID,
			&s.UserID,
			&s.MediaFilename,
			&s.ThumbnailFilename,
			&s.MediaType,
			&s.CreatedAt,
			&s.ExpiresAt,
			&u.ID,
			&u.Username,
			&u.DisplayName,
			&u.PasswordHash,
			&isAdminInt,
			&passwordChangeRequiredInt,
			&avatarFilename,
			&u.CreatedAt,
			&s.ViewCount,
		}

		if requestingUserID > 0 {
			scanTargets = append(scanTargets, &s.Viewed)
		}

		err := rows.Scan(scanTargets...)
		if err != nil {
			return nil, fmt.Errorf("scan story row: %w", err)
		}

		u.IsAdmin = isAdminInt != 0
		u.PasswordChangeRequired = passwordChangeRequiredInt != 0
		u.AvatarFilename = avatarFilename.String
		u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
		s.User = &u

		s.MediaURL = BuildMediaURL(s.UserID, s.MediaFilename)
		if s.ThumbnailFilename != "" {
			s.ThumbnailURL = BuildThumbnailURL(s.UserID, s.ThumbnailFilename)
		}

		stories = append(stories, &s)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return stories, nil
}
