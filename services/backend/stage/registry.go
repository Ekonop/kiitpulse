// Package stage tracks who may speak on which topic stage.
//
// This is the role machine's server side. The client can move itself from
// listener to hand-raised, because raising a hand is a request. It cannot move
// itself to speaker: that transition exists only here, behind a server check.
//
// State is in memory. A stage is a live session measured in minutes, so
// persisting it would mean faithfully restoring ghost speakers after a restart -
// worse than starting empty.
package stage

import "sync"

// Registry holds speaker grants keyed by topic.
type Registry struct {
	mu    sync.RWMutex
	topic map[string]map[string]struct{}

	// maxSpeakers bounds a stage. Past a handful of open mics a huddle stops
	// being a conversation, and the SFU uplink cost grows with every speaker.
	MaxSpeakers int
}

// New builds an empty registry.
func New() *Registry {
	return &Registry{
		topic:       make(map[string]map[string]struct{}),
		MaxSpeakers: 8,
	}
}

// GrantSpeaker marks a student as allowed to publish on a topic.
func (r *Registry) GrantSpeaker(topicID, roll string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.topic[topicID] == nil {
		r.topic[topicID] = make(map[string]struct{})
	}
	if len(r.topic[topicID]) >= r.MaxSpeakers {
		// Full: refuse rather than silently dropping someone else's slot.
		return
	}
	r.topic[topicID][roll] = struct{}{}
}

// RevokeSpeaker removes a speaker slot.
func (r *Registry) RevokeSpeaker(topicID, roll string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if set, ok := r.topic[topicID]; ok {
		delete(set, roll)
		if len(set) == 0 {
			delete(r.topic, topicID)
		}
	}
}

// IsSpeaker reports whether a student may publish on a topic.
func (r *Registry) IsSpeaker(topicID, roll string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	_, ok := r.topic[topicID][roll]
	return ok
}

// Speakers lists the rolls currently allowed to publish.
func (r *Registry) Speakers(topicID string) []string {
	r.mu.RLock()
	defer r.mu.RUnlock()
	set := r.topic[topicID]
	out := make([]string, 0, len(set))
	for roll := range set {
		out = append(out, roll)
	}
	return out
}
