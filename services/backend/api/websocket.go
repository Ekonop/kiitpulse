// Package api: WebSocket upgrade route.
package api

import (
	"context"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/gin-gonic/gin"

	"github.com/kiitpulse/backend/domain"
)

// webSocketRoute upgrades `/ws/topics/:topicID` and hands the connection to the
// hub.
//
// Browsers cannot set an Authorization header on a WebSocket handshake, so the
// token is also accepted as a query parameter. That is a real trade-off: query
// strings land in access logs. The mitigation is a short token lifetime and
// refusing to echo the parameter in logs (see requestLogger, which logs path
// only).
func webSocketRoute(d Deps) gin.HandlerFunc {
	return func(c *gin.Context) {
		topicID := c.Param("topicID")
		if topicID == "" {
			c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": "topic id required"})
			return
		}

		var student domain.Student
		if header := c.GetHeader("Authorization"); header != "" {
			s, err := d.Auth.Verify(trimBearer(header))
			if err != nil {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
				return
			}
			student = s
		} else if q := c.Query("access_token"); q != "" {
			s, err := d.Auth.Verify(q)
			if err != nil {
				c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid session"})
				return
			}
			student = s
		} else {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "login required"})
			return
		}

		conn, err := websocket.Accept(c.Writer, c.Request, &websocket.AcceptOptions{
			// The Flutter client is not a browser and sends no Origin; this is
			// safe *because* the session token is verified above, so an
			// attacker cannot join a room by forging an origin.
			InsecureSkipVerify: true,
			CompressionMode:    websocket.CompressionDisabled,
		})
		if err != nil {
			// Accept already wrote a response.
			return
		}
		conn.SetReadLimit(64 * 1024)

		// Handing the connection to the hub means this handler must not touch
		// the ResponseWriter afterwards.
		d.Hub.HandleSocket(conn, topicID, student)
		_ = conn.CloseNow()
	}
}

func trimBearer(header string) string {
	const prefix = "Bearer "
	if len(header) > len(prefix) && header[:len(prefix)] == prefix {
		return header[len(prefix):]
	}
	return header
}

// trackTopicLifetime keeps a room's message history alive only as long as the
// topic itself. Called from the hub's join hook, so it must not block the read
// loop - hence the goroutine with its own timeout.
func trackTopicLifetime(d Deps, topicID string) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		_ = d.Redis.Expire(ctx, "kiit:messages:"+topicID, 24*time.Hour).Err()
	}()
}
