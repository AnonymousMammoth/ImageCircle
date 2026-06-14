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

	// 7. Initialize rate limiter
	rateLimiter := middleware.NewRateLimiter(cfg.RateLimit)

	// 8. Create gin router with middleware stack
	router := gin.New()

	// Recovery middleware (gin built-in, suppresses stack traces in release mode)
	router.Use(gin.Recovery())

	// Security headers
	router.Use(middleware.SecurityHeaders(cfg.AllowedOrigin))

	// Logger (zero-PII)
	router.Use(middleware.Logger())

	// Rate limiter
	router.Use(rateLimiter.Middleware())

	// CORS
	router.Use(middleware.CORS(cfg.AllowedOrigin))

	// 9. Initialize all handlers
	authHandler := &handlers.AuthHandler{
		DB:           sqlDB,
		JWTSecret:    cfg.JWTSecret,
		PasswordCost: cfg.PasswordCost,
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

	mediaHandler := &handlers.MediaHandler{
		MediaStore: mediaStore,
		MaxSize:    cfg.MaxMediaSize,
	}

	// Set up token blacklist checker for auth middleware
	middleware.TokenBlacklistChecker = func(tokenString string) (bool, error) {
		return models.IsTokenBlacklisted(sqlDB, tokenString)
	}

	// 10. Setup routes

	// Health check (no auth, for Docker healthcheck)
	router.GET("/api/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	// Public (no auth)
	router.POST("/api/admin/setup", authHandler.Setup)
	router.POST("/api/auth/login", authHandler.Login)

	// Authenticated routes
	auth := router.Group("/")
	auth.Use(middleware.AuthRequired(cfg.JWTSecret))
	{
		// Auth
		auth.POST("/api/auth/refresh", authHandler.Refresh)
		auth.POST("/api/auth/change-password", authHandler.ChangePassword)
		auth.POST("/api/auth/logout", authHandler.Logout)

		// Users
		auth.GET("/api/users/search", userHandler.SearchUsers)
		auth.GET("/api/users/me", userHandler.GetMe)
		auth.PUT("/api/users/me", userHandler.UpdateMe)
		auth.POST("/api/users/me/avatar", userHandler.UpdateAvatar)
		auth.GET("/api/users/:id/posts", userHandler.GetUserPosts)
		auth.GET("/api/users/:id/stories", userHandler.GetUserStories)
		auth.GET("/api/users", middleware.AdminRequired(), userHandler.ListUsers)
		auth.POST("/api/users", middleware.AdminRequired(), userHandler.CreateUser)
		auth.DELETE("/api/users/:id", middleware.AdminRequired(), userHandler.DeleteUser)
		auth.POST("/api/users/:id/reset-password", middleware.AdminRequired(), userHandler.ResetPassword)
		auth.POST("/api/users/:id/toggle-admin", middleware.AdminRequired(), userHandler.ToggleAdmin)
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

		// Media
		auth.POST("/api/media", mediaHandler.Upload)
	}

	// Serve media files (public access - URLs are already unguessable)
	router.Static("/media", cfg.MediaDir)

	// Admin panel - static file serving with SPA routing
	// Serve admin.html for /admin (exact path)
	router.GET("/admin", func(c *gin.Context) {
		c.File("./web/admin.html")
	})
	// Serve static files and SPA fallback for /admin/* paths
	router.GET("/admin/*adminPath", func(c *gin.Context) {
		requestedPath := c.Param("adminPath")
		fullPath := filepath.Join("./web", filepath.Clean(requestedPath))

		// Security: ensure path is still within ./web (prevent directory traversal)
		absPath, _ := filepath.Abs(fullPath)
		absWeb, _ := filepath.Abs("./web")
		if !strings.HasPrefix(absPath, absWeb) {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}

		// Check if the requested file exists and is not a directory
		info, err := os.Stat(fullPath)
		if err != nil || info.IsDir() {
			// Serve admin.html for SPA routing (JavaScript router handles the path)
			c.File("./web/admin.html")
			return
		}

		// Serve the static file
		c.File(fullPath)
	})

	// Redirect root to /admin
	router.GET("/", func(c *gin.Context) {
		c.Redirect(http.StatusMovedPermanently, "/admin")
	})

	// 11. Start cleanup job goroutine
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	cleanupJob := jobs.NewCleanupJob(sqlDB, mediaStore, 1*time.Hour, logger)
	cleanupJob.Start(ctx)

	// 12. Setup graceful shutdown
	srv := &http.Server{
		Addr:    cfg.ServerBind + ":" + cfg.Port,
		Handler: router,
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

	// 1. Stop cleanup job
	cleanupJob.Stop()

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
