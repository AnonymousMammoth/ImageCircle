package utils

import (
	"github.com/gin-gonic/gin"
)

// RespondJSON sends a JSON response with the given status code and data.
func RespondJSON(c *gin.Context, status int, data interface{}) {
	c.JSON(status, data)
}

// RespondError sends a JSON error response with the given status code and message.
func RespondError(c *gin.Context, status int, message string) {
	c.JSON(status, gin.H{"error": message})
}

// RespondValidationError sends a JSON response containing field-specific validation errors.
func RespondValidationError(c *gin.Context, fieldErrors map[string]string) {
	c.JSON(422, gin.H{"errors": fieldErrors})
}

// RespondCreated sends a 201 Created JSON response with the given data.
func RespondCreated(c *gin.Context, data interface{}) {
	c.JSON(201, data)
}

// RespondNoContent sends a 204 No Content response.
func RespondNoContent(c *gin.Context) {
	c.Status(204)
}
