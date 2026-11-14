// Command server runs the KIITPulse campus backend.
//
// Designed to run with or without external dependencies: Redis is required for
// the radar (it *is* the radar), but the process starts and serves /healthz
// even when Redis is unreachable, so a deploy can be verified before the data
// store is wired up. Degraded means degraded, not a crash loop.
//
//	KIITPULSE_JWT_SECRET   >=32 bytes, required
//	KIITPULSE_REDIS_ADDR   default 127.0.0.1:6379
//	KIITPULSE_REDIS_PASS   optional
//	KIITPULSE_ADDR         default :8080
//	KIITPULSE_ORIGIN       CORS origin, default *
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/api"
	"github.com/kiitpulse/backend/auth"
	"github.com/kiitpulse/backend/chat"
	"github.com/kiitpulse/backend/domain"
	"github.com/kiitpulse/backend/radar"
	"github.com/kiitpulse/backend/stage"
	"github.com/kiitpulse/backend/voice"
)

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	}))

	secret := env("KIITPULSE_JWT_SECRET", "")
	if len(secret) < 32 {
		log.Error("KIITPULSE_JWT_SECRET must be at least 32 bytes",
			"have", len(secret))
		// A short secret is a real vulnerability, not a warning: refuse.
		os.Exit(1)
	}

	authSvc, err := auth.NewService(secret, 12*time.Hour)
	if err != nil {
		log.Error("auth init", "err", err)
		os.Exit(1)
	}

	rdb := redis.NewClient(&redis.Options{
		Addr:     env("KIITPULSE_REDIS_ADDR", "127.0.0.1:6379"),
		Password: env("KIITPULSE_REDIS_PASS", ""),
		DB:       0,
	})

	pingCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	if err := rdb.Ping(pingCtx).Err(); err != nil {
		log.Warn("redis unreachable; radar will return 503 until it comes up",
			"addr", rdb.Options().Addr, "err", err)
	} else {
		log.Info("redis connected", "addr", rdb.Options().Addr)
	}
	cancel()

	store := radar.NewStore(rdb)

	// Persist every message the hub broadcasts so a reconnecting client can
	// replay what it missed. Fire-and-forget with its own timeout: the sender
	// must not wait on Redis.
	hub := chat.NewHub(log,
		chat.WithJoinHook(func(topicID string) {
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
				defer cancel()
				_ = rdb.Expire(ctx, "kiit:messages:"+topicID, radar.TopicTTL*time.Second).Err()
			}()
		}),
		chat.WithMessageStore(func(m domain.EphemeralMessage) {
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				defer cancel()
				if err := store.AppendMessage(ctx, m); err != nil {
					log.Error("persist message", "topic", m.TopicID, "err", err)
				}
			}()
		}),
	)

	voiceCfg := voice.Config{
		URL:       env("KIITPULSE_LIVEKIT_URL", ""),
		APIKey:    env("KIITPULSE_LIVEKIT_KEY", ""),
		APISecret: env("KIITPULSE_LIVEKIT_SECRET", ""),
	}
	if voiceCfg.Configured() {
		log.Info("voice enabled", "url", voiceCfg.URL)
	} else {
		log.Warn("voice disabled: set KIITPULSE_LIVEKIT_URL/_KEY/_SECRET to enable stages")
	}

	router := api.NewRouter(api.Deps{
		Log:         log,
		Auth:        authSvc,
		Radar:       store,
		Hub:         hub,
		Redis:       rdb,
		AllowOrigin: env("KIITPULSE_ORIGIN", "*"),
		Voice:       voiceCfg,
		Stage:       stage.New(),
	})

	srv := &http.Server{
		Addr:              env("KIITPULSE_ADDR", ":8080"),
		Handler:           router,
		ReadHeaderTimeout: 10 * time.Second,
		// No WriteTimeout: WebSocket connections are long-lived by design.
		IdleTimeout: 120 * time.Second,
	}

	// ---- decay cron ----------------------------------------------------
	stopCron := startDecayCron(log, store)

	// ---- serve ---------------------------------------------------------
	go func() {
		log.Info("listening", "addr", srv.Addr)
		if err := srv.ListenAndServe(); err != nil &&
			!errors.Is(err, http.ErrServerClosed) {
			log.Error("server", "err", err)
			os.Exit(1)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Info("shutting down")

	stopCron()
	hub.CloseAll()

	shutdownCtx, shutdownCancel := context.WithTimeout(
		context.Background(), 10*time.Second)
	defer shutdownCancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("forced shutdown", "err", err)
	}
	_ = rdb.Close()
	log.Info("bye")
}

// startDecayCron applies the velocity decay once a minute.
//
// Ticker rather than cron syntax: one fixed interval needs no dependency, and
// the score is a smoothed ranking where a few seconds of drift is invisible.
func startDecayCron(log *slog.Logger, store *radar.Store) func() {
	ticker := time.NewTicker(time.Minute)
	done := make(chan struct{})
	go func() {
		for {
			select {
			case <-ticker.C:
				ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
				purged, err := store.DecayAll(ctx)
				cancel()
				if err != nil {
					log.Error("decay", "err", err)
					continue
				}
				if purged > 0 {
					log.Info("decay purged cold topics", "count", purged)
				}
			case <-done:
				return
			}
		}
	}()
	return func() {
		ticker.Stop()
		close(done)
	}
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
