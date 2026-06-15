package utils

import (
	"regexp"
	"strings"
)

// mentionRe matches @username mentions. The @ must be preceded by whitespace
// or the start of the string so email addresses are not treated as mentions.
var mentionRe = regexp.MustCompile(`(?:^|\s)@([a-zA-Z0-9_]+)`)

// ExtractMentions returns a deduplicated, case-folded list of usernames
// mentioned in text (without the leading @).
func ExtractMentions(text string) []string {
	seen := make(map[string]struct{})
	var out []string
	for _, m := range mentionRe.FindAllStringSubmatch(text, -1) {
		username := strings.ToLower(m[1])
		if _, ok := seen[username]; ok {
			continue
		}
		seen[username] = struct{}{}
		out = append(out, username)
	}
	return out
}
