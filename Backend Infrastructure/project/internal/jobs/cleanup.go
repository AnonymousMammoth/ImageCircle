package jobs

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
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

// Stop signals the job to stop.
func (j *CleanupJob) Stop() {
	close(j.stopCh)
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

		// Get just the filename (not the full path)
		basename := filepath.Base(path)
		if basename == "" {
			return nil
		}

		if !referenced[basename] {
			// Orphaned file - delete it
			relPath, err := filepath.Rel(mediaDir, path)
			if err != nil {
				return nil
			}
			// Normalize path separators for cross-platform consistency
			relPath = filepath.ToSlash(relPath)
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

// getReferencedMedia returns a set of all media filenames referenced
// in posts and stories tables (media_filename and thumbnail_filename columns).
func (j *CleanupJob) getReferencedMedia() (map[string]bool, error) {
	referenced := make(map[string]bool)

	// Query posts.media_filename
	rows, err := j.db.Query(`SELECT media_filename FROM posts WHERE media_filename IS NOT NULL AND media_filename != ''`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var fn string
		if err := rows.Scan(&fn); err != nil {
			rows.Close()
			return nil, err
		}
		if fn != "" {
			referenced[fn] = true
		}
	}
	rows.Close()

	// Query posts.thumbnail_filename
	rows, err = j.db.Query(`SELECT thumbnail_filename FROM posts WHERE thumbnail_filename IS NOT NULL AND thumbnail_filename != ''`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var fn string
		if err := rows.Scan(&fn); err != nil {
			rows.Close()
			return nil, err
		}
		if fn != "" {
			referenced[fn] = true
		}
	}
	rows.Close()

	// Query stories.media_filename
	rows, err = j.db.Query(`SELECT media_filename FROM stories WHERE media_filename IS NOT NULL AND media_filename != ''`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var fn string
		if err := rows.Scan(&fn); err != nil {
			rows.Close()
			return nil, err
		}
		if fn != "" {
			referenced[fn] = true
		}
	}
	rows.Close()

	// Query stories.thumbnail_filename
	rows, err = j.db.Query(`SELECT thumbnail_filename FROM stories WHERE thumbnail_filename IS NOT NULL AND thumbnail_filename != ''`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var fn string
		if err := rows.Scan(&fn); err != nil {
			rows.Close()
			return nil, err
		}
		if fn != "" {
			referenced[fn] = true
		}
	}
	rows.Close()

	return referenced, nil
}
