package handlers

import (
	"database/sql"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"circle/internal/models"
	"circle/internal/utils"
)

// ReportHandler handles report endpoints.
type ReportHandler struct {
	DB *sql.DB
}

// CreateReportRequest represents a request to create a report.
type CreateReportRequest struct {
	TargetType string `json:"target_type"`
	TargetID   int64  `json:"target_id"`
	Reason     string `json:"reason"`
}

// CreateReport creates a new moderation report.
func (h *ReportHandler) CreateReport(c *gin.Context) {
	userID := c.GetInt64("user_id")

	var req CreateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.TargetType = strings.TrimSpace(req.TargetType)
	req.Reason = strings.TrimSpace(req.Reason)

	if !models.ValidReportTargetTypes[req.TargetType] {
		utils.RespondError(c, http.StatusBadRequest, "target_type must be 'post', 'story', or 'user'")
		return
	}
	if req.TargetID <= 0 {
		utils.RespondError(c, http.StatusBadRequest, "target_id must be a positive integer")
		return
	}
	if req.Reason == "" {
		utils.RespondError(c, http.StatusBadRequest, "reason is required")
		return
	}
	if len(req.Reason) > 2000 {
		utils.RespondError(c, http.StatusBadRequest, "reason must be at most 2000 characters")
		return
	}

	// Prevent reporting yourself.
	if req.TargetType == "user" && req.TargetID == userID {
		utils.RespondError(c, http.StatusBadRequest, "cannot report yourself")
		return
	}

	report, err := models.CreateReport(h.DB, userID, req.TargetType, req.TargetID, req.Reason)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to create report")
		return
	}

	utils.RespondCreated(c, gin.H{
		"id":         report.ID,
		"status":     report.Status,
		"created_at": report.CreatedAt,
	})
}

// ListReports returns reports for admins, filtered by status.
func (h *ReportHandler) ListReports(c *gin.Context) {
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	if status == "" {
		status = "open"
	}
	if status != "open" && status != "resolved" && status != "all" {
		utils.RespondError(c, http.StatusBadRequest, "status must be 'open', 'resolved', or 'all'")
		return
	}

	reports, err := models.ListReports(h.DB, status)
	if err != nil {
		utils.RespondError(c, http.StatusInternalServerError, "failed to retrieve reports")
		return
	}

	utils.RespondJSON(c, http.StatusOK, gin.H{"reports": reports})
}

// UpdateReportRequest represents a request to update a report.
type UpdateReportRequest struct {
	Status       string `json:"status"`
	ResolverNote string `json:"resolver_note"`
}

// UpdateReport updates a report's status (admin only).
func (h *ReportHandler) UpdateReport(c *gin.Context) {
	resolverID := c.GetInt64("user_id")

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid id")
		return
	}

	var req UpdateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		utils.RespondError(c, http.StatusBadRequest, "invalid request body")
		return
	}

	req.Status = strings.ToLower(strings.TrimSpace(req.Status))
	req.ResolverNote = strings.TrimSpace(req.ResolverNote)

	if req.Status != "open" && req.Status != "resolved" {
		utils.RespondError(c, http.StatusBadRequest, "status must be 'open' or 'resolved'")
		return
	}

	report, err := models.UpdateReportStatus(h.DB, id, resolverID, req.Status, req.ResolverNote)
	if err != nil {
		if err == sql.ErrNoRows {
			utils.RespondError(c, http.StatusNotFound, "report not found")
			return
		}
		utils.RespondError(c, http.StatusInternalServerError, "failed to update report")
		return
	}

	utils.RespondJSON(c, http.StatusOK, report)
}
