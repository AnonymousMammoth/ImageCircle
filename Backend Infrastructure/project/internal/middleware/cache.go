package middleware

import (
	"strings"

	"github.com/gin-gonic/gin"
)

// NoStoreCacheControl returns a middleware that sets Cache-Control: no-store
// on all /api/* responses so that authenticated data is not cached by browsers
// or intermediate proxies.
func NoStoreCacheControl() gin.HandlerFunc {
	return func(c *gin.Context) {
		if strings.HasPrefix(c.Request.URL.Path, "/api/") {
			c.Header("Cache-Control", "no-store")
		}
		c.Next()
	}
}
