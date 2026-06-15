package models

import (
	"database/sql"
	"fmt"
	"time"
)

// Report represents a moderation report submitted by a user.
type Report struct {
	ID                   int64     `json:"id"`
	ReporterID           int64     `json:"reporter_id"`
	Reporter             *User     `json:"reporter,omitempty"`
	TargetType           string    `json:"target_type"`
	TargetID             int64     `json:"target_id"`
	TargetUser           *User     `json:"target_user,omitempty"`
	TargetPostCaption    string    `json:"target_post_caption,omitempty"`
	TargetPostMediaURL   string    `json:"target_post_media_url,omitempty"`
	TargetStoryMediaType string    `json:"target_story_media_type,omitempty"`
	TargetStoryMediaURL  string    `json:"target_story_media_url,omitempty"`
	Reason               string    `json:"reason"`
	Status               string    `json:"status"`
	CreatedAt            time.Time  `json:"created_at"`
	ResolvedAt           *time.Time `json:"resolved_at,omitempty"`
	ResolverID           int64      `json:"resolver_id,omitempty"`
	ResolverNote         string    `json:"resolver_note,omitempty"`
}

// ValidReportTargetTypes lists the allowed report target types.
var ValidReportTargetTypes = map[string]bool{
	"post":  true,
	"story": true,
	"user":  true,
}

// CreateReport inserts a new moderation report.
func CreateReport(db *sql.DB, reporterID int64, targetType string, targetID int64, reason string) (*Report, error) {
	query := `
		INSERT INTO reports (reporter_id, target_type, target_id, reason)
		VALUES (?, ?, ?, ?)
	`
	result, err := db.Exec(query, reporterID, targetType, targetID, reason)
	if err != nil {
		return nil, fmt.Errorf("insert report: %w", err)
	}

	id, err := result.LastInsertId()
	if err != nil {
		return nil, fmt.Errorf("last insert id: %w", err)
	}

	return GetReportByID(db, id)
}

// GetReportByID retrieves a single report by ID with reporter info.
func GetReportByID(db *sql.DB, id int64) (*Report, error) {
	query := `
		SELECT
			r.id, r.reporter_id, r.target_type, r.target_id, r.reason, r.status, r.created_at, r.resolved_at, r.resolver_id, r.resolver_note,
			u.id, u.username, u.display_name, u.is_admin, u.password_change_required, u.avatar_filename, u.created_at
		FROM reports r
		JOIN users u ON r.reporter_id = u.id
		WHERE r.id = ?
	`
	row := db.QueryRow(query, id)
	return scanReport(row)
}

// ListReports returns reports filtered by status, joined with reporter and target info.
func ListReports(db *sql.DB, status string) ([]*Report, error) {
	args := []interface{}{}
	whereStatus := ""
	if status != "" && status != "all" {
		whereStatus = "WHERE r.status = ?"
		args = append(args, status)
	}

	query := fmt.Sprintf(`
		SELECT
			r.id, r.reporter_id, r.target_type, r.target_id, r.reason, r.status, r.created_at, r.resolved_at, r.resolver_id, r.resolver_note,
			reporter.id, reporter.username, reporter.display_name, reporter.is_admin, reporter.password_change_required, reporter.avatar_filename, reporter.created_at,
			target.id, target.username, target.display_name, target.is_admin, target.password_change_required, target.avatar_filename, target.created_at,
			p.user_id, p.caption, p.media_filename,
			s.user_id, s.media_type, s.media_filename
		FROM reports r
		JOIN users reporter ON r.reporter_id = reporter.id
		LEFT JOIN users target ON r.target_type = 'user' AND target.id = r.target_id
		LEFT JOIN posts p ON r.target_type = 'post' AND p.id = r.target_id
		LEFT JOIN stories s ON r.target_type = 'story' AND s.id = r.target_id
		%s
		ORDER BY r.created_at DESC
	`, whereStatus)

	rows, err := db.Query(query, args...)
	if err != nil {
		return nil, fmt.Errorf("query reports: %w", err)
	}
	defer rows.Close()

	return scanReports(rows)
}

// UpdateReportStatus updates a report's status, resolver, and note.
func UpdateReportStatus(db *sql.DB, reportID, resolverID int64, status, note string) (*Report, error) {
	var resolvedAt interface{}
	if status == "resolved" {
		resolvedAt = time.Now().UTC()
	} else {
		resolvedAt = nil
	}

	query := `
		UPDATE reports
		SET status = ?, resolver_id = ?, resolver_note = ?, resolved_at = ?
		WHERE id = ?
	`
	result, err := db.Exec(query, status, resolverID, note, resolvedAt, reportID)
	if err != nil {
		return nil, fmt.Errorf("update report: %w", err)
	}

	rowsAffected, err := result.RowsAffected()
	if err != nil {
		return nil, fmt.Errorf("rows affected: %w", err)
	}
	if rowsAffected == 0 {
		return nil, sql.ErrNoRows
	}

	return GetReportByID(db, reportID)
}

