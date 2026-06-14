package database

import (
	"_ "embed"
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
// and runs the schema migration. It configures the connection pool
// for SQLite's single-writer model.
func New(dbPath string) (*DB, error) {
	conn, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	conn.SetMaxOpenConns(1)
	conn.SetMaxIdleConns(1)

	if err := applyPragmas(conn); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("apply pragmas: %w", err)
	}

	db := &DB{conn: conn}
	if err := db.RunSchema(); err != nil {
		_ = conn.Close()
		return nil, fmt.Errorf("run schema: %w", err)
	}

	return db, nil
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
