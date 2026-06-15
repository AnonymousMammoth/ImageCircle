package models

import (
	"database/sql"
	"fmt"
	"time"
)

// rowScanner is a common interface for sql.Row and sql.Rows.
type rowScanner interface {
	Scan(dest ...interface{}) error
}

// Comment represents a text reply on a post.
type Comment struct {
	ID        int64     `json:"id"`
	PostID    int64     `json:"post_id"`
	UserID    int64     `json:"user_id"`
	User      *User     `json:"user,omitempty"`
	Text      string    `json:"text"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateComment inserts a new comment and returns the created record.
// It verifies the post exists inside the transaction to avoid TOCTOU races.
func CreateComment(db *sql.DB, postID, userID int64, text string) (*Comment, error) {
	tx, err := db.Begin()
	if err != nil {
		return nil, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	var postExists bool
	if err := tx.QueryRow(`SELECT EXISTS(SELECT 1 FROM posts WHERE id = ?)`, postID).Scan(&postExists); err != nil {
		return nil, fmt.Errorf("check post exists: %w", err)
	}
	if !postExists {
		return nil, sql.ErrNoRows
	}

	result, err := tx.Exec(`
		INSERT INTO comments (post_id, user_id, text)
		VALUES (?, ?, ?)
	`, postID, userID, text)
	if err != nil {
		return nil, fmt.Errorf("insert comment: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	comment, err := getCommentByIDTx(tx, id)
	if err != nil {
		return nil, err
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit comment: %w", err)
	}

	return comment, nil
}

// GetCommentsByPost retrieves comments for a post ordered by created_at descending,
// paginated by limit and offset. Includes user info for each comment.
func GetCommentsByPost(db *sql.DB, postID int64, limit, offset int) ([]*Comment, error) {
	query := `
		SELECT
			c.id, c.post_id, c.user_id, c.text, c.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at
		FROM comments c
		JOIN users u ON c.user_id = u.id
		WHERE c.post_id = ?
		ORDER BY c.created_at DESC
		LIMIT ? OFFSET ?
	`
	rows, err := db.Query(query, postID, limit, offset)
	if err != nil {
		return nil, fmt.Errorf("query comments by post: %w", err)
	}
	defer rows.Close()

	return scanComments(rows)
}

// GetCommentByID retrieves a single comment by primary key.
func GetCommentByID(db *sql.DB, id int64) (*Comment, error) {
	query := `
		SELECT
			c.id, c.post_id, c.user_id, c.text, c.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at
		FROM comments c
		JOIN users u ON c.user_id = u.id
		WHERE c.id = ?
	`
	row := db.QueryRow(query, id)
	return scanComment(row)
}

// getCommentByIDTx retrieves a single comment by primary key within a transaction.
func getCommentByIDTx(tx *sql.Tx, id int64) (*Comment, error) {
	query := `
		SELECT
			c.id, c.post_id, c.user_id, c.text, c.created_at,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at
		FROM comments c
		JOIN users u ON c.user_id = u.id
		WHERE c.id = ?
	`
	row := tx.QueryRow(query, id)
	return scanComment(row)
}

// DeleteComment removes a comment by primary key.
func DeleteComment(db *sql.DB, id int64) error {
	query := `DELETE FROM comments WHERE id = ?`
	result, err := db.Exec(query, id)
	if err != nil {
		return fmt.Errorf("delete comment: %w", err)
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

// scanComment scans a single comment row with user info.
func scanComment(row rowScanner) (*Comment, error) {
	var c Comment
	var u User
	var isAdminInt int
	var passwordChangeRequiredInt int
	var avatarFilename sql.NullString

	err := row.Scan(
		&c.ID,
		&c.PostID,
		&c.UserID,
		&c.Text,
		&c.CreatedAt,
		&u.ID,
		&u.Username,
		&u.DisplayName,
		&isAdminInt,
		&passwordChangeRequiredInt,
		&avatarFilename,
		&u.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("scan comment: %w", err)
	}

	u.IsAdmin = isAdminInt != 0
	u.PasswordChangeRequired = passwordChangeRequiredInt != 0
	u.AvatarFilename = avatarFilename.String
	u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
	c.User = &u

	return &c, nil
}

// scanComments scans multiple comment rows.
func scanComments(rows *sql.Rows) ([]*Comment, error) {
	comments := make([]*Comment, 0)

	for rows.Next() {
		var c Comment
		var u User
		var isAdminInt int
		var passwordChangeRequiredInt int
		var avatarFilename sql.NullString

		err := rows.Scan(
			&c.ID,
			&c.PostID,
			&c.UserID,
			&c.Text,
			&c.CreatedAt,
			&u.ID,
			&u.Username,
			&u.DisplayName,
			&isAdminInt,
			&passwordChangeRequiredInt,
			&avatarFilename,
			&u.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scan comment row: %w", err)
		}

		u.IsAdmin = isAdminInt != 0
		u.PasswordChangeRequired = passwordChangeRequiredInt != 0
		u.AvatarFilename = avatarFilename.String
		u.AvatarURL = BuildAvatarURL(u.ID, u.AvatarFilename)
		c.User = &u

		comments = append(comments, &c)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return comments, nil
}
