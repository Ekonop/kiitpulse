package voice

import (
	"strings"
	"testing"

	"github.com/livekit/protocol/auth"
)

func testConfig() Config {
	return Config{
		URL:       "wss://voice.example.test",
		APIKey:    "test-key",
		APISecret: "test-secret-that-is-long-enough-to-sign",
	}
}

func TestMintListenerCannotPublish(t *testing.T) {
	token, room, err := Mint(testConfig(), TokenRequest{
		TopicID:    "t1",
		Roll:       "241551058",
		CanPublish: false,
	})
	if err != nil {
		t.Fatalf("Mint: %v", err)
	}
	if token == "" {
		t.Fatal("empty token")
	}
	if room != "kiit-huddle-t1" {
		t.Errorf("room = %q", room)
	}

	// Verify the signature and read the grant back. A listener must be
	// incapable at the SFU, not merely discouraged by the app.
	video := verifyToken(t, token)
	if video.CanPublish != nil && *video.CanPublish {
		t.Error("a listener token was granted publish rights")
	}
	if video.Room != "kiit-huddle-t1" {
		t.Errorf("grant room = %q", video.Room)
	}
}

func TestMintSpeakerCanPublish(t *testing.T) {
	token, _, err := Mint(testConfig(), TokenRequest{
		TopicID:    "t1",
		Roll:       "241551058",
		CanPublish: true,
	})
	if err != nil {
		t.Fatalf("Mint: %v", err)
	}
	video := verifyToken(t, token)
	if video.CanPublish == nil || !*video.CanPublish {
		t.Error("a speaker token carries no publish right")
	}
}

func TestMintRefusesWhenNotConfigured(t *testing.T) {
	_, _, err := Mint(Config{}, TokenRequest{TopicID: "t1", Roll: "241551058"})
	if err != ErrNotConfigured {
		t.Fatalf("err = %v, want ErrNotConfigured", err)
	}
}

func TestMintRefusesEmptyIdentity(t *testing.T) {
	for _, req := range []TokenRequest{
		{TopicID: "", Roll: "241551058"},
		{TopicID: "t1", Roll: ""},
	} {
		if _, _, err := Mint(testConfig(), req); err == nil {
			t.Errorf("accepted an incomplete request: %+v", req)
		}
	}
}

func TestTokenIsBoundToItsRoom(t *testing.T) {
	// A token for one topic must not be usable to join another.
	tokA, roomA, _ := Mint(testConfig(), TokenRequest{TopicID: "topic-a", Roll: "241551058"})
	tokB, roomB, _ := Mint(testConfig(), TokenRequest{TopicID: "topic-b", Roll: "241551058"})

	if roomA == roomB {
		t.Fatal("two topics produced the same room")
	}
	if tokA == tokB {
		t.Fatal("two topics produced the same token")
	}

	if verifyToken(t, tokA).Room == verifyToken(t, tokB).Room {
		t.Error("tokens are not scoped to their own room")
	}
}

func TestIdentityIsTheRollNumber(t *testing.T) {
	token, _, _ := Mint(testConfig(), TokenRequest{TopicID: "t1", Roll: "241551058"})
	v, err := auth.ParseAPIToken(token)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if !strings.Contains(v.Identity(), "241551058") {
		t.Errorf("identity = %q, want the roll number", v.Identity())
	}
}

// verifyToken checks the signature with the shared secret and returns the grant.
func verifyToken(t *testing.T, token string) *auth.VideoGrant {
	t.Helper()
	v, err := auth.ParseAPIToken(token)
	if err != nil {
		t.Fatalf("parse token: %v", err)
	}
	if v.APIKey() != testConfig().APIKey {
		t.Errorf("api key = %q, want %q", v.APIKey(), testConfig().APIKey)
	}
	_, grants, err := v.Verify(testConfig().APISecret)
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if grants.Video == nil {
		t.Fatal("token carries no video grant")
	}
	return grants.Video
}

// TestForgedTokenFailsVerification is the adversarial case: a token signed with
// the wrong secret must not verify, or anyone could mint themselves a speaker.
func TestForgedTokenFailsVerification(t *testing.T) {
	token, _, err := Mint(testConfig(), TokenRequest{
		TopicID: "t1", Roll: "999999999", CanPublish: true,
	})
	if err != nil {
		t.Fatalf("Mint: %v", err)
	}
	v, err := auth.ParseAPIToken(token)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if _, _, err := v.Verify("a-different-secret-entirely"); err == nil {
		t.Fatal("a token verified against the wrong secret; anyone could forge a speaker grant")
	}
}
