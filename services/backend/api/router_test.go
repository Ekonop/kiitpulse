package api

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/auth"
	"github.com/kiitpulse/backend/chat"
	"github.com/kiitpulse/backend/domain"
	"github.com/kiitpulse/backend/radar"
)

// newTestRouter builds a router with no Redis. Handlers that need Redis will
// fail with 503, which is the degraded behaviour we want to assert.
func newTestRouter(t *testing.T) (http.Handler, *auth.Service) {
	t.Helper()
	svc, err := auth.NewService("0123456789abcdef0123456789abcdef", time.Hour)
	if err != nil {
		t.Fatalf("auth service: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1"}) // nothing listens here
	log := slog.New(slog.NewTextHandler(io_discard{}, nil))

	return NewRouter(Deps{
		Log:         log,
		Auth:        svc,
		Radar:       radar.NewStore(rdb),
		Hub:         chat.NewHub(log, nil),
		Redis:       rdb,
		AllowOrigin: "*",
	}), svc
}

type io_discard struct{}

func (io_discard) Write(p []byte) (int, error) { return len(p), nil }

func TestHealth(t *testing.T) {
	r, _ := newTestRouter(t)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, httptest.NewRequest(http.MethodGet, "/healthz", nil))

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, want 200", w.Code)
	}
	var body map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &body)
	if body["status"] != "ok" {
		t.Errorf("status field = %v", body["status"])
	}
}

func TestSignInRejectsNonCampusEmail(t *testing.T) {
	r, _ := newTestRouter(t)

	cases := []struct {
		email      string
		wantStatus int
		wantCode   string
	}{
		{"student@gmail.com", http.StatusForbidden, "KIIT_DOMAIN_REQUIRED"},
		{"241551058@kiit.ac.in.evil.com", http.StatusForbidden, "KIIT_DOMAIN_REQUIRED"},
		{"vansh@kiit.ac.in", http.StatusForbidden, "KIIT_ROLL_INVALID"},
	}

	for _, tc := range cases {
		t.Run(tc.email, func(t *testing.T) {
			body := strings.NewReader(`{"email":"` + tc.email + `"}`)
			req := httptest.NewRequest(http.MethodPost, "/auth/signin", body)
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			r.ServeHTTP(w, req)

			if w.Code != tc.wantStatus {
				t.Fatalf("status = %d, want %d", w.Code, tc.wantStatus)
			}
			var resp map[string]any
			_ = json.Unmarshal(w.Body.Bytes(), &resp)
			if resp["code"] != tc.wantCode {
				t.Errorf("code = %v, want %v", resp["code"], tc.wantCode)
			}
		})
	}
}

func TestSignInIssuesSessionForCampusEmail(t *testing.T) {
	r, svc := newTestRouter(t)

	body := strings.NewReader(`{"email":"241551058@kiit.ac.in"}`)
	req := httptest.NewRequest(http.MethodPost, "/auth/signin", body)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", w.Code, w.Body.String())
	}

	var resp struct {
		RollNumber string `json:"roll_number"`
		BranchTag  string `json:"branch_tag"`
		Token      string `json:"token"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.RollNumber != "241551058" {
		t.Errorf("roll = %q", resp.RollNumber)
	}
	if resp.BranchTag != "CSE-AIML '28" {
		t.Errorf("branch = %q", resp.BranchTag)
	}

	// The issued token must actually work on a protected route.
	student, err := svc.Verify(resp.Token)
	if err != nil {
		t.Fatalf("issued token does not verify: %v", err)
	}
	if student.RollNumber != "241551058" {
		t.Errorf("verified roll = %q", student.RollNumber)
	}
}

// TestProtectedRoutesRequireSession is the security boundary test: every
// non-public route must reject a request with no token, and with a bad token.
func TestProtectedRoutesRequireSession(t *testing.T) {
	r, _ := newTestRouter(t)

	protected := []struct{ method, path string }{
		{http.MethodGet, "/radar/zones/campus15"},
		{http.MethodGet, "/radar/zones/campus15/population"},
		{http.MethodPost, "/radar/topics"},
		{http.MethodPost, "/voice/token"},
		{http.MethodPost, "/voice/hand-raise"},
		{http.MethodGet, "/voice/stage/t1"},
		{http.MethodGet, "/topics/t1/messages"},
		{http.MethodGet, "/passport/241551058"},
	}

	for _, route := range protected {
		t.Run(route.path, func(t *testing.T) {
			for _, token := range []string{"", "Bearer garbage", "Bearer "} {
				req := httptest.NewRequest(route.method, route.path, nil)
				if token != "" {
					req.Header.Set("Authorization", token)
				}
				w := httptest.NewRecorder()
				r.ServeHTTP(w, req)

				if w.Code != http.StatusUnauthorized {
					t.Errorf("%s with token %q: status = %d, want 401",
						route.path, token, w.Code)
				}
			}
		})
	}
}

// TestPassportIsSelfOnly: a valid session must not read another student's
// passport.
func TestPassportIsSelfOnly(t *testing.T) {
	r, svc := newTestRouter(t)
	token, _, err := svc.Issue(domainStudent("241551058"))
	if err != nil {
		t.Fatalf("issue: %v", err)
	}

	req := httptest.NewRequest(http.MethodGet, "/passport/999999999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden {
		t.Errorf("status = %d, want 403 for another student's passport", w.Code)
	}
}

func TestUnknownZoneRejected(t *testing.T) {
	r, svc := newTestRouter(t)
	token, _, _ := svc.Issue(domainStudent("241551058"))

	req := httptest.NewRequest(http.MethodGet, "/radar/zones/atlantis", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want 400 for an unknown zone", w.Code)
	}
}

func TestVoiceTokenNeverGrantsPublish(t *testing.T) {
	r, svc := newTestRouter(t)
	token, _, _ := svc.Issue(domainStudent("241551058"))

	body := strings.NewReader(`{"topic_id":"t1","as_speaker":true}`)
	req := httptest.NewRequest(http.MethodPost, "/voice/token", body)
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("status = %d", w.Code)
	}
	var resp map[string]any
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	// Even asking as_speaker:true must not produce a publish grant from this
	// endpoint - promotion is a separate server-authorised action.
	if resp["publish"] != false {
		t.Errorf("publish = %v, want false", resp["publish"])
	}
}

func domainStudent(roll string) domain.Student {
	return domain.Student{
		Email:      roll + "@kiit.ac.in",
		RollNumber: roll,
		BranchTag:  auth.BranchTagFor(roll),
	}
}
