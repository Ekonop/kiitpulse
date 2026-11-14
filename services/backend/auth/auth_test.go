package auth

import (
	"testing"
	"time"

	"github.com/kiitpulse/backend/domain"
)

func TestStudentFromEmail(t *testing.T) {
	cases := []struct {
		name      string
		email     string
		wantRoll  string
		wantErr   bool
		wantTag   string
	}{
		{"valid roll", "241551058@kiit.ac.in", "241551058", false, "CSE-AIML '28"},
		{"uppercase", "241551058@KIIT.AC.IN", "241551058", false, "CSE-AIML '28"},
		{"whitespace", "  241551058@kiit.ac.in  ", "241551058", false, "CSE-AIML '28"},
		{"other domain", "student@gmail.com", "", true, ""},
		{"lookalike domain", "241551058@kiit.ac.in.evil.com", "", true, ""},
		{"name not roll", "vansh@kiit.ac.in", "", true, ""},
		{"short roll", "12345@kiit.ac.in", "", true, ""},
		{"empty", "", "", true, ""},
		{"domain only", "@kiit.ac.in", "", true, ""},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := StudentFromEmail(tc.email)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("expected error for %q, got student %+v", tc.email, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got.RollNumber != tc.wantRoll {
				t.Errorf("roll = %q, want %q", got.RollNumber, tc.wantRoll)
			}
			if got.BranchTag != tc.wantTag {
				t.Errorf("branch = %q, want %q", got.BranchTag, tc.wantTag)
			}
		})
	}
}

func TestServiceIssueAndVerify(t *testing.T) {
	svc, err := NewService("0123456789abcdef0123456789abcdef", time.Hour)
	if err != nil {
		t.Fatalf("NewService: %v", err)
	}

	student := domain.Student{
		Email:      "241551058@kiit.ac.in",
		RollNumber: "241551058",
		BranchTag:  "CSE-AIML '28",
	}
	token, expiresIn, err := svc.Issue(student)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	if expiresIn <= 0 {
		t.Errorf("expiresIn = %d, want > 0", expiresIn)
	}

	got, err := svc.Verify(token)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if got.RollNumber != student.RollNumber {
		t.Errorf("roll = %q, want %q", got.RollNumber, student.RollNumber)
	}
}

func TestServiceRejectsShortSecret(t *testing.T) {
	if _, err := NewService("tooshort", time.Hour); err == nil {
		t.Fatal("expected an error for a short HMAC secret")
	}
}

func TestVerifyRejectsExpiredAndForged(t *testing.T) {
	svc, _ := NewService("0123456789abcdef0123456789abcdef", time.Hour)

	// Signed by a different key.
	other, _ := NewService("ffffffffffffffffffffffffffffffff", time.Hour)
	forged, _, _ := other.Issue(domain.Student{RollNumber: "241551058"})

	if _, err := svc.Verify(forged); err == nil {
		t.Fatal("a token signed with another key must not verify")
	}

	// Expired token.
	shortLived, _ := NewService("0123456789abcdef0123456789abcdef", time.Nanosecond)
	expired, _, _ := shortLived.Issue(domain.Student{RollNumber: "241551058"})
	time.Sleep(5 * time.Millisecond)
	if _, err := svc.Verify(expired); err == nil {
		t.Fatal("an expired token must not verify")
	}

	if _, err := svc.Verify("not-a-jwt"); err == nil {
		t.Fatal("garbage must not verify")
	}
}

// TestBranchTagMatchesClient pins the roll-prefix mapping. If a new batch
// prefix is added to the Flutter AuthController, it must be added here too.
func TestBranchTagMatchesClient(t *testing.T) {
	cases := map[string]string{
		"241551058": "CSE-AIML '28",
		"241560001": "IT '28",
		"240501234": "CSE '28",
		"240601234": "IT '28",
		"230501234": "CSE '27",
		"230601234": "IT '27",
		"220512345": "Senior",
		"999999999": "KIIT Student",
	}
	for roll, want := range cases {
		if got := BranchTagFor(roll); got != want {
			t.Errorf("BranchTagFor(%q) = %q, want %q", roll, got, want)
		}
	}
}
