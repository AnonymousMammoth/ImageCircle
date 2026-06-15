package handlers

import (
	"database/sql"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/storage"
	"circle/internal/utils"
)

// AdminContentHandler provides admin-only content moderation endpoints.
type AdminContentHandler struct {
	DB         *sql.DB
	MediaStore *storage.MediaStore
}

// ListContent returns paginated posts, stories, or comments for moderation.
func (h *AdminContentHandler) ListContent(c *gin.Context) {
	contentType := c.Query("type")
	page := utils.GetPagination(c)

	var items interface{}
	var err error

	switch contentType {
	case "post":
		items, err = models.ListAllPosts(h.DB, page.Limit, page.Offset)
	case "story":
		items, err = models.ListAllStories(h.DB, page.Limit, page.Offset)
	case "comment":
		items, err = models.ListAllComments(h.DB, page.Limit, page.Offset)
	default:
		utils.RespondError(c, http.StatusBadRequest, "invalid content type")
		return
	}

	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve content")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"items": items})
}

// DeletePost removes a post and its media files (admin only).
func (h *AdminContentHandler) DeletePost(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	post, err := models.GetPostByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "post not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve post")
		return
	}

	mediaFilename := post.MediaFilename
	thumbnailFilename := post.ThumbnailFilename

	if err := models.DeletePost(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete post")
		return
	}

	if mediaFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(post.UserID, 10) + "/" + mediaFilename)
	}
	if thumbnailFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(post.UserID, 10) + "/" + thumbnailFilename)
	}

	utils.RespondNoContent(c)
}

// DeleteStory removes a story and its media files (admin only).
func (h *AdminContentHandler) DeleteStory(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	story, err := models.GetStoryByID(h.DB, id)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "story not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve story")
		return
	}

	mediaFilename := story.MediaFilename
	thumbnailFilename := story.ThumbnailFilename

	if err := models.DeleteStory(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete story")
		return
	}

	if mediaFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(story.UserID, 10) + "/" + mediaFilename)
	}
	if thumbnailFilename != "" {
		_ = h.MediaStore.DeleteMedia(strconv.FormatInt(story.UserID, 10) + "/" + thumbnailFilename)
	}

	utils.RespondNoContent(c)
}

// DeleteComment removes a comment (admin only).
func (h *AdminContentHandler) DeleteComment(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	if _, err := models.GetCommentByID(h.DB, id); err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "comment not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve comment")
		return
	}

	if err := models.DeleteComment(h.DB, id); err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to delete comment")
		return
	}

	utils.RespondNoContent(c)
}
