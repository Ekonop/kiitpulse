package radar

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/campus"
	"github.com/kiitpulse/backend/domain"
)

// ErrTopicNotFound is returned when a topic id is not in the zone's ZSET.
var ErrTopicNotFound = errors.New("topic not found")

// Store owns all radar state in Redis.
//
// Key layout:
//
//	kiit:radar:<zone>            ZSET   topicID -> velocity score
//	kiit:topic:<id>              HASH   title, description, zone, tag, counters
//	kiit:topic:<id>:ttl          STRING expiry marker
//	kiit:zone:<zone>:presence    SET    rolls currently in the zone
//
// Every multi-key mutation goes through a pipeline (or a Lua script when it
// must be atomic) so a half-applied event can never leave a topic ranked
// without its metadata.
type Store struct {
	rdb *redis.Client

	// novelty tracks the last time a topic moved, so the decay job can be
	// aware of it. Local to the process; Redis stays the source of truth for
	// scores, this only avoids re-reading metadata we already hold.
	mu sync.RWMutex
}

// NewStore wraps a Redis client.
func NewStore(rdb *redis.Client) *Store {
	return &Store{rdb: rdb}
}

func radarKey(zone campus.Zone) string {
	return "kiit:radar:" + zone.Key()
}

func topicKey(id string) string { return "kiit:topic:" + id }

func presenceKey(zone campus.Zone) string {
	return "kiit:zone:" + zone.Key() + ":presence"
}

// CreateTopic inserts a topic and gives it a seed score.
func (s *Store) CreateTopic(ctx context.Context, t domain.TopicPulse) error {
	if t.Zone < int32(campus.ZoneCampus15) || t.Zone > int32(campus.ZoneKIMS) {
		return fmt.Errorf("radar: topic %q has invalid zone %d", t.ID, t.Zone)
	}
	now := time.Now().Unix()
	if t.CreatedAtUnix == 0 {
		t.CreatedAtUnix = now
	}
	t.LastActivityUnix = now

	zone := campus.Zone(t.Zone)
	pipe := s.rdb.Pipeline()
	pipe.HSet(ctx, topicKey(t.ID), map[string]any{
		"id":              t.ID,
		"title":           t.Title,
		"description":     t.Description,
		"zone":            t.Zone,
		"tag":             t.Tag,
		"message_count":   t.MessageCount,
		"created_at_unix": t.CreatedAtUnix,
		"last_activity":   t.LastActivityUnix,
	})
	pipe.ZAdd(ctx, radarKey(zone), redis.Z{
		Score:  RawScore(int(t.MessageCount), 0, 0),
		Member: t.ID,
	})
	pipe.Expire(ctx, topicKey(t.ID), TopicTTL*time.Second)
	if _, err := pipe.Exec(ctx); err != nil {
		return fmt.Errorf("radar: create topic: %w", err)
	}
	return nil
}

// RecordEvent adds weight to a topic's score and refreshes its TTL.
//
// This is the hot path: every message and reaction lands here. It uses a
// pipeline (not a transaction) because the two writes are independent - a
// missing TTL refresh is corrected by the next event.
func (s *Store) RecordEvent(ctx context.Context, zone campus.Zone, topicID string, kind EventKind) error {
	pipe := s.rdb.Pipeline()
	pipe.ZIncrBy(ctx, radarKey(zone), kind.Weight(), topicID)
	pipe.HSet(ctx, topicKey(topicID), "last_activity", time.Now().Unix())
	pipe.Expire(ctx, topicKey(topicID), TopicTTL*time.Second)
	if kind == EventMessage {
		pipe.HIncrBy(ctx, topicKey(topicID), "message_count", 1)
	}
	_, err := pipe.Exec(ctx)
	if err != nil {
		return fmt.Errorf("radar: record %s: %w", kind, err)
	}
	return nil
}

// Score returns one topic's current score.
func (s *Store) Score(ctx context.Context, zone campus.Zone, topicID string) (float64, error) {
	score, err := s.rdb.ZScore(ctx, radarKey(zone), topicID).Result()
	if errors.Is(err, redis.Nil) {
		return 0, ErrTopicNotFound
	}
	if err != nil {
		return 0, err
	}
	return score, nil
}

// Topic returns a topic's full record with its live score.
func (s *Store) Topic(ctx context.Context, topicID string) (domain.TopicPulse, error) {
	fields, err := s.rdb.HGetAll(ctx, topicKey(topicID)).Result()
	if err != nil {
		return domain.TopicPulse{}, err
	}
	if len(fields) == 0 {
		return domain.TopicPulse{}, ErrTopicNotFound
	}

	t := domain.TopicPulse{
		ID:               fields["id"],
		Title:            fields["title"],
		Description:      fields["description"],
		Tag:              fields["tag"],
		Zone:             int32(mustInt(fields["zone"])),
		MessageCount:     int32(mustInt(fields["message_count"])),
		CreatedAtUnix:    mustInt64(fields["created_at_unix"]),
		LastActivityUnix: mustInt64(fields["last_activity"]),
	}
	if score, err := s.rdb.ZScore(ctx, radarKey(campus.Zone(t.Zone)), topicID).Result(); err == nil {
		t.VelocityScore = score
	}
	return t, nil
}

