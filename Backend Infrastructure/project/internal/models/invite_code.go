package models

import (
	"database/sql"
	"fmt"
	"time"
)

// InviteCode represents a registration access code.
type InviteCode struct {
	ID        int64      `json:"id"`
	Code      string     `json:"code"`
	CreatedBy int64      `json:"created_by"`
	UsedBy    *int64     `json:"used_by,omitempty"`
	ExpiresAt *time.Time `json:"expires_at,omitempty"`
	CreatedAt time.Time  `json:"created_at"`
}

// CreateInviteCode inserts a new invite code and returns the created record.
func CreateInviteCode(db *sql.DB, createdBy int64, code string, expiresAt *time.Time) (*InviteCode, error) {
	query := `
		INSERT INTO invite_codes (created_by, code, expires_at)
		VALUES (?, ?, ?)
	`
	result, err := db.Exec(query, createdBy, code, expiresAt)
	if err != nil {
		return nil, fmt.Errorf("insert invite code: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetInviteCodeByID(db, id)
}

// GetInviteCodeByCode retrieves an invite code by its code string.
func GetInviteCodeByCode(db *sql.DB, code string) (*InviteCode, error) {
	query := `
		SELECT id, code, created_by, used_by, expires_at, created_at
		FROM invite_codes
		WHERE code = ?
	`
	return scanInviteCode(db.QueryRow(query, code))
}

// GetInviteCodeByID retrieves an invite code by primary key.
func GetInviteCodeByID(db *sql.DB, id int64) (*InviteCode, error) {
	query := `
		SELECT id, code, created_by, used_by, expires_at, created_at
		FROM invite_codes
		WHERE id = ?
	`
	return scanInviteCode(db.QueryRow(query, id))
}

// MarkInviteCodeUsed marks an invite code as used by a specific user.
func MarkInviteCodeUsed(db *sql.DB, code string, usedBy int64) error {
	query := `
		UPDATE invite_codes
		SET used_by = ?
		WHERE code = ? AND used_by IS NULL
	`
	result, err := db.Exec(query, usedBy, code)
	if err != nil {
		return fmt.Errorf("mark invite code used: %w", err)
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

// scanInviteCode scans a single invite code row.
func scanInviteCode(row *sql.Row) (*InviteCode, error) {
	var ic InviteCode
	var usedBy sql.NullInt64
	var expiresAt sql.NullTime

	err := row.Scan(
		&ic.ID,
		&ic.Code,
		&ic.CreatedBy,
		&usedBy,
		&expiresAt,
		&ic.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("scan invite code: %w", err)
	}

	if usedBy.Valid {
		ic.UsedBy = &usedBy.Int64
	}
	if expiresAt.Valid {
		ic.ExpiresAt = &expiresAt.Time
	}

	return &ic, nil
}
