package handlers

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"circle/internal/storage"
	"circle/internal/utils"
)

// MediaHandler handles generic media upload endpoints.
type MediaHandler struct {
	MediaStore *storage.MediaStore
	MaxSize    int64
}

// Upload handles a generic media file upload.
func (h *MediaHandler) Upload(c *gin.Context) {
	userID := c.GetInt64("user_id")

	// Parse multipart form with max size limit
	if err := c.Request.ParseMultipartForm(h.MaxSize); err != nil {
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

	// Validate no GPS data in the image
	detectedMime := detectMimeFromHeader(mediaHeader)
	if err := h.MediaStore.ValidateNoGPS(mediaFile, detectedMime); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "image contains location data")
		return
	}

	// Reset file after GPS check
	mediaFile.Seek(0, 0)

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
