package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Session represents an authenticated user session.
type Session struct {
	ID        int64     `json:"id"`
	UserID    int64     `json:"user_id"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
	CreatedAt time.Time `json:"created_at"`
}

// CreateSession inserts a new session token.
func CreateSession(db *sql.DB, userID int64, token string, expiresAt time.Time) error {
	query := `
		INSERT INTO sessions (user_id, token, expires_at)
		VALUES (?, ?, ?)
	`
	_, err := db.Exec(query, userID, token, expiresAt)
	if err != nil {
		return fmt.Errorf("insert session: %w", err)
	}
	return nil
}

// GetSessionByToken retrieves a session by its token.
// Returns sql.ErrNoRows if the token is not found or has expired.
func GetSessionByToken(db *sql.DB, token string) (*Session, error) {
	query := `
		SELECT id, user_id, token, expires_at, created_at
		FROM sessions
		WHERE token = ? AND expires_at > datetime('now')
	`
	var s Session
	err := db.QueryRow(query, token).Scan(
		&s.ID,
		&s.UserID,
		&s.Token,
		&s.ExpiresAt,
		&s.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("select session by token: %w", err)
	}
	return &s, nil
}

// DeleteSession removes a session by its token.
func DeleteSession(db *sql.DB, token string) error {
	query := `DELETE FROM sessions WHERE token = ?`
	result, err := db.Exec(query, token)
	if err != nil {
		return fmt.Errorf("delete session: %w", err)
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

// DeleteSessionsForUser removes all sessions belonging to a user.
func DeleteSessionsForUser(db *sql.DB, userID int64) error {
	query := `DELETE FROM sessions WHERE user_id = ?`
	_, err := db.Exec(query, userID)
	if err != nil {
		return fmt.Errorf("delete sessions for user: %w", err)
	}
	return nil
}

// DeleteExpiredSessions removes all sessions whose expires_at has passed.
func DeleteExpiredSessions(db *sql.DB) error {
	query := `DELETE FROM sessions WHERE expires_at <= datetime('now')`
	_, err := db.Exec(query)
	if err != nil {
		return fmt.Errorf("delete expired sessions: %w", err)
	}
	return nil
}

// IsTokenBlacklisted checks whether a token is absent from the active sessions table.
// A token is considered "blacklisted" (revoked) if it does not exist in the
// non-expired sessions table.
func IsTokenBlacklisted(db *sql.DB, token string) (bool, error) {
	query := `
		SELECT 1 FROM sessions
		WHERE token = ? AND expires_at > datetime('now')
	`
	var dummy int
	err := db.QueryRow(query, token).Scan(&dummy)
	if err != nil {
		if err == sql.ErrNoRows {
			// Token not found in active sessions — it's blacklisted/revoked
			return true, nil
		}
		return false, fmt.Errorf("check token blacklisted: %w", err)
	}
	// Token found — not blacklisted
	return false, nil
}
