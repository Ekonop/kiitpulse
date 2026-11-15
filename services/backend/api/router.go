// Package api wires the services into a Gin router.
package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	"github.com/kiitpulse/backend/auth"
	"github.com/kiitpulse/backend/campus"
	"github.com/kiitpulse/backend/chat"
	"github.com/kiitpulse/backend/domain"
	"github.com/kiitpulse/backend/passport"
	"github.com/kiitpulse/backend/radar"
	"github.com/kiitpulse/backend/stage"
	"github.com/kiitpulse/backend/voice"
)

// CtxStudent is the Gin context key holding the authenticated student.
const CtxStudent = "pulse.student"

// Deps are everything the router needs.
type Deps struct {
	Log   *slog.Logger
	Auth  *auth.Service
	Radar *radar.Store
	Hub   *chat.Hub
	Redis *redis.Client
	// AllowOrigin is the single CORS origin allowed, or "*" for dev.
	AllowOrigin string
	// Voice is the LiveKit configuration. Zero value means voice is off.
	Voice voice.Config
	// Stage tracks speaker grants per topic.
	Stage *stage.Registry
	// Passport awards badges from observed activity.
	Passport *passport.Tracker
}

// NewRouter builds the HTTP surface.
//
// Route layout follows what the Flutter client's LiveGateway expects. Every
// authenticated route sits behind RequireSession, which is the only place a
// token is read.
func NewRouter(d Deps) *gin.Engine {
	if d.Log == nil {
		d.Log = slog.Default()
	}
	gin.SetMode(gin.ReleaseMode)

	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(requestLogger(d.Log))
	r.Use(cors(d.AllowOrigin))

	r.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"sockets": d.Hub.ClientCount(),
		})
	})

	// ---- auth ----------------------------------------------------------
	r.GET("/ws/topics/:topicID", webSocketRoute(d))

	r.POST("/auth/signin", func(c *gin.Context) {
		var body struct {
			Email string `json:"email"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "expected {\"email\":\"...\"}"})
			return
		}

		student, err := auth.StudentFromEmail(body.Email)
		if err != nil {
			switch {
			case errors.Is(err, auth.ErrNotCampus):
				c.JSON(http.StatusForbidden, gin.H{
					"error": "only verified @kiit.ac.in student accounts are permitted",
					"code":  "KIIT_DOMAIN_REQUIRED",
				})
			case errors.Is(err, auth.ErrInvalidRoll):
				c.JSON(http.StatusForbidden, gin.H{
					"error": "use your roll number as the email local part, e.g. 241551058@kiit.ac.in",
					"code":  "KIIT_ROLL_INVALID",
				})
			default:
				c.JSON(http.StatusInternalServerError, gin.H{"error": "sign-in failed"})
			}
			return
		}

		token, expiresIn, err := d.Auth.Issue(student)
		if err != nil {
			d.Log.Error("auth: issue token", "err", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not issue session"})
			return
		}
		c.JSON(http.StatusOK, gin.H{
			"email":       student.Email,
			"roll_number": student.RollNumber,
			"branch_tag":  student.BranchTag,
			"token":       token,
			"expires_in":  expiresIn,
		})
	})

	// ---- authenticated -------------------------------------------------
	authed := r.Group("/", requireSession(d))

	authed.GET("/radar/zones/:zone", func(c *gin.Context) {
		zone := campus.ParseZone(c.Param("zone"))
		if !zone.Valid() {
			c.JSON(http.StatusBadRequest, gin.H{"error": "unknown campus zone"})
			return
		}
		limit := int64(50)
		topics, err := d.Radar.ZoneTopics(c.Request.Context(), zone, limit)
		if err != nil {
			d.Log.Error("radar: zone topics", "zone", zone.Key(), "err", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "radar unavailable"})
			return
		}
		c.JSON(http.StatusOK, topics)
	})

	authed.GET("/radar/zones/:zone/population", func(c *gin.Context) {
		zone := campus.ParseZone(c.Param("zone"))
		count, err := d.Radar.ZonePopulation(c.Request.Context(), zone)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "population unavailable"})
			return
		}
		c.JSON(http.StatusOK, gin.H{"zone": zone.Key(), "count": count})
	})

	authed.POST("/radar/topics", func(c *gin.Context) {
		var body struct {
			Title       string `json:"title"`
			Description string `json:"description"`
			CampusZone  string `json:"campus_zone"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid topic body"})
			return
		}
		title := strings.TrimSpace(body.Title)
		desc := strings.TrimSpace(body.Description)
		if title == "" || desc == "" || len(title) > 48 || len(desc) > 180 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "title (1-48) and description (1-180) are required",
			})
			return
		}
		zone := campus.ParseZone(body.CampusZone)
		if !zone.Valid() {
			c.JSON(http.StatusBadRequest, gin.H{"error": "unknown campus zone"})
			return
		}

		topic := domain.TopicPulse{
			ID:            newID("t"),
			Title:         title,
			Description:   desc,
			Zone:          int32(zone),
			MessageCount:  1,
			CreatedAtUnix: time.Now().Unix(),
		}
		created, err := d.Radar.CreateTopic(c.Request.Context(), topic)
		if err != nil {
			d.Log.Error("radar: create topic", "err", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "could not create topic"})
			return
		}
		// Credit the student who opened it, and note which zone they were in.
		if d.Passport != nil {
			roll := c.MustGet(CtxStudent).(domain.Student).RollNumber
			go func() {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				defer cancel()
				_ = d.Passport.RecordTopic(ctx, roll)
				_ = d.Passport.RecordZone(ctx, roll, campus.ParseZone(body.CampusZone).Key())
			}()
		}

		c.JSON(http.StatusCreated, created)
	})

	// ---- voice ---------------------------------------------------------
	authed.POST("/voice/token", func(c *gin.Context) {
		var body struct {
			TopicID   string `json:"topic_id"`
			AsSpeaker bool   `json:"as_speaker"`
		}
		if err := c.ShouldBindJSON(&body); err != nil || body.TopicID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "topic_id is required"})
			return
		}
		student := c.MustGet(CtxStudent).(domain.Student)

		// Publish rights are decided here, never by the client. `as_speaker` is
		// only a hint: it is ignored unless the server has already granted this
		// student a speaker slot for this topic.
		canPublish := d.Stage != nil && d.Stage.IsSpeaker(body.TopicID, student.RollNumber)
		if body.AsSpeaker && !canPublish {
			// Asking nicely does not grant it. Answer honestly rather than
			// silently degrading: the app shows "waiting for the stage".
			c.JSON(http.StatusForbidden, gin.H{
				"error": "you are not speaking on this stage yet",
				"code":  "SPEAKER_NOT_GRANTED",
			})
			return
		}

		token, room, err := voice.Mint(d.Voice, voice.TokenRequest{
			TopicID:    body.TopicID,
			Roll:       student.RollNumber,
			CanPublish: canPublish,
		})
		if errors.Is(err, voice.ErrNotConfigured) {
			c.JSON(http.StatusOK, gin.H{
				"token":   "",
				"ws_url":  "",
				"room":    voice.RoomName(body.TopicID),
				"publish": false,
				"note":    "voice is not configured on this deployment",
			})
			return
		}
		if err != nil {
			d.Log.Error("voice: mint token", "err", err)
			c.JSON(http.StatusInternalServerError, gin.H{"error": "could not mint a voice token"})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"token":   token,
			"ws_url":  d.Voice.URL,
			"room":    room,
			"publish": canPublish,
		})
	})

	// Granting a speaker slot. In a full build this is moderator-only; the
	// gate is here so the boundary exists even before roles ship.
	authed.POST("/voice/stage/:topicID/speakers", func(c *gin.Context) {
		topicID := c.Param("topicID")
		var body struct {
			Roll string `json:"roll"`
		}
		if err := c.ShouldBindJSON(&body); err != nil || body.Roll == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "roll is required"})
			return
		}
		student := c.MustGet(CtxStudent).(domain.Student)

		// Only the requesting student can be promoted for now: promoting others
		// needs the moderator role, which does not exist yet. Refusing is better
		// than shipping a hole where any client can make anyone a speaker.
		if body.Roll != student.RollNumber {
			c.JSON(http.StatusForbidden, gin.H{
				"error": "promoting another student requires the moderator role",
				"code":  "MODERATOR_REQUIRED",
			})
			return
		}
		if d.Stage == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stage unavailable"})
			return
		}
		d.Stage.GrantSpeaker(topicID, body.Roll)
		c.JSON(http.StatusOK, gin.H{"topic_id": topicID, "roll": body.Roll, "speaker": true})
	})

	authed.POST("/voice/hand-raise", func(c *gin.Context) {
		var body struct {
			TopicID string `json:"topic_id"`
			Raised  bool   `json:"raised"`
		}
		if err := c.ShouldBindJSON(&body); err != nil || body.TopicID == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "topic_id is required"})
			return
		}
		if d.Stage == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stage unavailable"})
			return
		}
		student := c.MustGet(CtxStudent).(domain.Student)
		role := d.Stage.SetHand(body.TopicID, student.RollNumber, body.Raised)
		c.JSON(http.StatusOK, gin.H{
			"topic_id": body.TopicID,
			"raised":   role == domain.StageRoleHandRaised,
			"role":     role,
		})
	})

	// Joining a stage is what makes someone appear on the roster and what the
	// radar scores as a voice join. Without this the stage had no members and
	// the 3.5x voice weight in the velocity formula was never triggered.
	authed.POST("/voice/stage/:topicID/join", func(c *gin.Context) {
		topicID := c.Param("topicID")
		if d.Stage == nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "stage unavailable"})
			return
		}
		student := c.MustGet(CtxStudent).(domain.Student)
		d.Stage.Join(topicID, student.RollNumber)

		if d.Passport != nil {
			go func(roll string) {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				defer cancel()
				_ = d.Passport.RecordVoiceJoin(ctx, roll)
			}(student.RollNumber)
		}

		// Score the join. Fire-and-forget: a radar hiccup must not stop someone
		// entering a room.
		if topic, err := d.Radar.Topic(c.Request.Context(), topicID); err == nil {
			go func(zone campus.Zone) {
				ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
				defer cancel()
				_ = d.Radar.RecordEvent(ctx, zone, topicID, radar.EventVoiceJoin)
			}(campus.Zone(topic.Zone))
		}

		c.JSON(http.StatusOK, gin.H{
			"topic_id": topicID,
			"role":     d.Stage.Role(topicID, student.RollNumber),
			"members":  d.Stage.Members(topicID),
		})
	})

	authed.POST("/voice/stage/:topicID/leave", func(c *gin.Context) {
		topicID := c.Param("topicID")
		student := c.MustGet(CtxStudent).(domain.Student)
		if d.Stage != nil {
			d.Stage.Leave(topicID, student.RollNumber)
		}
		c.JSON(http.StatusOK, gin.H{"topic_id": topicID, "left": true})
	})

	authed.GET("/voice/stage/:topicID", func(c *gin.Context) {
		topicID := c.Param("topicID")
		var members []domain.StageMember
		if d.Stage != nil {
			members = d.Stage.Members(topicID)
		}
		if members == nil {
			members = []domain.StageMember{}
		}
		c.JSON(http.StatusOK, gin.H{
			"topic_id": topicID,
			"members":  members,
			"count":    len(members),
		})
	})

	// ---- reactions -----------------------------------------------------
	// Reactions feed the radar at 0.25 of a message each. They are counted, not
	// stored per-user: an ephemeral campus pulse does not need a permanent
	// record of who tapped fire on a 24-hour topic.
	authed.POST("/topics/:topicID/react", func(c *gin.Context) {
		topicID := c.Param("topicID")
		var body struct {
			Kind domain.ReactionKind `json:"kind"`
		}
		if err := c.ShouldBindJSON(&body); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid reaction body"})
			return
		}
		if !body.Kind.Valid() {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "kind must be one of fire, agree, ask",
				"code":  "UNKNOWN_REACTION",
			})
			return
		}

		topic, err := d.Radar.Topic(c.Request.Context(), topicID)
		if err != nil {
			c.JSON(http.StatusNotFound, gin.H{"error": "no such topic"})
			return
		}

		if err := d.Radar.RecordEvent(c.Request.Context(), campus.Zone(topic.Zone),
			topicID, radar.EventReaction); err != nil {
			d.Log.Error("record reaction", "topic", topicID, "err", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "could not record reaction"})
			return
		}

		c.JSON(http.StatusOK, gin.H{"topic_id": topicID, "kind": body.Kind})
	})

	// ---- chat history --------------------------------------------------
	authed.GET("/topics/:topicID/messages", func(c *gin.Context) {
		// History is a capped Redis list that expires with the topic, so an
		// ephemeral room really is ephemeral. Decoded here rather than passed
		// through raw so a corrupt entry is skipped instead of corrupting the
		// whole response.
		topicID := c.Param("topicID")
		limit := 50
		if q := c.Query("limit"); q != "" {
			if n, err := strconv.Atoi(q); err == nil && n > 0 && n <= 200 {
				limit = n
			}
		}
		messages, err := d.Radar.RecentMessages(c.Request.Context(), topicID, limit)
		if err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "history unavailable"})
			return
		}
		c.JSON(http.StatusOK, messages)
	})

	// ---- passport ------------------------------------------------------
	authed.GET("/passport/:roll", func(c *gin.Context) {
		student := c.MustGet(CtxStudent).(domain.Student)
		// A student may only read their own passport.
		if c.Param("roll") != student.RollNumber {
			c.JSON(http.StatusForbidden, gin.H{"error": "you can only read your own passport"})
			return
		}
		if d.Passport == nil {
			c.JSON(http.StatusOK, []any{})
			return
		}

		activity, err := d.Passport.Activity(c.Request.Context(), student.RollNumber)
		if err != nil {
			d.Log.Error("passport: read activity", "roll", student.RollNumber, "err", err)
			c.JSON(http.StatusServiceUnavailable, gin.H{"error": "could not read your passport"})
			return
		}

		badges := passport.Award(activity)
		passport.SortByIssued(badges)
		c.JSON(http.StatusOK, badges)
	})

	return r
}

// requireSession validates the bearer token and stores the student on the
// context. This is the only place a token is read.
func requireSession(d Deps) gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		const prefix = "Bearer "
		if !strings.HasPrefix(header, prefix) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "login required"})
			return
		}
		student, err := d.Auth.Verify(strings.TrimPrefix(header, prefix))
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{
				"error": "session expired or invalid",
				"code":  "UNAUTHENTICATED",
			})
			return
		}
		c.Set(CtxStudent, student)
		c.Next()
	}
}

func requestLogger(log *slog.Logger) gin.HandlerFunc {
	return func(c *gin.Context) {
		start := time.Now()
		c.Next()
		// Health checks would otherwise dominate the log.
		if c.Request.URL.Path == "/healthz" {
			return
		}
		log.Info("http",
			"method", c.Request.Method,
			"path", c.Request.URL.Path,
			"status", c.Writer.Status(),
			"ms", time.Since(start).Milliseconds(),
		)
	}
}

// cors allows the app origin. `*` is for local development only.
func cors(origin string) gin.HandlerFunc {
	if origin == "" {
		origin = "*"
	}
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", origin)
		c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
