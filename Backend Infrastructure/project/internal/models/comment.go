package models

import (
	"database/sql"
	"fmt"
	"time"
)

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
func CreateComment(db *sql.DB, postID, userID int64, text string) (*Comment, error) {
	query := `
		INSERT INTO comments (post_id, user_id, text)
		VALUES (?, ?, ?)
	`
	result, err := db.Exec(query, postID, userID, text)
	if err != nil {
		return nil, fmt.Errorf("insert comment: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetCommentByID(db, id)
}

// GetCommentsByPost retrieves comments for a post ordered by created_at descending,
// paginated by limit and offset. Includes user info for each comment.
func GetCommentsByPost(db *sql.DB, postID int64, limit, offset int) ([]*Comment, error) {
	query := `
		SELECT
			c.id, c.post_id, c.user_id, c.text, c.created_at,
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.created_at
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
			u.id, u.username, u.display_name, u.password_hash, u.is_admin, u.password_change_required, u.created_at
		FROM comments c
		JOIN users u ON c.user_id = u.id
		WHERE c.id = ?
	`
	row := db.QueryRow(query, id)
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

// GetCommentCount returns the number of comments on a post.
func GetCommentCount(db *sql.DB, postID int64) (int, error) {
	query := `SELECT COUNT(*) FROM comments WHERE post_id = ?`
	var count int
	err := db.QueryRow(query, postID).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("count comments: %w", err)
	}
	return count, nil
}

// scanComment scans a single comment row with user info.
func scanComment(row *sql.Row) (*Comment, error) {
	var c Comment
	var u User
	var isAdminInt int
	var passwordChangeRequiredInt int

	err := row.Scan(
		&c.ID,
		&c.PostID,
		&c.UserID,
		&c.Text,
		&c.CreatedAt,
		&u.ID,
		&u.Username,
		&u.DisplayName,
		&u.PasswordHash,
		&isAdminInt,
		&passwordChangeRequiredInt,
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

		err := rows.Scan(
			&c.ID,
			&c.PostID,
			&c.UserID,
			&c.Text,
			&c.CreatedAt,
			&u.ID,
			&u.Username,
			&u.DisplayName,
			&u.PasswordHash,
			&isAdminInt,
			&passwordChangeRequiredInt,
			&u.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scan comment row: %w", err)
		}

		u.IsAdmin = isAdminInt != 0
		u.PasswordChangeRequired = passwordChangeRequiredInt != 0
		c.User = &u

		comments = append(comments, &c)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return comments, nil
}
