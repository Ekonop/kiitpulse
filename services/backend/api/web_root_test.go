package api

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/auth"
	"github.com/kiitpulse/backend/chat"
	"github.com/kiitpulse/backend/radar"
)

// The web root must serve the app on "/" and fall back to the shell for unknown
// paths, while never shadowing the API.
//
// This caught a real deployment bug: c.FileFromFS routes through
// http.FileServer, which answers GET / with a relative redirect to "./" and
// never serves index.html at all, so the public site 301'd in a loop.
func TestWebRootServesAppAndNotAPI(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"),
		[]byte("<!doctype html><title>kiitpulse</title>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(dir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "a.js"),
		[]byte("console.log(1)"), 0o644); err != nil {
		t.Fatal(err)
	}

	svc, err := auth.NewService("0123456789abcdef0123456789abcdef", time.Hour)
	if err != nil {
		t.Fatalf("auth service: %v", err)
	}
	rdb := redis.NewClient(&redis.Options{Addr: "127.0.0.1:1"})
	r := NewRouter(Deps{
		Log:         slog.New(slog.NewTextHandler(io_discard{}, nil)),
		Auth:        svc,
		Radar:       radar.NewStore(rdb),
		Hub:         chat.NewHub(slog.New(slog.NewTextHandler(io_discard{}, nil))),
		Redis:       rdb,
		AllowOrigin: "*",
		WebRoot:     dir,
	})

	cases := []struct {
		path string
		want int
		body string
	}{
		{"/", http.StatusOK, "kiitpulse"},
		{"/assets/a.js", http.StatusOK, "console.log"},
		// A deep link must boot the app rather than 404.
		{"/anything/else", http.StatusOK, "kiitpulse"},
		// The API must still answer JSON, not the shell.
		{"/healthz", http.StatusOK, "status"},
	}

	for _, c := range cases {
		rec := httptest.NewRecorder()
		r.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, c.path, nil))
		if rec.Code != c.want {
			t.Errorf("GET %s = %d, want %d", c.path, rec.Code, c.want)
			continue
		}
		if got := rec.Body.String(); !strings.Contains(got, c.body) {
			t.Errorf("GET %s body %q does not contain %q", c.path, got, c.body)
		}
	}
}
