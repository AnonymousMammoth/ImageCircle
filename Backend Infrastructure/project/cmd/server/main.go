package main

import (
	"context"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"

	"circle/internal/config"
	"circle/internal/database"
	"circle/internal/handlers"
	"circle/internal/jobs"
	"circle/internal/middleware"
	"circle/internal/models"
	"circle/internal/storage"
)

// serveWebStatic serves a single file from root using a path parameter.
// It prevents directory traversal and returns 404 for directories or missing files.
func serveWebStatic(c *gin.Context, root, paramName string) {
	rel := strings.TrimPrefix(c.Param(paramName), "/")
	rel = filepath.Clean(rel)
	if rel == "." || rel == "/" || rel == "" {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	fullPath := filepath.Join(root, rel)

	absPath, err := filepath.Abs(fullPath)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	absRoot, err := filepath.Abs(root)
	if err != nil {
		c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "server error"})
		return
	}

	// Ensure the resolved path stays within the root directory.
	if !strings.HasPrefix(absPath, absRoot+string(filepath.Separator)) && absPath != absRoot {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	info, err := os.Stat(absPath)
	if err != nil || info.IsDir() {
		c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
		return
	}

	c.Header("Cache-Control", "public, max-age=86400")
	c.File(absPath)
}

func main() {
	// 1. Load configuration (fatal on error)
	cfg, err := config.Load()
	if err != nil {
		slog.Error("failed to load configuration", "error", err)
		os.Exit(1)
	}

	// 2. Ensure data directories exist
	if err := cfg.EnsureDirs(); err != nil {
		slog.Error("failed to create data directories", "error", err)
		os.Exit(1)
	}

	// 3. Initialize structured logger (slog to stderr, JSON format)
	logger := slog.New(slog.NewJSONHandler(os.Stderr, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))
	slog.SetDefault(logger)

	// Set gin mode based on environment
	if os.Getenv("GIN_MODE") == "release" {
		gin.SetMode(gin.ReleaseMode)
	}

	// 4. Open SQLite database with WAL mode
	// 5. Run schema migration (handled by database.New)
	db, err := database.New(cfg.DBPath)
	if err != nil {
		logger.Error("failed to initialize database", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	sqlDB := db.Conn()

	// 6. Initialize media storage
	mediaStore := storage.NewMediaStore(cfg.MediaDir)

	// 7. Initialize rate limiters
	// When running behind a trusted reverse proxy (nginx), the connection
	// RemoteAddr is the proxy's IP — identical for every client — which would
	// collapse all traffic onto a single rate-limit bucket and break per-IP
	// brute-force protection. In that case derive the key from the X-Real-Ip
	// header nginx sets to the real client address (and overwrites, so it cannot
	// be spoofed). Without a proxy, use the connection RemoteAddr directly.
	clientIPExtractor := middleware.ClientIPFromRemoteAddr
	if cfg.TrustProxy {
		clientIPExtractor = middleware.ClientIPFromXRealIP
	}
	rateLimiter := middleware.NewRateLimiterWithExtractor(cfg.RateLimit, clientIPExtractor)
	strictRateLimiter := middleware.NewRateLimiterWithExtractor(10, clientIPExtractor)

	// 8. Create gin router with middleware stack
	router := gin.New()
	router.ForwardedByClientIP = cfg.TrustProxy
	if cfg.TrustProxy {
		router.RemoteIPHeaders = []string{"X-Forwarded-For", "X-Real-Ip"}
	}

	// Recovery middleware (gin built-in, suppresses stack traces in release mode)
	router.Use(gin.Recovery())

	// Security headers
	router.Use(middleware.SecurityHeaders(cfg.AllowedOrigin))

	// Logger (zero-PII)
	router.Use(middleware.Logger())

	// Rate limiter
	router.Use(rateLimiter.Middleware())

	// Cache-Control: no-store for API responses containing auth/user data
	router.Use(middleware.NoStoreCacheControl())

	// CORS
	router.Use(middleware.CORS(cfg.AllowedOrigin))

	// 9. Initialize all handlers
	authHandler := &handlers.AuthHandler{
		DB:           sqlDB,
		JWTSecret:    cfg.JWTSecret,
		PasswordCost: cfg.PasswordCost,
		CookieSecure: cfg.CookieSecure,
	}

	userHandler := &handlers.UserHandler{
		DB:           sqlDB,
		MediaStore:   mediaStore,
		PasswordCost: cfg.PasswordCost,
	}

	postHandler := &handlers.PostHandler{
		DB:         sqlDB,
		MediaStore: mediaStore,
		MaxSize:    cfg.MaxMediaSize,
	}

	storyHandler := &handlers.StoryHandler{
		DB:         sqlDB,
		MediaStore: mediaStore,
		MaxSize:    cfg.MaxMediaSize,
	}

	likeHandler := &handlers.LikeHandler{
		DB: sqlDB,
	}

	commentHandler := &handlers.CommentHandler{
		DB: sqlDB,
	}

	notificationHandler := &handlers.NotificationHandler{
		DB: sqlDB,
	}

	reportHandler := &handlers.ReportHandler{
		DB: sqlDB,
	}

	mediaHandler := &handlers.MediaHandler{
		MediaStore: mediaStore,
		MediaDir:   cfg.MediaDir,
		MaxSize:    cfg.MaxMediaSize,
	}

	// Set up token blacklist checker for auth middleware
	middleware.TokenBlacklistChecker = func(tokenString string) (bool, error) {
		return models.IsTokenBlacklisted(sqlDB, tokenString)
	}

	// 10. Setup routes

	// Health check (no auth, for Docker healthcheck)
	router.GET("/api/health", func(c *gin.Context) {
		if err := sqlDB.Ping(); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "database unavailable"})
			return
		}
		if _, err := os.Stat(cfg.MediaDir); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "error", "detail": "storage unavailable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Public (no auth)
	router.GET("/api/admin/setup", authHandler.SetupStatus)
	router.POST("/api/admin/setup", strictRateLimiter.Middleware(), authHandler.Setup)
	router.POST("/api/auth/login", strictRateLimiter.Middleware(), authHandler.Login)

	// Authenticated routes
	auth := router.Group("/")
	auth.Use(middleware.AuthRequired(cfg.JWTSecret))
	{
		// Auth
		auth.POST("/api/auth/refresh", authHandler.Refresh)
		auth.POST("/api/auth/change-password", strictRateLimiter.Middleware(), authHandler.ChangePassword)
		auth.POST("/api/auth/logout", authHandler.Logout)

		// Users
		auth.GET("/api/users/search", userHandler.SearchUsers)
		auth.GET("/api/users/me", userHandler.GetMe)
		auth.PUT("/api/users/me", userHandler.UpdateMe)
		auth.POST("/api/users/me/avatar", userHandler.UpdateAvatar)
		auth.GET("/api/users/me/blocked", userHandler.ListBlockedUsers)
		auth.GET("/api/users/:id/posts", userHandler.GetUserPosts)
		auth.GET("/api/users/:id/stories", userHandler.GetUserStories)
		auth.GET("/api/users", middleware.AdminRequired(), userHandler.ListUsers)
		auth.POST("/api/users", middleware.AdminRequired(), userHandler.CreateUser)
		auth.DELETE("/api/users/:id", middleware.AdminRequired(), userHandler.DeleteUser)
		auth.POST("/api/users/:id/reset-password", middleware.AdminRequired(), userHandler.ResetPassword)
		auth.POST("/api/users/:id/toggle-admin", middleware.AdminRequired(), userHandler.ToggleAdmin)
		auth.POST("/api/users/:id/block", userHandler.BlockUser)
		auth.DELETE("/api/users/:id/block", userHandler.UnblockUser)
		auth.GET("/api/users/stats", middleware.AdminRequired(), userHandler.GetStats)

		// Posts
		auth.GET("/api/posts", postHandler.ListPosts)
		auth.GET("/api/posts/:id", postHandler.GetPost)
		auth.POST("/api/posts", postHandler.CreatePost)
		auth.DELETE("/api/posts/:id", postHandler.DeletePost)

		// Stories
		auth.GET("/api/stories", storyHandler.ListStories)
		auth.GET("/api/stories/:id", storyHandler.GetStory)
		auth.POST("/api/stories", storyHandler.CreateStory)
		auth.POST("/api/stories/:id/view", storyHandler.ViewStory)
		auth.DELETE("/api/stories/:id", storyHandler.DeleteStory)

		// Likes
		auth.POST("/api/posts/:id/like", likeHandler.ToggleLike)

		// Comments
		auth.GET("/api/posts/:id/comments", commentHandler.ListComments)
		auth.POST("/api/posts/:id/comments", commentHandler.CreateComment)
		auth.DELETE("/api/comments/:id", commentHandler.DeleteComment)

		// Notifications
		auth.GET("/api/notifications", notificationHandler.ListNotifications)
		auth.GET("/api/notifications/unread-count", notificationHandler.UnreadCount)
		auth.POST("/api/notifications/read", notificationHandler.MarkRead)

		// Reports
		auth.POST("/api/reports", reportHandler.CreateReport)
		auth.GET("/api/admin/reports", middleware.AdminRequired(), reportHandler.ListReports)
		auth.PUT("/api/admin/reports/:id", middleware.AdminRequired(), reportHandler.UpdateReport)

		// Admin content moderation
		adminContentHandler := &handlers.AdminContentHandler{
			DB:         sqlDB,
			MediaStore: mediaStore,
		}
		admin := auth.Group("/api/admin")
		admin.Use(middleware.AdminRequired())
		{
			admin.GET("/content", adminContentHandler.ListContent)
			admin.DELETE("/content/posts/:id", adminContentHandler.DeletePost)
			admin.DELETE("/content/stories/:id", adminContentHandler.DeleteStory)
			admin.DELETE("/content/comments/:id", adminContentHandler.DeleteComment)
		}

		// Media
		auth.POST("/api/media", mediaHandler.Upload)
		auth.GET("/media/*filepath", mediaHandler.Serve)
	}

	// Admin panel - static file serving with SPA routing
	// Serve admin.html for /admin (exact path)
	router.GET("/admin", func(c *gin.Context) {
		c.File("./web/admin.html")
	})
	// Serve static files and SPA fallback for /admin/* paths
	router.GET("/admin/*adminPath", func(c *gin.Context) {
		requestedPath := c.Param("adminPath")
		rel := filepath.Clean(requestedPath)
		if rel == "." || rel == "/" || rel == "" {
			c.File("./web/admin.html")
			return
		}

		fullPath := filepath.Join("./web", rel)

		// Security: ensure path is still within ./web (prevent directory traversal)
		absPath, err := filepath.Abs(fullPath)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}

		absWeb, err := filepath.Abs("./web")
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "server error"})
			return
		}

		if !strings.HasPrefix(absPath, absWeb+string(filepath.Separator)) && absPath != absWeb {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}

		// Check if the requested file exists and is not a directory
		info, err := os.Stat(absPath)
		if err != nil || info.IsDir() {
			// Serve admin.html for SPA routing (JavaScript router handles the path)
			c.File("./web/admin.html")
			return
		}

		// Serve the static file
		c.File(absPath)
	})

	// Serve web app assets (no directory listings, 404 for missing files)
	router.GET("/app.css", func(c *gin.Context) {
		c.Header("Cache-Control", "public, max-age=86400")
		c.File("./web/app.css")
	})
	router.GET("/js/*filepath", func(c *gin.Context) {
		serveWebStatic(c, "./web/js", "filepath")
	})

	// PWA manifest, service worker, and icons
	router.GET("/manifest.json", func(c *gin.Context) {
		c.Header("Cache-Control", "public, max-age=3600")
		c.File("./web/manifest.json")
	})
	router.GET("/sw.js", func(c *gin.Context) {
		c.Header("Cache-Control", "no-cache, no-store, must-revalidate")
		c.Header("Content-Type", "application/javascript")
		c.File("./web/sw.js")
	})
	router.GET("/icons/*filepath", func(c *gin.Context) {
		serveWebStatic(c, "./web/icons", "filepath")
	})

	// Serve web app shell at root
	router.GET("/", func(c *gin.Context) {
		c.Header("Cache-Control", "no-cache")
		c.File("./web/index.html")
	})

	// SPA fallback: any unmatched non-API/non-admin/non-media path returns index.html
	router.NoRoute(func(c *gin.Context) {
		path := c.Request.URL.Path
		if strings.HasPrefix(path, "/api/") || strings.HasPrefix(path, "/media/") || strings.HasPrefix(path, "/admin") {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.Header("Cache-Control", "no-cache")
		c.File("./web/index.html")
	})

	// 11. Start cleanup job goroutine
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cleanupJob := jobs.NewCleanupJob(sqlDB, mediaStore, 1*time.Hour, logger)
	cleanupJob.Start(ctx)

	// 12. Setup graceful shutdown
	srv := &http.Server{
		Addr:         cfg.ServerBind + ":" + cfg.Port,
		Handler:      router,
		ReadTimeout:  5 * time.Minute,
		WriteTimeout: 5 * time.Minute,
		IdleTimeout:  120 * time.Second,
	}

	// Start server in a goroutine
	go func() {
		logger.Info("starting server", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server failed to start", "error", err)
			os.Exit(1)
		}
	}()

	// Wait for interrupt signal
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("shutting down server")

	// Shutdown sequence
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	// 1. Stop background goroutines
	cleanupJob.Stop()
	rateLimiter.Stop()
	strictRateLimiter.Stop()

	// 2. Graceful server shutdown with 10s timeout
	if err := srv.Shutdown(shutdownCtx); err != nil {
		logger.Error("server forced to shutdown", "error", err)
	}

	// 3. Close database connection
	if err := db.Close(); err != nil {
		logger.Error("failed to close database", "error", err)
	}

	logger.Info("server exited gracefully")
}
