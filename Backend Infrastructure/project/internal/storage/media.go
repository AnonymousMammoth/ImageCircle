package storage

import (
	"fmt"
	"io"
	"mime/multipart"
	"os"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"github.com/rwcarlsen/goexif/exif"
)

var allowedMimeTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"video/mp4":       ".mp4",
	"video/quicktime": ".mov",
	"image/heic":      ".heic",
}

// magicBytes holds the expected file signatures for each MIME type.
var magicBytes = map[string][]byte{
	"image/jpeg":      {0xFF, 0xD8, 0xFF},
	"image/png":       {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A},
	"video/mp4":       {0x00, 0x00, 0x00},
	"video/quicktime": {0x00, 0x00, 0x00},
	"image/heic":      {0x00, 0x00, 0x00},
}

// MediaStore handles filesystem operations for media files.
type MediaStore struct {
	BasePath string
}

// NewMediaStore creates a new MediaStore with the given base path.
func NewMediaStore(basePath string) *MediaStore {
	return &MediaStore{BasePath: basePath}
}

// SaveMedia saves an uploaded file to /{basePath}/{userID}/{uuid}.{ext}.
// It validates file type, file size, and magic bytes.
// Returns: relative path (e.g., "1/abc123.jpg"), full filename, error.
func (s *MediaStore) SaveMedia(userID int64, file multipart.File, header *multipart.FileHeader, maxSize int64) (string, string, error) {
	if header.Size > maxSize {
		return "", "", fmt.Errorf("file too large: %d bytes exceeds maximum %d bytes", header.Size, maxSize)
	}

	buffer := make([]byte, 512)
	n, err := file.Read(buffer)
	if err != nil {
		return "", "", fmt.Errorf("failed to read file header: %w", err)
	}

	detectedMime := detectMimeType(buffer[:n])
	if detectedMime == "" {
		return "", "", fmt.Errorf("unsupported file type")
	}

	ext, ok := allowedMimeTypes[detectedMime]
	if !ok {
		return "", "", fmt.Errorf("unsupported file type: %s", detectedMime)
	}

	if !validateMagicBytes(buffer[:n], detectedMime) {
		return "", "", fmt.Errorf("file content does not match claimed type")
	}

	_, err = file.Seek(0, io.SeekStart)
	if err != nil {
		return "", "", fmt.Errorf("failed to seek file: %w", err)
	}

	filename := uuid.New().String() + ext
	relativePath := filepath.Join(fmt.Sprintf("%d", userID), filename)
	fullPath := filepath.Join(s.BasePath, relativePath)

	userDir := filepath.Join(s.BasePath, fmt.Sprintf("%d", userID))
	if err := os.MkdirAll(userDir, 0o700); err != nil {
		return "", "", fmt.Errorf("failed to create user media directory: %w", err)
	}

	dst, err := os.OpenFile(fullPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return "", "", fmt.Errorf("failed to create destination file: %w", err)
	}
	defer dst.Close()

	_, err = io.Copy(dst, file)
	if err != nil {
		_ = os.Remove(fullPath)
		return "", "", fmt.Errorf("failed to write file: %w", err)
	}

	return relativePath, filename, nil
}

// DeleteMedia removes a media file by relative path.
func (s *MediaStore) DeleteMedia(relativePath string) error {
	fullPath := s.GetFullPath(relativePath)
	if err := os.Remove(fullPath); err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("failed to delete media file: %w", err)
	}
	return nil
}

// GetFullPath returns the absolute filesystem path for a relative path.
func (s *MediaStore) GetFullPath(relativePath string) string {
	return filepath.Join(s.BasePath, relativePath)
}

// ValidateNoGPS checks if an image contains EXIF GPS data.
// Returns an error if GPS data is found, indicating the upload should be rejected.
// Skips the check for HEIC files and video files due to limited EXIF support.
func (s *MediaStore) ValidateNoGPS(file multipart.File, mimeType string) error {
	if mimeType == "image/heic" || mimeType == "video/mp4" || mimeType == "video/quicktime" {
		return nil
	}

	if mimeType != "image/jpeg" && mimeType != "image/png" {
		return nil
	}

	_, err := file.Seek(0, io.SeekStart)
	if err != nil {
		return fmt.Errorf("failed to seek file for EXIF check: %w", err)
	}

	x, err := exif.Decode(file)
	if err != nil {
		return nil
	}

	_, err = x.Get(exif.GPSLatitude)
	if err == nil {
		return fmt.Errorf("image contains GPS location data")
	}

	_, err = x.Get(exif.GPSLongitude)
	if err == nil {
		return fmt.Errorf("image contains GPS location data")
	}

	tag, err := x.Get(exif.GPSInfoIFDPointer)
	if err == nil && tag != nil {
		return fmt.Errorf("image contains GPS location data")
	}

	return nil
}

// detectMimeType detects the MIME type from file magic bytes.
func detectMimeType(data []byte) string {
	if len(data) < 8 {
		return ""
	}

	if len(data) >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
		return "image/jpeg"
	}

	if len(data) >= 8 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 &&
		data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A {
		return "image/png"
	}

	if len(data) >= 12 && data[4] == 'f' && data[5] == 't' && data[6] == 'y' && data[7] == 'p' {
		majorBrand := strings.ToLower(string(data[8:12]))
		switch {
		case strings.Contains(majorBrand, "mp4") || strings.Contains(majorBrand, "mmp4") || strings.Contains(majorBrand, "iso"):
			return "video/mp4"
		case strings.Contains(majorBrand, "qt") || strings.Contains(majorBrand, "mov"):
			return "video/quicktime"
		case strings.Contains(majorBrand, "heic") || strings.Contains(majorBrand, "heix") || strings.Contains(majorBrand, "mif1"):
			return "image/heic"
		}

		brandStr := strings.ToLower(string(data[8:]))
		if strings.Contains(brandStr, "heic") || strings.Contains(brandStr, "mif1") || strings.Contains(brandStr, "heix") {
			return "image/heic"
		}
	}

	if len(data) >= 16 {
		headerStr := strings.ToLower(string(data[:16]))
		if strings.Contains(headerStr, "heic") {
			return "image/heic"
		}
	}

	if len(data) >= 8 {
		atomType := string(data[4:8])
		if atomType == "moov" || atomType == "mdat" || atomType == "wide" {
			return "video/quicktime"
		}
	}

	return ""
}

// validateMagicBytes checks whether the file's magic bytes match the expected signature.
func validateMagicBytes(data []byte, mimeType string) bool {
	expected, ok := magicBytes[mimeType]
	if !ok {
		return false
	}

	if len(data) < len(expected) {
		return false
	}

	if mimeType == "video/mp4" || mimeType == "video/quicktime" || mimeType == "image/heic" {
		return detectMimeType(data) == mimeType
	}

	for i, b := range expected {
		if data[i] != b {
			return false
		}
	}
	return true
}
