class_name HeliCamera
extends FlightCamera
## The camera for flying a helicopter (the "heli" rig): behind and above it
## along the way its nose points on the map. Unlike the plane's camera it
## doesn't pitch with the helicopter (a helicopter leans forward to fly, and
## the view would point at the ground) and only leans a little with its bank,
## so the horizon stays put; flips and rolls happen in front of the camera.
## Everything else (look around, look back, chase / far / cockpit, ground and
## wall collision, shake) is FlightCamera's.


func _init() -> void:
	distance = 12.5
	height = 3.4
	look_ahead = 3.0
	follow = 3.0
	bank_follow = 0.15
	fov_full_speed = 60.0


## Level, along the helicopter's heading, leaning a little with its bank.
func _frame(b: Basis) -> Basis:
	var h := target as Helicopter
	var yaw := h.heading if h else atan2(b.z.x, b.z.z)
	var frame := Basis(Vector3.UP, yaw)
	if h and h.trick_left <= 0.0 and absf(h.bank) < PI * 0.5:
		frame = frame * Basis(Vector3.FORWARD, h.bank * bank_follow)
	return frame
