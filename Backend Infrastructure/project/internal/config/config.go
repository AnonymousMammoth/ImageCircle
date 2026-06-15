package config

import (
	"fmt"
	"os"
	"strconv"
)

// Config holds all application configuration.
type Config struct {
	Port          string
	DataDir       string
	MediaDir      string
	DBPath        string
	JWTSecret     []byte
	MaxMediaSize  int64
	AllowedOrigin string
	AdminBind     string
	RateLimit     int
	PasswordCost  int
	ServerBind    string
	TrustProxy    bool
}

// Load reads configuration from environment variables with sensible defaults.
// Required variables (no defaults): CIRCLE_JWT_SECRET, CIRCLE_ALLOWED_ORIGIN.
func Load() (*Config, error) {
	port := getEnv("CIRCLE_PORT", "8080")
	dataDir := getEnv("CIRCLE_DATA_DIR", "/data")

	jwtSecretStr := os.Getenv("CIRCLE_JWT_SECRET")
	if jwtSecretStr == "" {
		return nil, fmt.Errorf("CIRCLE_JWT_SECRET is required")
	}
	jwtSecret := []byte(jwtSecretStr)
	if len(jwtSecret) < 32 {
		return nil, fmt.Errorf("CIRCLE_JWT_SECRET must be at least 32 bytes")
	}

	maxMediaSizeStr := getEnv("CIRCLE_MAX_MEDIA_SIZE", "52428800")
	maxMediaSize, err := strconv.ParseInt(maxMediaSizeStr, 10, 64)
	if err != nil {
		return nil, fmt.Errorf("invalid CIRCLE_MAX_MEDIA_SIZE: %w", err)
	}

	allowedOrigin := os.Getenv("CIRCLE_ALLOWED_ORIGIN")
	if allowedOrigin == "" {
		return nil, fmt.Errorf("CIRCLE_ALLOWED_ORIGIN is required")
	}

	adminBind := getEnv("CIRCLE_ADMIN_BIND", "127.0.0.1")

	rateLimitStr := getEnv("CIRCLE_RATE_LIMIT", "100")
	rateLimit, err := strconv.Atoi(rateLimitStr)
	if err != nil {
		return nil, fmt.Errorf("invalid CIRCLE_RATE_LIMIT: %w", err)
	}

	passwordCostStr := getEnv("CIRCLE_PASSWORD_COST", "12")
	passwordCost, err := strconv.Atoi(passwordCostStr)
	if err != nil {
		return nil, fmt.Errorf("invalid CIRCLE_PASSWORD_COST: %w", err)
	}

	trustProxy := false
	if v := os.Getenv("CIRCLE_TRUST_PROXY"); v != "" {
		b, err := strconv.ParseBool(v)
		if err != nil {
			return nil, fmt.Errorf("invalid CIRCLE_TRUST_PROXY: %w", err)
		}
		trustProxy = b
	}

	cfg := &Config{
		Port:          port,
		DataDir:       dataDir,
		MediaDir:      dataDir + "/media",
		DBPath:        dataDir + "/circle.db",
		JWTSecret:     jwtSecret,
		MaxMediaSize:  maxMediaSize,
		AllowedOrigin: allowedOrigin,
		AdminBind:     adminBind,
		RateLimit:     rateLimit,
		PasswordCost:  passwordCost,
		ServerBind:    "", // all interfaces
		TrustProxy:    trustProxy,
	}

	return cfg, nil
}

// EnsureDirs creates DataDir and MediaDir if they do not already exist.
func (c *Config) EnsureDirs() error {
	if err := os.MkdirAll(c.DataDir, 0o700); err != nil {
		return fmt.Errorf("failed to create data directory: %w", err)
	}
	if err := os.MkdirAll(c.MediaDir, 0o700); err != nil {
		return fmt.Errorf("failed to create media directory: %w", err)
	}
	return nil
}

func getEnv(key, defaultValue string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultValue
}
