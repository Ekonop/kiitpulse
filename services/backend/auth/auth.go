// Package auth implements the @kiit.ac.in identity guard and session tokens.
//
// Two things this package is careful about:
//
//  1. The domain check happens on the *server*, not only in the app. A client
//     can lie about its own email string; the server cannot.
//  2. Token verification is constant-time and the roll number is derived from
//     the verified email, never accepted from the request body.
package auth

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"

	"github.com/kiitpulse/backend/domain"
)

// CampusDomain is the only domain allowed to authenticate.
const CampusDomain = "@kiit.ac.in"

var (
	ErrNotCampus      = errors.New("only verified @kiit.ac.in accounts are permitted")
	ErrInvalidRoll    = errors.New("email local part is not a KIIT roll number")
	ErrInvalidToken   = errors.New("invalid or expired session token")
	ErrNoSession      = errors.New("no session on this request")
)

// rollPattern accepts the 6-12 digit roll numbers KIIT actually issues.
var rollPattern = regexp.MustCompile(`^[0-9]{6,12}$`)

// Service issues and verifies session tokens.
type Service struct {
	secret   []byte
	ttl      time.Duration
	issuer   string
}

// NewService builds a token service. `secret` must be at least 32 bytes in
// production; NewService refuses short secrets rather than signing with them.
func NewService(secret string, ttl time.Duration) (*Service, error) {
	if len(secret) < 32 {
		return nil, fmt.Errorf("auth: HMAC secret must be at least 32 bytes, got %d", len(secret))
	}
	return &Service{
		secret: []byte(secret),
		ttl:    ttl,
		issuer: "kiitpulse",
	}, nil
}

// StudentFromEmail validates a campus identity and derives the roll number.
//
// This is the single place the domain rule lives. Both the demo sign-in and a
// real Google/Microsoft OAuth callback must route through it.
func StudentFromEmail(email string) (domain.Student, error) {
	clean := strings.ToLower(strings.TrimSpace(email))
	if !strings.HasSuffix(clean, CampusDomain) {
		return domain.Student{}, ErrNotCampus
	}
	roll := strings.TrimSuffix(clean, CampusDomain)
	if !rollPattern.MatchString(roll) {
		return domain.Student{}, ErrInvalidRoll
	}
	return domain.Student{
		Email:      clean,
		RollNumber: roll,
		BranchTag:  BranchTagFor(roll),
	}, nil
}

// BranchTagFor maps a roll number prefix to a programme tag.
//
// Mirrors AuthController.branchTagFor in the Flutter client. Pinned by
// auth_test.go so a new batch prefix is added in both places.
func BranchTagFor(roll string) string {
	switch {
	case strings.HasPrefix(roll, "24155"):
		return "CSE-AIML '28"
	case strings.HasPrefix(roll, "24156"):
		return "IT '28"
	case strings.HasPrefix(roll, "2405"):
		return "CSE '28"
	case strings.HasPrefix(roll, "2406"):
		return "IT '28"
	case strings.HasPrefix(roll, "2305"):
		return "CSE '27"
	case strings.HasPrefix(roll, "2306"):
		return "IT '27"
	case strings.HasPrefix(roll, "22"):
		return "Senior"
	default:
		return "KIIT Student"
	}
}

// Claims is the session token body.
type Claims struct {
	Roll      string `json:"roll"`
	BranchTag string `json:"branch_tag"`
	jwt.RegisteredClaims
}

// Issue signs a session token for a verified student.
func (s *Service) Issue(student domain.Student) (string, int64, error) {
	now := time.Now()
	claims := Claims{
		Roll:      student.RollNumber,
		BranchTag: student.BranchTag,
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   student.RollNumber,
			Issuer:    s.issuer,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(s.ttl)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	signed, err := token.SignedString(s.secret)
	if err != nil {
		return "", 0, err
	}
	return signed, int64(s.ttl.Seconds()), nil
}

// Verify parses and validates a session token.
//
// The signing method is checked explicitly: without that check a token signed
// with "none" or an asymmetric algorithm could be accepted.
func (s *Service) Verify(raw string) (domain.Student, error) {
	parser := jwt.NewParser(
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(s.issuer),
		jwt.WithExpirationRequired(),
	)

	claims := &Claims{}
	token, err := parser.ParseWithClaims(raw, claims, func(t *jwt.Token) (any, error) {
		return s.secret, nil
	})
	if err != nil || !token.Valid {
		return domain.Student{}, ErrInvalidToken
	}
	if !rollPattern.MatchString(claims.Roll) {
		return domain.Student{}, ErrInvalidToken
	}
	// Re-derive the branch tag instead of trusting the one in the token: a
	// tampered branch tag would otherwise display on someone else's messages.
	return domain.Student{
		Email:      claims.Roll + CampusDomain,
		RollNumber: claims.Roll,
		BranchTag:  BranchTagFor(claims.Roll),
	}, nil
}

// ---- request context ---------------------------------------------------

type ctxKey struct{}

// WithStudent attaches an authenticated student to a context.
func WithStudent(ctx context.Context, s domain.Student) context.Context {
	return context.WithValue(ctx, ctxKey{}, s)
}

// FromContext retrieves the authenticated student.
func FromContext(ctx context.Context) (domain.Student, bool) {
	s, ok := ctx.Value(ctxKey{}).(domain.Student)
	return s, ok
}
