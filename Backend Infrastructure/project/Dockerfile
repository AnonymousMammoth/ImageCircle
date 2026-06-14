# Multi-stage Dockerfile for Circle
# Stage 1: Builder - compiles the Go binary with CGO/SQLite3 support
# Stage 2: Runtime - minimal Alpine image with non-root user
#
# Security features:
# - Multi-stage build keeps final image small (~20MB vs 400MB+)
# - Non-root user execution
# - Statically linked binary (no runtime CGO dependencies)
# - No secrets baked into image layers
# - Health check for container orchestration

# ---------------------------------------------------------------------------
# STAGE 1: Builder
# ---------------------------------------------------------------------------
FROM golang:1.22-alpine AS builder

# Install build-base for gcc, musl-dev, and other C compilation tools
# Required for CGO_ENABLED=1 with SQLite3 (mattn/go-sqlite3)
RUN apk add --no-cache build-base

WORKDIR /app

# Download dependencies first (layer caching)
COPY go.mod go.sum ./
RUN go mod download

# Copy all source code
COPY . .

# Build a statically linked binary
# -ldflags '-s -w'  : strip debug info and symbol table for smaller binary
# -extldflags "-static" : statically link all C libraries (SQLite3)
# CGO_ENABLED=1      : required for SQLite3 (CGO bindings)
# The resulting binary has no runtime dependencies
ENV CGO_ENABLED=1
RUN go build -ldflags='-s -w -extldflags "-static"' -o circle ./cmd/server

# ---------------------------------------------------------------------------
# STAGE 2: Runtime
# ---------------------------------------------------------------------------
FROM alpine:latest

# Install ca-certificates for HTTPS outbound connections
RUN apk add --no-cache ca-certificates wget

# Create non-root user for security
# -D: don't assign password (no login)
# -g '': empty GECOS field
RUN adduser -D -g '' circle

WORKDIR /app

# Copy only the compiled binary from builder
COPY --from=builder /app/circle .

# Copy admin panel static assets
COPY --from=builder /app/web ./web

# Create data directory and media subdirectory, owned by circle user
RUN mkdir -p /data/media && chown -R circle:circle /data

# Switch to non-root user
USER circle

# Expose the application port
EXPOSE 8080

# Mark /data as a volume for persistent storage
VOLUME ["/data"]

# Health check: verify API is responsive
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/api/health || exit 1

# Run the application
CMD ["./circle"]
