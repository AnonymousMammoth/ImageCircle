package handlers

import (
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/storage"
	"circle/internal/utils"
)

// MediaHandler handles generic media upload and serving endpoints.
type MediaHandler struct {
	MediaStore *storage.MediaStore
	MediaDir   string
	MaxSize    int64
}

// Upload handles a generic media file upload.
func (h *MediaHandler) Upload(c *gin.Context) {
	userID := c.GetInt64("user_id")

	// Parse multipart form. The argument is the in-memory budget; larger files spill to temp files.
	const multipartMemoryLimit = 8 << 20 // 8 MB
	if err := c.Request.ParseMultipartForm(multipartMemoryLimit); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "failed to parse form")
		return
	}

	// Get media file
	mediaFile, mediaHeader, err := c.Request.FormFile("media")
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "media file is required")
		return
	}
	defer mediaFile.Close()

	// Detect MIME type for validation
	detectedMime, err := storage.DetectMimeType(mediaFile)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "failed to detect media type")
		return
	}

	// Validate no GPS data in the image
	mediaFile.Seek(0, io.SeekStart)
	if err := h.MediaStore.ValidateNoGPS(mediaFile, detectedMime); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "image contains location data")
		return
	}

	// Reset file after GPS check
	mediaFile.Seek(0, io.SeekStart)

	// Save media file
	_, filename, err := h.MediaStore.SaveMedia(userID, mediaFile, mediaHeader, h.MaxSize)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, err.Error())
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{
		"filename": filename,
		"url":      "/media/" + strconv.FormatInt(userID, 10) + "/" + filename,
	})
}

// Serve streams an authenticated media file from disk.
// It sanitizes the path, prevents directory traversal, and returns 404 for
// directories or missing files. The response is marked private and not cacheable
// by shared caches.
func (h *MediaHandler) Serve(c *gin.Context) {
	rel := strings.TrimPrefix(c.Param("filepath"), "/")
	rel = filepath.Clean(rel)
	if rel == "." || rel == "/" || rel == "" {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	fullPath := filepath.Join(h.MediaDir, rel)
	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	absRoot, err := filepath.Abs(h.MediaDir)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "server error"})
		return
	}

	// Ensure the resolved path stays within the media directory.
	if !strings.HasPrefix(absPath, absRoot+string(filepath.Separator)) && absPath != absRoot {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	info, err := os.Stat(absPath)
	if err != nil || info.IsDir() {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	c.Header("Cache-Control", "private, max-age=31536000, immutable")
	c.File(absPath)
}
