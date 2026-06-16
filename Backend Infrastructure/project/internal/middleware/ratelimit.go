package middleware

import (
	"fmt"
	"net"
	"net/http"
	"strings"
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
	buckets     map[string]*bucket
	mu          sync.RWMutex
	limit       int
	refill      time.Duration
	ipExtractor func(*gin.Context) string
	stopCh      chan struct{}
	stopOnce    sync.Once
}

// NewRateLimiter creates a new RateLimiter with the specified requests-per-minute limit.
// It also starts a background goroutine to clean up stale buckets every 5 minutes.
// The client IP is derived from gin's c.ClientIP().
func NewRateLimiter(requestsPerMinute int) *RateLimiter {
	return NewRateLimiterWithExtractor(requestsPerMinute, nil)
}

// NewRateLimiterWithExtractor creates a new RateLimiter with a custom IP extractor.
// If extractor is nil, it defaults to gin's c.ClientIP().
func NewRateLimiterWithExtractor(requestsPerMinute int, extractor func(*gin.Context) string) *RateLimiter {
	if extractor == nil {
		extractor = func(c *gin.Context) string {
			return c.ClientIP()
		}
	}
	rl := &RateLimiter{
		buckets:     make(map[string]*bucket),
		limit:       requestsPerMinute,
		refill:      time.Minute,
		ipExtractor: extractor,
		stopCh:      make(chan struct{}),
	}
	go rl.cleanup()
	return rl
}

// Stop terminates the background cleanup goroutine. It is safe to call multiple times.
func (rl *RateLimiter) Stop() {
	rl.stopOnce.Do(func() {
		close(rl.stopCh)
	})
}

// Middleware returns a gin middleware that rate-limits requests using a token bucket.
// The client key is derived from a hash of the request IP address.
// If the limit is exceeded, it returns 429 Too Many Requests with a Retry-After header.
func (rl *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		key := utils.HashIP(rl.ipExtractor(c))

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

// ClientIPFromRemoteAddr returns the client IP from the connection's RemoteAddr,
// ignoring proxy headers such as X-Forwarded-For.
func ClientIPFromRemoteAddr(c *gin.Context) string {
	ip, _, err := net.SplitHostPort(c.Request.RemoteAddr)
	if err != nil {
		return c.Request.RemoteAddr
	}
	return ip
}

// ClientIPFromXRealIP returns the real client IP from the X-Real-Ip header that
// a trusted reverse proxy sets (e.g. nginx `proxy_set_header X-Real-IP $remote_addr`).
// Because nginx overwrites this header on every request it cannot be spoofed by the
// client, making it a safe per-client rate-limiting key. It falls back to the
// connection RemoteAddr when the header is absent (e.g. direct connections).
//
// This is used instead of gin's c.ClientIP() because the rate limiter must derive
// a stable per-client key without depending on gin's trusted-proxy configuration,
// which would otherwise collapse every proxied request onto the single proxy IP.
func ClientIPFromXRealIP(c *gin.Context) string {
	if ip := strings.TrimSpace(c.GetHeader("X-Real-Ip")); ip != "" {
		return ip
	}
	return ClientIPFromRemoteAddr(c)
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

	for {
		select {
		case <-ticker.C:
			rl.purgeStaleBuckets()
		case <-rl.stopCh:
			return
		}
	}
}

// purgeStaleBuckets removes buckets that have been inactive for more than 10 minutes.
// It collects stale keys under a read lock, then deletes them under a write lock.
func (rl *RateLimiter) purgeStaleBuckets() {
	now := time.Now()

	rl.mu.RLock()
	stale := make([]string, 0, len(rl.buckets))
	for key, b := range rl.buckets {
		if now.Sub(b.last) > 10*time.Minute {
			stale = append(stale, key)
		}
	}
	rl.mu.RUnlock()

	if len(stale) == 0 {
		return
	}

	rl.mu.Lock()
	for _, key := range stale {
		delete(rl.buckets, key)
	}
	rl.mu.Unlock()
}
