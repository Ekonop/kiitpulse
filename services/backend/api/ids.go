// Package api: small helpers shared by the route handlers.
package api

import (
	"crypto/rand"
	"encoding/hex"
)

// newID returns a short, collision-resistant identifier with a prefix.
//
// Random rather than sequential: a guessable topic id lets anyone enumerate
// rooms, and these ids appear in URLs.
func newID(prefix string) string {
	b := make([]byte, 9)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand only fails if the OS entropy source is broken, in which
		// case a predictable id is the least of the problems.
		return prefix + "-fallback"
	}
	return prefix + "-" + hex.EncodeToString(b)
}
