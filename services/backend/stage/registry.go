// Package stage tracks who is on which topic stage, and in what role.
//
// This is the role machine's server side. The client can move itself from
// listener to hand-raised, because raising a hand is a request. It cannot move
// itself to speaker: that transition exists only here, behind a server check.
//
// State is in memory. A stage is a live session measured in minutes, so
// persisting it would mean faithfully restoring ghost speakers after a
// restart - worse than starting empty.
package stage

import (
	"sort"
	"sync"

	"github.com/kiitpulse/backend/domain"
)

// Registry holds stage membership keyed by topic.
type Registry struct {
	mu    sync.RWMutex
	topic map[string]map[string]domain.StageRole

	// MaxSpeakers bounds a stage. Past a handful of open mics a huddle stops
	// being a conversation, and the SFU uplink cost grows with every speaker.
	MaxSpeakers int
}

// New builds an empty registry.
func New() *Registry {
	return &Registry{
		topic:       make(map[string]map[string]domain.StageRole),
		MaxSpeakers: 8,
	}
}

func (r *Registry) ensure(topicID string) map[string]domain.StageRole {
	if r.topic[topicID] == nil {
		r.topic[topicID] = make(map[string]domain.StageRole)
	}
	return r.topic[topicID]
}

func (r *Registry) cleanup(topicID string, m map[string]domain.StageRole) {
	if len(m) == 0 {
		delete(r.topic, topicID)
	}
}

// Join adds a student to a stage as a listener.
//
// Joining is idempotent: calling it twice must not demote a speaker back to
// listener, because a reconnect would otherwise silently revoke the mic.
func (r *Registry) Join(topicID, roll string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.ensure(topicID)
	if _, exists := m[roll]; !exists {
		m[roll] = domain.StageRoleListener
	}
}

// Leave removes a student from a stage entirely.
func (r *Registry) Leave(topicID, roll string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.topic[topicID]
	if m == nil {
		return
	}
	delete(m, roll)
	r.cleanup(topicID, m)
}

// SetHand records a raised or lowered hand.
//
// A speaker who lowers their hand keeps their mic - lowering a hand is not a
// demotion, and silently killing someone's audio mid-sentence would be worse
// than doing nothing. Only a listener can raise a hand.
func (r *Registry) SetHand(topicID, roll string, raised bool) domain.StageRole {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.ensure(topicID)
	current := m[roll]

	switch {
	case current == domain.StageRoleSpeaker || current == domain.StageRoleModerator:
		// Speakers and moderators do not need a hand in the air.
		m[roll] = current
	case raised:
		m[roll] = domain.StageRoleHandRaised
	default:
		m[roll] = domain.StageRoleListener
	}
	return m[roll]
}

// GrantSpeaker marks a student as allowed to publish on a topic.
//
// Refuses at the cap rather than dropping someone else's slot.
func (r *Registry) GrantSpeaker(topicID, roll string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.ensure(topicID)

	if existing := m[roll]; existing == domain.StageRoleSpeaker || existing == domain.StageRoleModerator {
		return true
	}
	if r.countSpeakers(m) >= r.MaxSpeakers {
		return false
	}
	m[roll] = domain.StageRoleSpeaker
	return true
}

// RevokeSpeaker removes a speaker slot, returning them to listener.
func (r *Registry) RevokeSpeaker(topicID, roll string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	m := r.topic[topicID]
	if m == nil {
		return
	}
	if m[roll] == domain.StageRoleSpeaker {
		m[roll] = domain.StageRoleListener
	}
	r.cleanup(topicID, m)
}

// IsSpeaker reports whether a student may publish on a topic.
func (r *Registry) IsSpeaker(topicID, roll string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	role := r.topic[topicID][roll]
	return role == domain.StageRoleSpeaker || role == domain.StageRoleModerator
}

// Role returns a student's current role on a topic.
func (r *Registry) Role(topicID, roll string) domain.StageRole {
	r.mu.RLock()
	defer r.mu.RUnlock()
	if role, ok := r.topic[topicID][roll]; ok {
		return role
	}
	return domain.StageRoleListener
}

// Members returns the roster, ordered so the response is stable: speakers
// first, then raised hands, then listeners, each group alphabetical.
//
// A map iteration would reshuffle the stage UI on every poll.
func (r *Registry) Members(topicID string) []domain.StageMember {
	r.mu.RLock()
	defer r.mu.RUnlock()

	m := r.topic[topicID]
	out := make([]domain.StageMember, 0, len(m))
	for roll, role := range m {
		out = append(out, domain.StageMember{Roll: roll, Role: role})
	}

	rank := func(role domain.StageRole) int {
		switch role {
		case domain.StageRoleModerator:
			return 0
		case domain.StageRoleSpeaker:
			return 1
		case domain.StageRoleHandRaised:
			return 2
		default:
			return 3
		}
	}
	sort.Slice(out, func(i, j int) bool {
		if ri, rj := rank(out[i].Role), rank(out[j].Role); ri != rj {
			return ri < rj
		}
		return out[i].Roll < out[j].Roll
	})
	return out
}

// Speakers lists the rolls currently allowed to publish.
func (r *Registry) Speakers(topicID string) []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	out := make([]string, 0)
	for roll, role := range r.topic[topicID] {
		if role == domain.StageRoleSpeaker || role == domain.StageRoleModerator {
			out = append(out, roll)
		}
	}
	sort.Strings(out)
	return out
}

// Size is the number of people on a stage.
func (r *Registry) Size(topicID string) int {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.topic[topicID])
}

func (r *Registry) countSpeakers(m map[string]domain.StageRole) int {
	n := 0
	for _, role := range m {
		if role == domain.StageRoleSpeaker || role == domain.StageRoleModerator {
			n++
		}
	}
	return n
}
