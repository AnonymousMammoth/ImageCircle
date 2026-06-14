# Makefile for Circle - Private Photo Sharing Platform
#
# Provides convenient shortcuts for common development and deployment tasks.
# All paths are relative to the project root.

.PHONY: build run docker-build docker-up docker-down test clean help

# ---------------------------------------------------------------------------
# Go Application
# ---------------------------------------------------------------------------

# Build the Go binary locally
# Requires: Go 1.22+, gcc (for CGO/SQLite3)
build:
	@echo "Building Circle..."
	CGO_ENABLED=1 go build -ldflags='-s -w' -o circle ./cmd/server
	@echo "Build complete: ./circle"

# Run the application locally (development)
# Assumes .env file exists with required variables
run:
	@echo "Starting Circle (local)..."
	@if [ ! -f .env ]; then echo "Warning: .env file not found"; fi
	mkdir -p data/media
n	CGO_ENABLED=1 go run ./cmd/server

# Run Go tests
# Includes race detection and verbose output
test:
	@echo "Running tests..."
	go test -race -v ./...

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

# Build the Docker image
# Uses multi-stage build for minimal final image
docker-build:
	@echo "Building Docker image..."
	docker compose build --no-cache

# Start all services in detached mode
# Services: circle-app (Go backend), circle-nginx (reverse proxy)
docker-up:
	@echo "Starting Docker services..."
	mkdir -p data/media
	docker compose up -d
	@echo "Services started. Check status: make docker-logs"

# Stop all services
docker-down:
	@echo "Stopping Docker services..."
	docker compose down

# View logs from all services
docker-logs:
	docker compose logs -f --tail=100

# Restart services (useful after config changes)
docker-restart: docker-down docker-up

# Pull latest images and rebuild
docker-update:
	@echo "Updating Docker services..."
	docker compose pull
	docker compose up -d --build

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

# Remove compiled binary and local data directory
clean:
	@echo "Cleaning up..."
	rm -f circle
	rm -rf data/
	@echo "Cleanup complete"

# Deep clean: remove Docker volumes and images too
clean-all: docker-down clean
	@echo "Removing Docker volumes and images..."
	docker compose rm -f -v
	docker rmi circle-app 2>/dev/null || true
	@echo "Deep cleanup complete"

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

# Show help for all targets
help:
	@echo "Circle - Available targets:"
	@echo ""
	@echo "  Development:"
	@echo "    make build          Build Go binary locally"
	@echo "    make run            Run application locally (dev)"
	@echo "    make test           Run Go test suite"
	@echo ""
	@echo "  Docker:"
	@echo "    make docker-build   Build Docker image"
	@echo "    make docker-up      Start all services"
	@echo "    make docker-down    Stop all services"
	@echo "    make docker-logs    View service logs"
	@echo "    make docker-restart Restart all services"
	@echo "    make docker-update  Pull and rebuild services"
	@echo ""
	@echo "  Cleanup:"
	@echo "    make clean          Remove binary and data/"
	@echo "    make clean-all      Remove everything including Docker volumes"
	@echo ""
	@echo "  Help:"
	@echo "    make help           Show this help message"
