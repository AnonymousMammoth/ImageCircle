package models

import (
	"database/sql"
	"fmt"
)

// ToggleLike adds or removes a like for a post by a user.
// Returns true if the post is now liked, false if unliked.
func ToggleLike(db *sql.DB, postID, userID int64) (bool, error) {
	tx, err := db.Begin()
	if err != nil {
		return false, fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Check if like already exists
	var existingID int64
	checkQuery := `SELECT id FROM likes WHERE post_id = ? AND user_id = ?`
	err = tx.QueryRow(checkQuery, postID, userID).Scan(&existingID)

	if err != nil && err != sql.ErrNoRows {
		return false, fmt.Errorf("check existing like: %w", err)
	}

	if err == sql.ErrNoRows {
		// Not liked yet — insert
		insertQuery := `
			INSERT INTO likes (post_id, user_id)
			VALUES (?, ?)
		`
		_, err = tx.Exec(insertQuery, postID, userID)
		if err != nil {
			return false, fmt.Errorf("insert like: %w", err)
		}
		if commitErr := tx.Commit(); commitErr != nil {
			return false, fmt.Errorf("commit insert: %w", commitErr)
		}
		return true, nil
	}

	// Already liked — delete
	deleteQuery := `DELETE FROM likes WHERE id = ?`
	_, err = tx.Exec(deleteQuery, existingID)
	if err != nil {
		return false, fmt.Errorf("delete like: %w", err)
	}
	if commitErr := tx.Commit(); commitErr != nil {
		return false, fmt.Errorf("commit delete: %w", commitErr)
	}
	return false, nil
}

// GetLikeCount returns the number of likes for a post.
func GetLikeCount(db *sql.DB, postID int64) (int, error) {
	query := `SELECT COUNT(*) FROM likes WHERE post_id = ?`
	var count int
	err := db.QueryRow(query, postID).Scan(&count)
	if err != nil {
		return 0, fmt.Errorf("count likes: %w", err)
	}
	return count, nil
}

// HasLiked checks whether a user has liked a post.
func HasLiked(db *sql.DB, postID, userID int64) (bool, error) {
	query := `SELECT 1 FROM likes WHERE post_id = ? AND user_id = ?`
	var dummy int
	err := db.QueryRow(query, postID, userID).Scan(&dummy)
	if err != nil {
		if err == sql.ErrNoRows {
			return false, nil
		}
		return false, fmt.Errorf("check liked: %w", err)
	}
	return true, nil
}
