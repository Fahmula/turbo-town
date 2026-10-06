class_name VehicleSoundProfile
extends Resource
## What one class of vehicle sounds like (assets/audio/profiles/<id>.tres),
## played by VehicleAudio. Sounds every vehicle shares (tyres, wind, crashes,
## glass...) live in VehicleSoundBank instead.
##
## The engine is a set of steady loops, each recorded (or rendered) at a known
## rpm, on load (throttle) and off load (coasting). VehicleAudio plays the two
## loops either side of the current rpm, pitched to match it and crossfaded
## with equal power, and blends the on- and off-load sets by engine load. See
## ASSET_MANIFEST.md for where every file comes from.

@export_group("Engine")
## Steady on-load (throttle) loops, lowest rpm first.
@export var engine_on: Array[AudioStream] = []
## The rpm each `engine_on` loop was recorded at.
@export var engine_on_rpm: PackedFloat32Array = []
## Steady off-load (coasting, engine braking) loops, lowest rpm first.
@export var engine_off: Array[AudioStream] = []
@export var engine_off_rpm: PackedFloat32Array = []
## The vehicle's rpm is multiplied by this before picking and pitching loops,
## so one recording set can serve engines with other rev ranges.
@export var rpm_scale := 1.0
@export var engine_volume_db := 0.0
## Extra loudness (dB) at the redline compared with idle, and on load
## compared with coasting.
@export var rpm_gain_db := 7.0
@export var load_gain_db := 4.0
## Starter + catch, played when the vehicle appears; the loops fade in
## `startup_catch` seconds in.
@export var startup: AudioStream
@export var startup_catch := 0.7

@export_group("Character")
## A plane's propeller (a loop at `propeller_rpm`): pitched with the engine,
## louder with revs and power.
@export var propeller: AudioStream
@export var propeller_rpm := 2400.0
@export var propeller_volume_db := -4.0
## Turbo or supercharger whine (a loop at `whine_rpm`), rising with revs and
## load.
@export var whine: AudioStream
@export var whine_rpm := 6000.0
@export var whine_volume_db := -14.0
## Turbo blow-off when lifting off after hard throttle.
@export var blowoff: AudioStream
## Exhaust crackle on lift-off from high revs.
@export var pops: Array[AudioStream] = []
@export var pops_volume_db := -8.0
## Gear change clunk / air release.
@export var shift: AudioStream
@export var shift_volume_db := -14.0
## Air brakes hiss when a heavy vehicle comes to a stop.
@export var air_brake: AudioStream
## Beeps while reversing (trucks, buses).
@export var reverse_beeper := false

@export_group("Horn")
## A loop; plays while the horn is held (traffic honks briefly).
@export var horn: AudioStream
@export var horn_volume_db := 0.0
@export var horn_pitch := 1.0

@export_group("Body")
## Heavier vehicles' crashes and thumps sound lower and bigger (1 = a
## 1.3 t car).
@export var size := 1.0
