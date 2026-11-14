package campus

import "testing"

// TestGeofencesMatchClient pins every box to the coordinates in the Flutter
// package (packages/kiit_contracts/lib/src/campus_zone.dart).
//
// These two copies are deliberate: the client needs the boxes to render
// instantly and to work offline, the server needs them to be authoritative. The
// test is what keeps them from drifting.
func TestGeofencesMatchClient(t *testing.T) {
	type box struct {
		minLat, maxLat, minLng, maxLng float64
	}
	want := map[Zone]box{
		ZoneCampus15:  {20.3530, 20.3560, 85.8170, 85.8210},
		ZoneKSAC:      {20.3510, 20.3540, 85.8130, 85.8170},
		ZoneKPHostels: {20.3560, 20.3610, 85.8150, 85.8220},
		ZoneFoodCourt: {20.3500, 20.3525, 85.8180, 85.8230},
		ZoneCampus67:  {20.3540, 20.3600, 85.8100, 85.8150},
		ZoneKIMS:      {20.3450, 20.3500, 85.8100, 85.8200},
	}

	for zone, w := range want {
		g := GeofenceFor(zone)
		if g.MinLat != w.minLat || g.MaxLat != w.maxLat ||
			g.MinLng != w.minLng || g.MaxLng != w.maxLng {
			t.Errorf("%s: got [%v..%v] x [%v..%v], want [%v..%v] x [%v..%v]",
				zone.Key(),
				g.MinLat, g.MaxLat, g.MinLng, g.MaxLng,
				w.minLat, w.maxLat, w.minLng, w.maxLng)
		}
	}
}

// TestKnownCampusPoints checks that real places resolve to the zone a student
// would name if you asked them where they were standing.
func TestKnownCampusPoints(t *testing.T) {
	cases := []struct {
		name string
		lat  float64
		lng  float64
		want Zone
	}{
		{"Campus 15 library", 20.35475, 85.81900, ZoneCampus15},
		{"Campus 15 canteen", 20.35550, 85.81850, ZoneCampus15},
		{"KP hostel block", 20.35800, 85.81700, ZoneKPHostels},
		{"Off campus (Patia bazaar)", 20.34000, 85.83000, ZoneOffCampus},
		{"Far away (Bhubaneswar centre)", 20.2960, 85.8245, ZoneOffCampus},
		{"Canteen & 0,0", 0, 0, ZoneOffCampus},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Resolve(tc.lat, tc.lng); got != tc.want {
				t.Errorf("Resolve(%v,%v) = %s, want %s",
					tc.lat, tc.lng, got.Key(), tc.want.Key())
			}
		})
	}
}

func TestParseZoneRoundTrip(t *testing.T) {
	for _, zone := range AllPhysicalZones() {
		if got := ParseZone(zone.Key()); got != zone {
			t.Errorf("ParseZone(%q) = %s", zone.Key(), got.Key())
		}
	}
	if got := ParseZone("atlantis"); got != ZoneOffCampus {
		t.Errorf("unknown zone should be offCampus, got %s", got.Key())
	}
}

func TestZoneValidity(t *testing.T) {
	if !ZoneCampus15.Valid() {
		t.Error("Campus15 should be valid")
	}
	if ZoneOffCampus.Valid() {
		t.Error("OffCampus is not a chat-able zone")
	}
}

// TestGeofencesDoNotOverlap guards the resolve order: if two boxes overlap,
// whichever is checked first silently swallows the other.
func TestGeofencesDoNotOverlap(t *testing.T) {
	zones := AllPhysicalZones()
	for i := 0; i < len(zones); i++ {
		for j := i + 1; j < len(zones); j++ {
			a, b := GeofenceFor(zones[i]), GeofenceFor(zones[j])
			if a.Overlaps(b) {
				t.Errorf("%s and %s overlap; resolve() order would hide one",
					zones[i].Key(), zones[j].Key())
			}
		}
	}
}

// TestZoneKeysMatchClient pins the wire keys to the Dart CampusZone.key values
// in packages/kiit_contracts. A drift here means every radar request for that
// zone silently 400s, which is exactly what happened with campus6and7.
func TestZoneKeysMatchClient(t *testing.T) {
	want := map[Zone]string{
		ZoneCampus15:  "campus15",
		ZoneKSAC:      "ksac",
		ZoneKPHostels: "kp_hostels",
		ZoneFoodCourt: "food_court",
		ZoneCampus67:  "campus6_7",
		ZoneKIMS:      "kims",
		ZoneOffCampus: "off_campus",
	}
	for zone, key := range want {
		if got := zone.Key(); got != key {
			t.Errorf("%d.Key() = %q, want %q (Dart CampusZone.key)", zone, got, key)
		}
	}
}

// TestParseZoneAcceptsLegacySpelling keeps old URLs and cached keys working.
func TestParseZoneAcceptsLegacySpelling(t *testing.T) {
	for _, s := range []string{"campus6_7", "campus6and7", "campus67"} {
		if got := ParseZone(s); got != ZoneCampus67 {
			t.Errorf("ParseZone(%q) = %s, want campus6_7", s, got.Key())
		}
	}
}
