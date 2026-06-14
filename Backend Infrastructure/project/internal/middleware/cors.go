package middleware

import (
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

// CORS returns a middleware that sets Cross-Origin Resource Sharing headers.
// The allowedOrigin parameter specifies the exact origin to allow — never a wildcard.
func CORS(allowedOrigin string) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", allowedOrigin)
		c.Header("Access-Control-Allow-Credentials", "true")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Content-Type, Authorization")
		c.Header("Access-Control-Max-Age", strconv.Itoa(86400))

		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}

		c.Next()
	}
}