func scanReport(row *sql.Row) (*Report, error) {
	var r Report
	var reporter User
	var isAdminInt int
	var passwordChangeRequiredInt int
	var avatarFilename sql.NullString
	var resolvedAt sql.NullTime
	var resolverID sql.NullInt64
	var resolverNote sql.NullString

	err := row.Scan(
		&r.ID,
		&r.ReporterID,
		&r.TargetType,
		&r.TargetID,
		&r.Reason,
		&r.Status,
		&r.CreatedAt,
		&resolvedAt,
		&resolverID,
		&resolverNote,
		&reporter.ID,
		&reporter.Username,
		&reporter.DisplayName,
		&isAdminInt,
		&passwordChangeRequiredInt,
		&avatarFilename,
		&reporter.CreatedAt,
	)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, sql.ErrNoRows
		}
		return nil, fmt.Errorf("scan report: %w", err)
	}

	reporter.IsAdmin = isAdminInt != 0
	reporter.PasswordChangeRequired = passwordChangeRequiredInt != 0
	reporter.AvatarFilename = avatarFilename.String
	reporter.AvatarURL = BuildAvatarURL(reporter.ID, reporter.AvatarFilename)
	r.Reporter = &reporter

	if resolvedAt.Valid {
		t := resolvedAt.Time
		r.ResolvedAt = &t
	}
	if resolverID.Valid {
		r.ResolverID = resolverID.Int64
	}
	r.ResolverNote = resolverNote.String

	return &r, nil
}

func scanReports(rows *sql.Rows) ([]*Report, error) {
	reports := make([]*Report, 0)

	for rows.Next() {
		var r Report
		var reporter User
		var reporterIsAdminInt int
		var reporterPasswordChangeRequiredInt int
		var reporterAvatar sql.NullString
		var resolvedAt sql.NullTime
		var resolverID sql.NullInt64
		var resolverNote sql.NullString
		var targetPostUserID, targetStoryUserID sql.NullInt64
		var targetPostCaption, targetPostMediaFilename sql.NullString
		var targetStoryMediaType, targetStoryMediaFilename sql.NullString

		// Target-user fields are NULL when the report target is a post or story.
		var targetUserID sql.NullInt64
		var targetUsername, targetDisplayName sql.NullString
		var targetIsAdminInt, targetPasswordChangeRequiredInt sql.NullInt64
		var targetAvatar sql.NullString
		var targetCreatedAt sql.NullTime

		err := rows.Scan(
			&r.ID,
			&r.ReporterID,
			&r.TargetType,
			&r.TargetID,
			&r.Reason,
			&r.Status,
			&r.CreatedAt,
			&resolvedAt,
			&resolverID,
			&resolverNote,
			&reporter.ID,
			&reporter.Username,
			&reporter.DisplayName,
			&reporterIsAdminInt,
			&reporterPasswordChangeRequiredInt,
			&reporterAvatar,
			&reporter.CreatedAt,
			&targetUserID,
			&targetUsername,
			&targetDisplayName,
			&targetIsAdminInt,
			&targetPasswordChangeRequiredInt,
			&targetAvatar,
			&targetCreatedAt,
			&targetPostUserID,
			&targetPostCaption,
			&targetPostMediaFilename,
			&targetStoryUserID,
			&targetStoryMediaType,
			&targetStoryMediaFilename,
		)
		if err != nil {
			return nil, fmt.Errorf("scan report row: %w", err)
		}

		reporter.IsAdmin = reporterIsAdminInt != 0
		reporter.PasswordChangeRequired = reporterPasswordChangeRequiredInt != 0
		reporter.AvatarFilename = reporterAvatar.String
		reporter.AvatarURL = BuildAvatarURL(reporter.ID, reporter.AvatarFilename)
		r.Reporter = &reporter

		if targetUserID.Valid {
			var targetUser User
			targetUser.ID = targetUserID.Int64
			targetUser.Username = targetUsername.String
			targetUser.DisplayName = targetDisplayName.String
			targetUser.IsAdmin = targetIsAdminInt.Valid && targetIsAdminInt.Int64 != 0
			targetUser.PasswordChangeRequired = targetPasswordChangeRequiredInt.Valid && targetPasswordChangeRequiredInt.Int64 != 0
			targetUser.AvatarFilename = targetAvatar.String
			targetUser.AvatarURL = BuildAvatarURL(targetUser.ID, targetUser.AvatarFilename)
			r.TargetUser = &targetUser
		}

		if targetPostCaption.Valid {
			r.TargetPostCaption = targetPostCaption.String
			r.TargetPostMediaURL = BuildMediaURL(targetPostUserID.Int64, targetPostMediaFilename.String)
		}
		if targetStoryMediaType.Valid {
			r.TargetStoryMediaType = targetStoryMediaType.String
			r.TargetStoryMediaURL = BuildMediaURL(targetStoryUserID.Int64, targetStoryMediaFilename.String)
		}

		if resolvedAt.Valid {
			t := resolvedAt.Time
			r.ResolvedAt = &t
		}
		if resolverID.Valid {
			r.ResolverID = resolverID.Int64
		}
		r.ResolverNote = resolverNote.String

		reports = append(reports, &r)
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("rows iteration: %w", err)
	}

	return reports, nil
}
