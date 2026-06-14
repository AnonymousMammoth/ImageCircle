package models

import (
	"database/sql"
	"fmt"
	"time"
)

// User represents a platform member.
type User struct {
	ID                     int64     `json:"id"`
	Username               string    `json:"username"`
	DisplayName            string    `json:"display_name"`
	PasswordHash           string    `json:"-"`
	IsAdmin                bool      `json:"is_admin"`
	PasswordChangeRequired bool      `json:"password_change_required"`
	CreatedAt              time.Time `json:"created_at"`
}

// CreateUser inserts a new user and returns the created record.
func CreateUser(db *sql.DB, username, displayName, passwordHash string, isAdmin bool) (*User, error) {
	query := `
		INSERT INTO users (username, display_name, password_hash, is_admin, password_change_required)
		VALUES (?, ?, ?, ?, ?)
	`
	result, err := db.Exec(query, username, displayName, passwordHash, isAdmin, !isAdmin)
	if err != nil {
		return nil, fmt.Errorf("insert user: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetUserByID(db, id)
}

// GetUserByID retrieves a user by primary key.
func GetUserByID(db *sql.DB, id int64) (*User, error) {
	query := `
		SELECT id, username, display_name, password_hash, is_admin, password_change_required, created_at
		FROM users
		WHERE id = ?
	`
	row := db.QueryRow(query, id)
	return scanUser(row)
}

// GetUserByUsername retrieves a user by username.
func GetUserByUsername(db *sql.DB, username string) (*User, error) {
	query := `
		SELECT id, username, display_name, password_hash, is_admin, password_change_required, created_at
		FROM users
		WHERE username = ?
	`
	row := db.QueryRow(query, username)
	return scanUser(row)
}

// GetAllUsers retrieves all users ordered by created_at descending.
func GetAllUsers(db *sql.DB) ([]*User, error) {
	query := `
		SELECT id, username, display_name, password_hash, is_admin, password_change_required, created_at
		FROM users
		ORDER BY created_at DESC
	`
	rows, err := db.Query(query)
	if err != nil {
		return nil, fmt.Errorf("query all users: %w", err)
	}
	defer rows.Close()

	return scanUsers(rows)
}

// UpdateUser updates a user's display_name and is_admin fields.
func UpdateUser(db *sql.DB, user *User) error {
	query := `
		UPDATE users
		SET display_name = ?, is_admin = ?
		WHERE id = ?
	`
	result, err := db.Exec(query, user.DisplayName, user.IsAdmin, user.ID)
	if err != nil {
		return fmt.Errorf("update user: %w", err)
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

// UpdatePassword updates a user's password hash and change-required flag.
func UpdatePassword(db *sql.DB, userID int64, passwordHash string, changeRequired bool) error {
	query := `
		UPDATE users
		SET password_hash = ?, password_change_required = ?
		WHERE id = ?
	`
	result, err := db.Exec(query, passwordHash, changeRequired, userID)
	if err != nil {
		return fmt.Errorf("update password: %w", err)
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

// DeleteUser removes a user by primary key. Related records are handled by CASCADE.
func DeleteUser(db *sql.DB, id int64) error {
	query := `DELETE FROM users WHERE id = ?`
	result, err := db.Exec(query, id)
	if err != nil {
		return fmt.Errorf("delete user: %w", err)
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

// ToggleAdmin flips the is_admin flag for a user.
func ToggleAdmin(db *sql.DB, id int64) error {
	query := `
		UPDATE users
		SET is_admin = (CASE WHEN is_admin = 1 THEN 0 ELSE 1 END)
		WHERE id = ?
	`
	result, err := db.Exec(query, id)
	if err != nil {
		return fmt.Errorf("toggle admin: %w", err)
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

// scanUser scans a single user row.
func scanUser(row *sql.Row) (*User, error) {
	var u User
	var isAdminInt int
	var passwordChangeRequiredInt int

	err := row.Scan(
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
		return nil, fmt.Errorf("scan user: %w", err)
	}

	u.IsAdmin = isAdminInt != 0
	u.PasswordChangeRequired = passwordChangeRequiredInt != 0
	return &u, nil
}

// scanUsers scans multiple user rows.
func scanUsers(rows *sql.Rows) ([]*User, error) {
	var users []*User
	for rows.Next() {
		var u User
		var isAdminInt int
		var passwordChangeRequiredInt int

		err := rows.Scan(
			&u.ID,
			&u.Username,
			&u.DisplayName,
			&u.PasswordHash,
			&isAdminInt,
			&passwordChangeRequiredInt,
			&u.CreatedAt,
		)
		if err != nil {
			return nil, fmt.Errorf("scan user row: %w", err)
		}

		u.IsAdmin = isAdminInt != 0
		u.PasswordChangeRequired = passwordChangeRequiredInt != 0
		users = append(users, &u)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return users, nil
}
