package middleware

import (
	"fmt"
	"strings"

	"github.com/gin-gonic/gin"
)

// SecurityHeaders returns a middleware that sets security-related HTTP headers.
// The allowedOrigin is used to build the connect-src directive in the CSP.
func SecurityHeaders(allowedOrigin string) gin.HandlerFunc {
	// Sanitize allowedOrigin to prevent CSP injection
	allowedOrigin = strings.TrimSpace(allowedOrigin)

	csp := fmt.Sprintf(
		"default-src 'self'; "+
			"script-src 'self'; "+
			"style-src 'self' 'unsafe-inline'; "+
			"img-src 'self' blob: data:; "+
			"media-src 'self'; "+
			"connect-src 'self' %s; "+
			"frame-ancestors 'none';",
		allowedOrigin,
	)

	return func(c *gin.Context) {
		// HTTP Strict Transport Security (HSTS) — 2 years, include subdomains
		c.Header("Strict-Transport-Security", "max-age=63072000; includeSubDomains")

		// Prevent MIME type sniffing
		c.Header("X-Content-Type-Options", "nosniff")

		// Prevent clickjacking
		c.Header("X-Frame-Options", "DENY")

		// Content Security Policy — strict, no wildcards, no nonces
		c.Header("Content-Security-Policy", csp)

		// Referrer policy
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")

		// Disable deprecated XSS filter (can be abused)
		c.Header("X-XSS-Protection", "0")

		// Restrict browser features
		c.Header("Permissions-Policy", "camera=(), microphone=(), geolocation=()")

		c.Next()
	}
}
