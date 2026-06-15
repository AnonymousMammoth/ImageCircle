package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Block represents a one-way user block.
type Block struct {
	ID        int64     `json:"id"`
	BlockerID int64     `json:"blocker_id"`
	BlockedID int64     `json:"blocked_id"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateBlock records that blockerID has blocked blockedID.
// Returns sql.ErrNoRows if the blocked user does not exist.
func CreateBlock(db *sql.DB, blockerID, blockedID int64) error {
	// Verify the blocked user exists.
	var exists bool
	if err := db.QueryRow(`SELECT EXISTS(SELECT 1 FROM users WHERE id = ?)`, blockedID).Scan(&exists); err != nil {
		return fmt.Errorf("check blocked user exists: %w", err)
	}
	if !exists {
		return sql.ErrNoRows
	}

	query := `
		INSERT OR IGNORE INTO blocks (blocker_id, blocked_id)
		VALUES (?, ?)
	`
	_, err := db.Exec(query, blockerID, blockedID)
	if err != nil {
		return fmt.Errorf("insert block: %w", err)
	}
	return nil
}

// DeleteBlock removes a block. It is idempotent and does not error if no row exists.
func DeleteBlock(db *sql.DB, blockerID, blockedID int64) error {
	query := `DELETE FROM blocks WHERE blocker_id = ? AND blocked_id = ?`
	_, err := db.Exec(query, blockerID, blockedID)
	if err != nil {
		return fmt.Errorf("delete block: %w", err)
	}
	return nil
}

// GetBlockedUserIDs returns the set of user IDs blocked by blockerID.
func GetBlockedUserIDs(db *sql.DB, blockerID int64) ([]int64, error) {
	query := `
		SELECT blocked_id FROM blocks
		WHERE blocker_id = ?
		ORDER BY created_at DESC
	`
	rows, err := db.Query(query, blockerID)
	if err != nil {
		return nil, fmt.Errorf("query blocked user ids: %w", err)
	}
	defer rows.Close()

	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("scan blocked user id: %w", err)
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}
	return ids, nil
}

// IsBlocked reports whether blockerID has blocked blockedID.
func IsBlocked(db *sql.DB, blockerID, blockedID int64) (bool, error) {
	var exists bool
	query := `SELECT EXISTS(SELECT 1 FROM blocks WHERE blocker_id = ? AND blocked_id = ?)`
	err := db.QueryRow(query, blockerID, blockedID).Scan(&exists)
	if err != nil {
		return false, fmt.Errorf("check blocked: %w", err)
	}
	return exists, nil
}