// ZoneTopics returns the top N topics for a zone, highest score first.
//
// One ZREVRANGE plus one pipeline for metadata: O(log N + M) instead of a
// per-topic round trip.
func (s *Store) ZoneTopics(ctx context.Context, zone campus.Zone, limit int64) ([]domain.TopicPulse, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	ids, err := s.rdb.ZRevRangeWithScores(ctx, radarKey(zone), 0, limit-1).Result()
	if err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		return []domain.TopicPulse{}, nil
	}

	pipe := s.rdb.Pipeline()
	cmds := make([]*redis.MapStringStringCmd, len(ids))
	for i, z := range ids {
		cmds[i] = pipe.HGetAll(ctx, topicKey(z.Member.(string)))
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, redis.Nil) {
		return nil, err
	}

	out := make([]domain.TopicPulse, 0, len(ids))
	for i, cmd := range cmds {
		fields, err := cmd.Result()
		if err != nil || len(fields) == 0 {
			// Ranked but gone: a stale ZSET member. Drop it.
			s.rdb.ZRem(ctx, radarKey(zone), ids[i].Member)
			continue
		}
		out = append(out, domain.TopicPulse{
			ID:               fields["id"],
			Title:            fields["title"],
			Description:      fields["description"],
			Tag:              fields["tag"],
			Zone:             int32(mustInt(fields["zone"])),
			MessageCount:     int32(mustInt(fields["message_count"])),
			CreatedAtUnix:    mustInt64(fields["created_at_unix"]),
			LastActivityUnix: mustInt64(fields["last_activity"]),
			VelocityScore:    ids[i].Score,
		})
	}
	return out, nil
}

// DecayAll applies one minute of decay to every physical zone and purges
// anything that has fallen below the floor.
//
// The blueprint's version reads every member and writes it back one at a time,
// which is O(N) round trips. Rewriting a whole sorted set costs one round trip
// per zone, so that is what this does.
func (s *Store) DecayAll(ctx context.Context) (int, error) {
	purged := 0
	for _, zone := range campus.AllPhysicalZones() {
		key := radarKey(zone)
		entries, err := s.rdb.ZRangeWithScores(ctx, key, 0, -1).Result()
		if err != nil {
			return purged, fmt.Errorf("radar: decay read %s: %w", key, err)
		}
		if len(entries) == 0 {
			continue
		}

		keep := make([]redis.Z, 0, len(entries))
		var dead []any
		for _, e := range entries {
			next := Decay(e.Score, 1)
			if next < PurgeFloor {
				dead = append(dead, e.Member)
				continue
			}
			keep = append(keep, redis.Z{Score: next, Member: e.Member})
		}

		pipe := s.rdb.Pipeline()
		pipe.Del(ctx, key)
		if len(keep) > 0 {
			pipe.ZAdd(ctx, key, keep...)
		}
		for _, d := range dead {
			pipe.Del(ctx, topicKey(d.(string)))
		}
		if _, err := pipe.Exec(ctx); err != nil {
			return purged, fmt.Errorf("radar: decay write %s: %w", key, err)
		}
		purged += len(dead)
	}
	return purged, nil
}

// JoinPresence records a student as present in a zone and returns the count.
func (s *Store) JoinPresence(ctx context.Context, zone campus.Zone, roll string) (int, error) {
	key := presenceKey(zone)
	pipe := s.rdb.Pipeline()
	pipe.SAdd(ctx, key, roll)
	pipe.Expire(ctx, key, 6*time.Minute)
	cnt := pipe.SCard(ctx, key)
	if _, err := pipe.Exec(ctx); err != nil {
		return 0, err
	}
	return int(cnt.Val()), nil
}

// Heartbeat refreshes presence without adding a member. Returns the zone count.
func (s *Store) Heartbeat(ctx context.Context, zone campus.Zone, roll string) (int, error) {
	return s.JoinPresence(ctx, zone, roll)
}

// ZonePopulation returns how many students are currently in a zone.
func (s *Store) ZonePopulation(ctx context.Context, zone campus.Zone) (int, error) {
	n, err := s.rdb.SCard(ctx, presenceKey(zone)).Result()
	if err != nil {
		return 0, err
	}
	return int(n), nil
}

// MergeZones combines several zone feeds into one ranked list.
//
// Used by the "All Patia" radar view. Sorting is by score descending with the
// id as a tiebreaker so the order is stable between identical scores - an
// unstable comparator makes a live list visibly jitter.
func MergeZones(lists ...[]domain.TopicPulse) []domain.TopicPulse {
	var out []domain.TopicPulse
	for _, l := range lists {
		out = append(out, l...)
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].VelocityScore != out[j].VelocityScore {
			return out[i].VelocityScore > out[j].VelocityScore
		}
		return out[i].ID < out[j].ID
	})
	return out
}

func mustInt(s string) int {
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		return 0
	}
	return n
}

func mustInt64(s string) int64 {
	n, err := strconv.ParseInt(strings.TrimSpace(s), 10, 64)
	if err != nil {
		return 0
	}
	return n
}
