package utils

import (
	"strconv"

	"github.com/gin-gonic/gin"
)

const (
	defaultPageSize = 20
	maxPageSize     = 100
)

// Pagination holds parsed limit/offset values from query parameters.
type Pagination struct {
	Limit  int
	Offset int
}

// GetPagination parses ?page and ?limit query parameters from the request.
// Page defaults to 1 and limit defaults to defaultPageSize, capped at maxPageSize.
func GetPagination(c *gin.Context) Pagination {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	if page < 1 {
		page = 1
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", strconv.Itoa(defaultPageSize)))
	if limit < 1 {
		limit = defaultPageSize
	}
	if limit > maxPageSize {
		limit = maxPageSize
	}

	return Pagination{
		Limit:  limit,
		Offset: (page - 1) * limit,
	}
}
