package jobs

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"sync"
	"time"

	"circle/internal/models"
	"circle/internal/storage"
)

// CleanupJob runs periodic background cleanup tasks:
//   - deleting expired stories (DB rows + media files)
//   - deleting expired sessions
//   - removing orphaned media files (no DB reference)
type CleanupJob struct {
	db         *sql.DB
	mediaStore *storage.MediaStore
	interval   time.Duration
	logger     *slog.Logger
	stopCh     chan struct{}
	stopOnce   sync.Once
}

// NewCleanupJob creates a new cleanup job runner.
// interval: how often to run cleanup (default 1 hour if <= 0).
func NewCleanupJob(db *sql.DB, mediaStore *storage.MediaStore, interval time.Duration, logger *slog.Logger) *CleanupJob {
	if interval <= 0 {
		interval = 1 * time.Hour
	}
	return &CleanupJob{
		db:         db,
		mediaStore: mediaStore,
		interval:   interval,
		logger:     logger,
		stopCh:     make(chan struct{}),
	}
}

// Start begins the cleanup loop in a goroutine. Call Stop() to terminate.
func (j *CleanupJob) Start(ctx context.Context) {
	// Run initial cleanup immediately
	j.runCleanup()

	go func() {
		ticker := time.NewTicker(j.interval)
		defer ticker.Stop()

		for {
			select {
			case <-ticker.C:
				j.runCleanup()
			case <-j.stopCh:
				j.logger.Info("cleanup job stopped")
				return
			case <-ctx.Done():
				j.logger.Info("cleanup job stopped (context cancelled)")
				return
			}
		}
	}()
}

// Stop signals the job to stop. It is safe to call multiple times.
func (j *CleanupJob) Stop() {
	j.stopOnce.Do(func() {
		close(j.stopCh)
	})
}

// runCleanup performs one cleanup cycle:
//  1. Delete expired stories (DB + filesystem)
//  2. Delete expired sessions
//  3. Delete orphaned media files (not referenced by any post or story)
func (j *CleanupJob) runCleanup() {
	j.logger.Info("running cleanup cycle")

	j.deleteExpiredStories()
	j.deleteExpiredSessions()
	j.cleanupOrphanedMedia()
}

// deleteExpiredStories finds all expired stories, deletes their media files, then deletes DB rows.
func (j *CleanupJob) deleteExpiredStories() {
	stories, err := models.GetExpiredStories(j.db)
	if err != nil {
		j.logger.Error("failed to get expired stories", "error", err)
		return
	}

	if len(stories) == 0 {
		return
	}

	deletedCount := 0
	for _, story := range stories {
		// Delete media files first
		if story.MediaFilename != "" {
			relativePath := filepath.Join(fmt.Sprintf("%d", story.UserID), story.MediaFilename)
			_ = j.mediaStore.DeleteMedia(relativePath)
		}
		if story.ThumbnailFilename != "" {
			relativePath := filepath.Join(fmt.Sprintf("%d", story.UserID), story.ThumbnailFilename)
			_ = j.mediaStore.DeleteMedia(relativePath)
		}

		// Delete story from DB
		if err := models.DeleteStory(j.db, story.ID); err != nil {
			j.logger.Error("failed to delete expired story",
				"story_id", story.ID,
				"error", err,
			)
			continue
		}
		deletedCount++
	}

	j.logger.Info("deleted expired stories",
		"count", deletedCount,
		"total_expired", len(stories),
	)
}

// deleteExpiredSessions removes expired JWT sessions.
func (j *CleanupJob) deleteExpiredSessions() {
	if err := models.DeleteExpiredSessions(j.db); err != nil {
		j.logger.Error("failed to delete expired sessions", "error", err)
		return
	}

	j.logger.Info("cleaned up expired sessions")
}

// cleanupOrphanedMedia walks the media directory and removes files
// not referenced by any post or story in the database.
func (j *CleanupJob) cleanupOrphanedMedia() {
	referenced, err := j.getReferencedMedia()
	if err != nil {
		j.logger.Error("failed to get referenced media set", "error", err)
		return
	}

	// Walk the media directory tree
	mediaDir := j.mediaStore.BasePath
	orphanCount := 0

	err = filepath.Walk(mediaDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return nil // Skip files we can't read
		}
		if info.IsDir() {
			return nil
		}

		relPath, err := filepath.Rel(mediaDir, path)
		if err != nil {
			return nil
		}
		// Normalize path separators for cross-platform consistency
		relPath = filepath.ToSlash(relPath)

		if !referenced[relPath] {
			// Orphaned file - delete it
			if err := j.mediaStore.DeleteMedia(relPath); err != nil {
				j.logger.Error("failed to delete orphaned media",
					"path", relPath,
					"error", err,
				)
			} else {
				orphanCount++
			}
		}

		return nil
	})

	if err != nil {
		j.logger.Error("failed to walk media directory", "error", err)
		return
	}

	if orphanCount > 0 {
		j.logger.Info("removed orphaned media files", "count", orphanCount)
	}
}

// getReferencedMedia returns a set of all relative media paths referenced
// in posts, stories, and users tables (media_filename, thumbnail_filename,
// and avatar_filename columns). Paths are normalized with forward slashes.
func (j *CleanupJob) getReferencedMedia() (map[string]bool, error) {
	referenced := make(map[string]bool)

	// Helper to collect filenames for a query. Each row is expected to contain
	// a user_id column followed by the filename column.
	collect := func(query string) error {
		rows, err := j.db.Query(query)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var userID int64
			var fn string
			if err := rows.Scan(&userID, &fn); err != nil {
				return err
			}
			if fn != "" {
				referenced[filepath.ToSlash(filepath.Join(fmt.Sprintf("%d", userID), fn))] = true
			}
		}
		return rows.Err()
	}

	queries := []string{
		`SELECT user_id, media_filename FROM posts WHERE media_filename IS NOT NULL AND media_filename != ''`,
		`SELECT user_id, thumbnail_filename FROM posts WHERE thumbnail_filename IS NOT NULL AND thumbnail_filename != ''`,
		`SELECT user_id, media_filename FROM stories WHERE media_filename IS NOT NULL AND media_filename != ''`,
		`SELECT user_id, thumbnail_filename FROM stories WHERE thumbnail_filename IS NOT NULL AND thumbnail_filename != ''`,
		`SELECT id, avatar_filename FROM users WHERE avatar_filename IS NOT NULL AND avatar_filename != ''`,
	}

	for _, q := range queries {
		if err := collect(q); err != nil {
			return nil, err
		}
	}

	return referenced, nil
}
