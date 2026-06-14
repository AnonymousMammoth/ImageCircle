package middleware

import (
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
)

// Logger returns a middleware that logs HTTP requests without any PII.
// It logs: timestamp, method, path, status code, and duration.
// It explicitly does NOT log: IP addresses, usernames, user agents, or query parameters.
func Logger() gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()

		// Process the request
		c.Next()

		duration := time.Since(start)
		status := c.Writer.Status()
		method := c.Request.Method
		path := c.Request.URL.Path

		// Intentionally omit: ClientIP, User-Agent, Query params, username
		fmt.Printf("[%s] %s %s %d %s\n",
			start.Format(time.RFC3339),
			method,
			path,
			status,
			duration.String(),
		)
	}
}
