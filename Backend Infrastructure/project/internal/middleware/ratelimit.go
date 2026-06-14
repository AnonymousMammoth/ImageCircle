package middleware

import (
	"fmt"
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"

	"circle/internal/utils"
)

// bucket represents a token bucket for rate limiting.
type bucket struct {
	tokens float64
	last   time.Time
}

// RateLimiter implements an in-memory token bucket rate limiter.
// It is safe for concurrent use.
type RateLimiter struct {
	buckets map[string]*bucket
	mu      sync.RWMutex
	limit   int
	refill  time.Duration
}

// NewRateLimiter creates a new RateLimiter with the specified requests-per-minute limit.
// It also starts a background goroutine to clean up stale buckets every 5 minutes.
func NewRateLimiter(requestsPerMinute int) *RateLimiter {
	rl := &RateLimiter{
		buckets: make(map[string]*bucket),
		limit:   requestsPerMinute,
		refill:  time.Minute,
	}
	go rl.cleanup()
	return rl
}

// Middleware returns a gin middleware that rate-limits requests using a token bucket.
// The client key is derived from a hash of the request IP address.
// If the limit is exceeded, it returns 429 Too Many Requests with a Retry-After header.
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		key := utils.HashIP(c.ClientIP())

		allowed, retryAfter := rl.allow(key)
		if !allowed {
			c.Header("Retry-After", fmt.Sprintf("%d", int(retryAfter.Seconds())+1))
			c.AbortWithStatusJSON(http.StatusTooManyRequests, map[string]string{
				"error": "rate limit exceeded",
			})
			return
		}

		c.Next()
	}
}

// allow checks whether the given key has a token available.
// It returns true if the request is allowed, or false and the duration to wait.
func (rl *RateLimiter) allow(key string) (bool, time.Duration) {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	now := time.Now()
	b, exists := rl.buckets[key]
	if !exists {
		// New bucket with a full complement of tokens minus one for this request
		rl.buckets[key] = &bucket{
			tokens: float64(rl.limit) - 1,
			last:   now,
		}
		return true, 0
	}

	// Calculate tokens to add based on time elapsed since last request
	elapsed := now.Sub(b.last)
	tokensToAdd := elapsed.Seconds() * (float64(rl.limit) / rl.refill.Seconds())
	b.tokens = min(float64(rl.limit), b.tokens+tokensToAdd)
	b.last = now

	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}

	// Calculate retry after based on how long until 1 token is available
	retryAfter := time.Duration((1.0 - b.tokens) * rl.refill.Seconds() / float64(rl.limit) * float64(time.Second))
	return false, retryAfter
}

// cleanup periodically removes stale buckets to prevent unbounded memory growth.
// It runs in its own goroutine and cleans every 5 minutes.
func (rl *RateLimiter) cleanup() {
	ticker := time.NewTicker(5 * time.Minute)
	defer ticker.Stop()

	for range ticker.C {
		rl.mu.Lock()
		now := time.Now()
		for key, b := range rl.buckets {
			// Remove buckets that have been inactive for more than 10 minutes
			if now.Sub(b.last) > 10*time.Minute {
				delete(rl.buckets, key)
			}
		}
		rl.mu.Unlock()
	}
}
