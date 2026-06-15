package handlers

import (
	"database/sql"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/storage"
	"circle/internal/utils"
)

// StoryHandler handles story endpoints.
type StoryHandler struct {
	DB         *sql.DB
	MediaStore *storage.MediaStore
	MaxSize    int64
}

// CreateStoryRequest represents the form data for creating a story.
type CreateStoryRequest struct {
	MediaType string `form:"media_type"`
}

// ListStories returns active stories not yet viewed by the requesting user,
// paginated by ?page and ?limit.
func (h *StoryHandler) ListStories(c *gin.Context) {
	userID := c.GetInt64("user_id")
	page := utils.GetPagination(c)

	stories, err := models.GetActiveStories(h.DB, userID, page.Limit, page.Offset)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve stories")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"stories": stories})
}

// GetStory returns a single story by ID.
func (h *StoryHandler) GetStory(c *gin.Context) {
	userID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	story, err := models.GetStoryByIDWithUserContext(h.DB, id, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "story not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve story")
		return
	}

	utils.RespondJSON(c, http.StatusOK, story)
}

// CreateStory creates a new story with media.
func (h *StoryHandler) CreateStory(c *gin.Context) {
	userID := c.GetInt64("user_id")

	// Parse multipart form. The argument is the in-memory budget; larger files spill to temp files.
	const multipartMemoryLimit = 8 << 20 // 8 MB
	if err := c.Request.ParseMultipartForm(multipartMemoryLimit); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "failed to parse form")
		return
	}

	mediaType := c.PostForm("media_type")
	if mediaType != "image" && mediaType != "video" {
		utils.RespondError(c, http.StatusBadRequest, "media_type must be 'image' or 'video'")
		return
	}

	// Get media file
	mediaFile, mediaHeader, err := c.Request.FormFile("media")
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "media file is required")
		return
	}
	defer mediaFile.Close()

	// Validate no GPS data (only for images)
	if mediaType == "image" {
		detectedMime, err := storage.DetectMimeType(mediaFile)
		if err != nil {
			utils.RespondError(c, http.StatusBadRequest, "failed to detect media type")
			return
		}
		mediaFile.Seek(0, io.SeekStart)
		if err := h.MediaStore.ValidateNoGPS(mediaFile, detectedMime); err != nil {
			utils.RespondError(c, http.StatusBadRequest, "image contains location data")
			return
		}
		mediaFile.Seek(0, io.SeekStart)
	}

	// Save media file
	_, mediaFilename, err := h.MediaStore.SaveMedia(userID, mediaFile, mediaHeader, h.MaxSize)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	// Handle optional thumbnail
	var thumbnailFilename string
	thumbFile, thumbHeader, err := c.Request.FormFile("thumbnail")
	if err == nil && thumbFile != nil {
		defer thumbFile.Close()
		_, thumbnailFilename, err = h.MediaStore.SaveMedia(userID, thumbFile, thumbHeader, h.MaxSize)
		if err != nil {
			// Clean up main media on thumbnail failure
			_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + mediaFilename)
			utils.RespondError(c, http.StatusBadRequest, "failed to save thumbnail: "+err.Error())
			return
		}
	}

	expiresAt := time.Now().UTC().Add(72 * time.Hour)

	story, err := models.CreateStory(h.DB, userID, mediaFilename, thumbnailFilename, mediaType, expiresAt)
	if err != nil {
		// Clean up media files on DB failure
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + mediaFilename)
		if thumbnailFilename != "" {
			_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + thumbnailFilename)
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to create story")
		return
	}

	utils.RespondCreated(c, story)
}

// ViewStory marks a story as viewed by the current user.
func (h *StoryHandler) ViewStory(c *gin.Context) {
	userID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Verify story exists
	_, err = models.GetStoryByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "story not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve story")
		return
	}

	if err := models.MarkStoryViewed(h.DB, id, userID); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to mark story as viewed")
		return
	}

	utils.RespondNoContent(c)
}

// DeleteStory deletes a story and its media files.
func (h *StoryHandler) DeleteStory(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Get story to check ownership
	story, err := models.GetStoryByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "story not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve story")
		return
	}

	if !checkOwnership(c, story.UserID) {
		utils.RespondError(c, http.StatusForbidden, "not authorized to delete this story")
		return
	}

	// Get media filenames before deleting DB row
	mediaFilename := story.MediaFilename
	thumbnailFilename := story.ThumbnailFilename

	if err := models.DeleteStory(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete story")
		return
	}

	// Clean up media files after DB deletion
	if mediaFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(story.UserID, 10) + "/" + mediaFilename)
	}
	if thumbnailFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(story.UserID, 10) + "/" + thumbnailFilename)
	}

	utils.RespondNoContent(c)
}
