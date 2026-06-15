package database

import (
	_ "embed"
	"fmt"

	"database/sql"

	_ "github.com/mattn/go-sqlite3"
)

//go:embed schema.sql
var schemaSQL string

// DB wraps the sql.DB connection with schema management capabilities.
type DB struct {
	conn *sql.DB
}

// New opens a SQLite database at dbPath, applies required pragmas,
// and runs the schema migration. It configures a modest connection pool
// that works safely with SQLite's WAL mode while allowing concurrent reads.
func New(dbPath string) (*DB, error) {
	conn, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	// SQLite with WAL mode allows concurrent reads but only one writer at a time.
	// Limit the pool to a single open connection to eliminate writer contention.
	conn.SetMaxOpenConns(1)
	conn.SetMaxIdleConns(1)

	if err := applyPragmas(conn); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("apply pragmas: %w", err)
	}

	db := &DB{conn: conn}
	// Apply base schema first so migrations always run against an existing table structure.
	if err := db.RunSchema(); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("run schema: %w", err)
	}
	if err := db.migrate(); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("migrate: %w", err)
	}

	return db, nil
}

// migrate applies one-off schema migrations that are not handled by schema.sql.
func (db *DB) migrate() error {
	// Add avatar_filename column to users if it doesn't exist.
	var count int
	err := db.conn.QueryRow(`
		SELECT COUNT(*) FROM pragma_table_info('users') WHERE name = 'avatar_filename'
	`).Scan(&count)
	if err != nil {
		return fmt.Errorf("check avatar column: %w", err)
	}
	if count == 0 {
		if _, err := db.conn.Exec(`ALTER TABLE users ADD COLUMN avatar_filename TEXT`); err != nil {
			return fmt.Errorf("add avatar column: %w", err)
		}
	}

	// Add notifications table for explicit activity items such as @mentions.
	if err := db.conn.QueryRow(`
		SELECT COUNT(*) FROM pragma_table_info('notifications') WHERE name = 'id'
	`).Scan(&count); err != nil {
		return fmt.Errorf("check notifications table: %w", err)
	}
	if count == 0 {
		_, err := db.conn.Exec(`
			CREATE TABLE notifications (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
				actor_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
				type TEXT NOT NULL CHECK(type IN ('mention_post', 'mention_comment')),
				post_id INTEGER REFERENCES posts(id) ON DELETE CASCADE,
				comment_id INTEGER REFERENCES comments(id) ON DELETE CASCADE,
				text_preview TEXT,
				is_read INTEGER DEFAULT 0,
				created_at DATETIME DEFAULT CURRENT_TIMESTAMP
			);
			CREATE INDEX idx_notifications_user_id_created_at ON notifications(user_id, created_at DESC);
			CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read);
		`)
		if err != nil {
			return fmt.Errorf("create notifications table: %w", err)
		}
	}

	return nil
}

// Conn returns the underlying *sql.DB connection.
func (db *DB) Conn() *sql.DB {
	return db.conn
}

// Close closes the database connection.
func (db *DB) Close() error {
	if db.conn != nil {
		return db.conn.Close()
	}
	return nil
}

// RunSchema executes the embedded schema.sql migration.
func (db *DB) RunSchema() error {
	if _, err := db.conn.Exec(schemaSQL); err != nil {
		return fmt.Errorf("execute schema: %w", err)
	}
	return nil
}

func applyPragmas(conn *sql.DB) error {
	pragmas := []string{
		`PRAGMA journal_mode=WAL;`,
		`PRAGMA foreign_keys=ON;`,
		`PRAGMA busy_timeout=5000;`,
	}
	for _, p := range pragmas {
		if _, err := conn.Exec(p); err != nil {
			return fmt.Errorf("%s: %w", p, err)
		}
	}
	return nil
}
