package handlers

import (
	"database/sql"
	"mime/multipart"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/storage"
	"circle/internal/utils"
)

// PostHandler handles post endpoints.
type PostHandler struct {
	DB         *sql.DB
	MediaStore *storage.MediaStore
	MaxSize    int64
}

// ListPosts returns all posts in chronological order.
func (h *PostHandler) ListPosts(c *gin.Context) {
	userID := c.GetInt64("user_id")

	posts, err := models.GetFeed(h.DB, userID)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve posts")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"posts": posts})
}

// GetPost returns a single post by ID.
func (h *PostHandler) GetPost(c *gin.Context) {
	userID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	post, err := models.GetPostByIDWithUserContext(h.DB, id, userID)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve post")
		return
	}

	utils.RespondJSON(c, http.StatusOK, post)
}

// CreatePost creates a new post. It accepts either a JSON text-only body or a
// multipart form with a caption and media file.
func (h *PostHandler) CreatePost(c *gin.Context) {
	userID := c.GetInt64("user_id")
	contentType := strings.ToLower(c.ContentType())

	var caption, mediaFilename, thumbnailFilename string

	if strings.HasPrefix(contentType, "application/json") {
		var req struct {
			Caption string `json:"caption"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			utils.RespondError(c, http.StatusBadRequest, "invalid request body")
			return
		}
		caption = strings.TrimSpace(req.Caption)
	} else if strings.HasPrefix(contentType, "multipart/form-data") {
		// Parse multipart form with max size limit
		if err := c.Request.ParseMultipartForm(h.MaxSize); err != nil {
			utils.RespondError(c, http.StatusBadRequest, "failed to parse form")
			return
		}

		caption = strings.TrimSpace(c.PostForm("caption"))

		// Get media file
		mediaFile, mediaHeader, err := c.Request.FormFile("media")
		if err != nil {
			utils.RespondError(c, http.StatusBadRequest, "media file is required")
			return
		}
		defer mediaFile.Close()

		// Validate no GPS data in the image
		if err := h.MediaStore.ValidateNoGPS(mediaFile, detectMimeFromHeader(mediaHeader)); err != nil {
			utils.RespondError(c, http.StatusBadRequest, "image contains location data")
			return
		}

		// Save media file
		mediaFile.Seek(0, 0)
		_, mediaFilename, err = h.MediaStore.SaveMedia(userID, mediaFile, mediaHeader, h.MaxSize)
		if err != nil {
			utils.RespondError(c, http.StatusBadRequest, err.Error())
			return
		}

		// Handle optional thumbnail
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
	} else {
		utils.RespondError(c, http.StatusBadRequest, "unsupported content type")
		return
	}

	if caption == "" && mediaFilename == "" {
		utils.RespondError(c, http.StatusBadRequest, "caption or media is required")
		return
	}

	post, err := models.CreatePost(h.DB, userID, caption, mediaFilename, thumbnailFilename)
	if err != nil {
		// Clean up media files on DB failure
		if mediaFilename != "" {
			_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + mediaFilename)
		}
		if thumbnailFilename != "" {
			_ = h.MediaStore.DeleteMedia(strconv.FormatInt(userID, 10) + "/" + thumbnailFilename)
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to create post")
		return
	}

	utils.RespondCreated(c, post)
}

// DeletePost deletes a post and its media files.
func (h *PostHandler) DeletePost(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	// Get post to check ownership
	post, err := models.GetPostByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve post")
		return
	}

	if !checkOwnership(c, post.UserID) {
		utils.RespondError(c, http.StatusForbidden, "not authorized to delete this post")
		return
	}

	// Get media filenames before deleting DB row
	mediaFilename := post.MediaFilename
	thumbnailFilename := post.ThumbnailFilename

	if err := models.DeletePost(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete post")
		return
	}

	// Clean up media files after DB deletion
	if mediaFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(post.UserID, 10) + "/" + mediaFilename)
	}
	if thumbnailFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(post.UserID, 10) + "/" + thumbnailFilename)
	}

	utils.RespondNoContent(c)
}

// detectMimeFromHeader attempts to detect MIME type from a file header.
func detectMimeFromHeader(header *multipart.FileHeader) string {
	file, err := header.Open()
	if err != nil {
		return ""
	}
	defer file.Close()

	buf := make([]byte, 512)
	n, _ := file.Read(buf)
	if n == 0 {
		return ""
	}

	// Check JPEG
	if n >= 3 && buf[0] == 0xFF && buf[1] == 0xD8 && buf[2] == 0xFF {
		return "image/jpeg"
	}
	// Check PNG
	if n >= 8 && buf[0] == 0x89 && buf[1] == 0x50 && buf[2] == 0x4E && buf[3] == 0x47 {
		return "image/png"
	}
	// Check MP4/MOV/HEIC by ftyp
	if n >= 12 && buf[4] == 'f' && buf[5] == 't' && buf[6] == 'y' && buf[7] == 'p' {
		return "video/mp4" // Default to mp4, actual detection will happen in SaveMedia
	}
	return ""
}
