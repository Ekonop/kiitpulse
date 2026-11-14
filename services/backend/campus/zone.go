// Package campus holds the KIIT Patia geofences and zone resolution.
//
// The fences are the same axis-aligned boxes the Dart client uses
// (packages/kiit_contracts/lib/src/campus_zone.dart). They are duplicated on
// purpose: the client needs a fast local answer to render the header before a
// round-trip, and the server needs the authoritative answer for zone
// assignment and velocity bucketing. `campus_test.go` pins them together with
// known coordinates so the two can never silently drift.
package campus

import "strings"

// Zone is a physical KIIT campus area. Values match the Dart enum wire order.
type Zone int

const (
	ZoneUnspecified Zone = 0
	ZoneCampus15    Zone = 1
	ZoneKSAC        Zone = 2
	ZoneKPHostels   Zone = 3
	ZoneFoodCourt   Zone = 4
	ZoneCampus67    Zone = 5
	ZoneKIMS        Zone = 6
	ZoneOffCampus   Zone = 7
)

// Key is the stable string used in Redis keys, Postgres columns and URLs.
func (z Zone) Key() string {
	switch z {
	case ZoneCampus15:
		return "campus15"
	case ZoneKSAC:
		return "ksac"
	case ZoneKPHostels:
		return "kp_hostels"
	case ZoneFoodCourt:
		return "food_court"
	case ZoneCampus67:
		return "campus6_7"
	case ZoneKIMS:
		return "kims"
	default:
		return "off_campus"
	}
}

// Label is the short human name shown in the UI.
func (z Zone) Label() string {
	switch z {
	case ZoneCampus15:
		return "Campus 15"
	case ZoneKSAC:
		return "KSAC"
	case ZoneKPHostels:
		return "KP / QC Hostels"
	case ZoneFoodCourt:
		return "Food Court"
	case ZoneCampus67:
		return "Campus 6 & 7"
	case ZoneKIMS:
		return "KIMS"
	default:
		return "Off-Campus"
	}
}

// Valid reports whether the zone is a real place a student can stand in.
func (z Zone) Valid() bool { return z >= ZoneCampus15 && z <= ZoneKIMS }

// ParseZone maps a URL/key segment to a Zone.
func ParseZone(s string) Zone {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "campus15":
		return ZoneCampus15
	case "ksac":
		return ZoneKSAC
	case "kp_hostels", "kphostels":
		return ZoneKPHostels
	case "food_court", "foodcourt":
		return ZoneFoodCourt
	case "campus6_7", "campus6and7", "campus67":
		return ZoneCampus67
	case "kims":
		return ZoneKIMS
	default:
		return ZoneOffCampus
	}
}

// Fence is an inclusive lat/lng bounding box in WGS84.
type Fence struct {
	Zone                           Zone
	MinLat, MaxLat, MinLng, MaxLng float64
}

// Contains reports whether the coordinate lies inside the fence.
func (f Fence) Contains(lat, lng float64) bool {
	return lat >= f.MinLat && lat <= f.MaxLat && lng >= f.MinLng && lng <= f.MaxLng
}

// Fences is ordered: Resolve returns the first match, which is the same order
// the client checks. Changing this order changes behaviour on the overlap
// between Campus 15 and KP Hostels.
var Fences = []Fence{
	{ZoneCampus15, 20.3530, 20.3560, 85.8170, 85.8210},
	{ZoneKSAC, 20.3510, 20.3540, 85.8130, 85.8170},
	{ZoneKPHostels, 20.3560, 20.3610, 85.8150, 85.8220},
	{ZoneFoodCourt, 20.3500, 20.3525, 85.8180, 85.8230},
	{ZoneCampus67, 20.3540, 20.3600, 85.8100, 85.8150},
	{ZoneKIMS, 20.3450, 20.3500, 85.8100, 85.8200},
}

// Resolve maps a coordinate to its KIIT zone, or ZoneOffCampus.
func Resolve(lat, lng float64) Zone {
	for _, f := range Fences {
		if f.Contains(lat, lng) {
			return f.Zone
		}
	}
	return ZoneOffCampus
}

// AllPhysicalZones is what the radar fans out over.
func AllPhysicalZones() []Zone {
	return []Zone{ZoneCampus15, ZoneKSAC, ZoneKPHostels, ZoneFoodCourt, ZoneCampus67, ZoneKIMS}
}

// GeofenceFor returns the fence for a zone. The zero Fence is returned for
// ZoneOffCampus, which by definition has no box.
func GeofenceFor(z Zone) Fence {
	for _, f := range Fences {
		if f.Zone == z {
			return f
		}
	}
	return Fence{Zone: ZoneOffCampus}
}

// Overlaps reports whether two boxes share any area.
func (f Fence) Overlaps(other Fence) bool {
	return f.MinLat < other.MaxLat && other.MinLat < f.MaxLat &&
		f.MinLng < other.MaxLng && other.MinLng < f.MaxLng
}
