"""Writes assets/audio/profiles/<vehicle>.tres (VehicleSoundProfile) from
PROFILES: which engine set each vehicle uses and its character. Called by
build_audio.py after the sounds exist; edit here, not the .tres files.

Engine sets live in assets/audio/engine/<set>/on_<rpm>.wav and
off_<rpm>.wav (see recorded.py). `rpm_scale` maps the vehicle's own rev range
onto the set's recorded rpm (a bus at 1,800 rpm can use loops recorded at
2,000 rpm with a small pitch change).

`rpm_gain_db` / `load_gain_db` are how much quieter idle and coasting are
than full throttle at the redline; together ~5-7 dB (idle). Wider, and idle
and cruising vanish on small speakers like the Steam Deck's (owner,
2026-10-02). `engine_volume_db` 0 puts every engine at full throttle at the
same level, the loudest steady sound in the mix (ART_BIBLE.md §33).
"""
from pathlib import Path

PROFILES = {
    # 90s Japanese turbo coupe: a smooth straight six, turbo whistle, blow-off,
    # crackles on the overrun.
    "sports_car": dict(engine="i6", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=4.0, load_gain_db=3.0,
                       
                       whine="engine/turbo_whine.wav", whine_rpm=7000.0, whine_volume_db=-17.0,
                       blowoff="engine/blowoff.wav", pops=["engine/pop_%d.wav" % k for k in (1, 2, 3, 4)], pops_volume_db=-9.0,
                       shift="engine/shift.wav", shift_volume_db=-16.0,
                       horn="horn/car.wav", horn_volume_db=-7.0, size=1.0),
    # Family sedan: a quiet four.
    "sedan": dict(engine="four", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=4.5, load_gain_db=2.0,
                  
                  shift="engine/shift.wav", shift_volume_db=-20.0,
                  horn="horn/car.wav", horn_volume_db=-7.0, horn_pitch=1.06, size=1.05),
    # Passenger van: a busy small four.
    "van": dict(engine="suv4", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=4.0, load_gain_db=2.0,
                
                shift="engine/shift.wav", shift_volume_db=-20.0,
                horn="horn/car.wav", horn_volume_db=-7.0, horn_pitch=0.92, size=1.3),
    # Cab-over delivery truck: diesel, air brakes, reverse beeper.
    "box_truck": dict(engine="diesel", rpm_scale=0.55, engine_volume_db=0.0, rpm_gain_db=3.5, load_gain_db=2.0,
                      
                      whine="engine/turbo_whine.wav", whine_rpm=4500.0, whine_volume_db=-24.0,
                      shift="engine/shift.wav", shift_volume_db=-14.0, air_brake="brake/air_1.wav", reverse_beeper=True,
                      horn="horn/air.wav", horn_volume_db=-9.0, horn_pitch=1.12, size=2.4),
    # City bus: a big, low diesel.
    "bus": dict(engine="diesel", rpm_scale=0.6, engine_volume_db=0.0, rpm_gain_db=3.0, load_gain_db=2.0,
                
                whine="engine/turbo_whine.wav", whine_rpm=3500.0, whine_volume_db=-22.0,
                shift="engine/shift.wav", shift_volume_db=-14.0, air_brake="brake/air_1.wav", reverse_beeper=True,
                horn="horn/car.wav", horn_volume_db=-6.0, horn_pitch=0.78, size=4.0),
    # Full-size pickup: a truck V8.
    "pickup": dict(engine="v8_truck", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=3.5, load_gain_db=3.0,
                   
                   shift="engine/shift.wav", shift_volume_db=-17.0,
                   horn="horn/car.wav", horn_volume_db=-7.0, horn_pitch=0.86, size=1.4),
    # Sand rail: an air-cooled flat four, revvy and raspy, pops.
    "buggy": dict(engine="flat4", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=4.0, load_gain_db=3.0,
                  
                  pops=["engine/pop_%d.wav" % k for k in (1, 2, 3, 4)], pops_volume_db=-12.0,
                  shift="engine/shift.wav", shift_volume_db=-18.0,
                  horn="horn/car.wav", horn_volume_db=-9.0, horn_pitch=1.4, size=0.8),
    # Monster truck: a big-block hot-rod V8 with a supercharger whine.
    "monster_truck": dict(engine="v8_big", rpm_scale=1.0, engine_volume_db=0.0, rpm_gain_db=3.5, load_gain_db=3.0,
                          
                          whine="engine/supercharger_whine.wav", whine_rpm=5200.0, whine_volume_db=-18.0,
                          pops=["engine/pop_%d.wav" % k for k in (1, 2, 3, 4)], pops_volume_db=-8.0,
                          shift="engine/shift.wav", shift_volume_db=-14.0,
                          horn="horn/air_big.wav", horn_volume_db=-8.0, horn_pitch=1.15, size=2.6),
    # Light sport plane: an air-cooled flat four (aero engines are the same
    # family), a little quieter, with the propeller's buzz on top. No horn.
    "plane": dict(engine="flat4", rpm_scale=1.0, engine_volume_db=-2.0, rpm_gain_db=4.0, load_gain_db=2.5,
                  propeller="engine/propeller.wav", propeller_rpm=2400.0, propeller_volume_db=-4.0, size=1.3),
}

SCRIPT = "res://scripts/vehicle/audio/vehicle_sound_profile.gd"


def write_profiles(out_dir: Path, engine_sets: dict):
    """engine_sets: set name -> {"on": [(rpm, rel path)], "off": [(rpm, rel path)]}"""
    pdir = out_dir / "profiles"
    pdir.mkdir(parents=True, exist_ok=True)
    for vid, p in PROFILES.items():
        es = engine_sets[p["engine"]]
        ext = []

        def ref(rel):
            path = "res://assets/audio/" + rel
            for i, e in enumerate(ext):
                if e[1] == path:
                    return 'ExtResource("%d")' % (i + 2)
            ext.append(("AudioStream", path))
            return 'ExtResource("%d")' % (len(ext) + 1)

        lines = []
        on = [ref(r) for _, r in es["on"]]
        off = [ref(r) for _, r in es["off"]]
        lines.append("engine_on = Array[AudioStream]([%s])" % ", ".join(on))
        lines.append("engine_on_rpm = PackedFloat32Array(%s)" % ", ".join("%g" % r for r, _ in es["on"]))
        lines.append("engine_off = Array[AudioStream]([%s])" % ", ".join(off))
        lines.append("engine_off_rpm = PackedFloat32Array(%s)" % ", ".join("%g" % r for r, _ in es["off"]))
        for key in ("rpm_scale", "engine_volume_db", "rpm_gain_db", "load_gain_db", "startup_catch", "whine_rpm",
                    "whine_volume_db", "pops_volume_db", "shift_volume_db", "horn_volume_db", "horn_pitch", "size",
                    "propeller_rpm", "propeller_volume_db"):
            if key in p:
                lines.append("%s = %s" % (key, float(p[key])))
        lines.append("startup = %s" % ref("engine/%s/startup.wav" % p["engine"]))
        import recorded
        lines.append("startup_catch = %s" % recorded.handover(p["engine"]))
        for key in ("whine", "blowoff", "shift", "air_brake", "horn", "propeller"):
            if key in p:
                lines.append("%s = %s" % (key, ref(p[key])))
        if "pops" in p:
            lines.append("pops = Array[AudioStream]([%s])" % ", ".join(ref(r) for r in p["pops"]))
        if p.get("reverse_beeper"):
            lines.append("reverse_beeper = true")
        head = ['[gd_resource type="Resource" script_class="VehicleSoundProfile" format=3]', "",
                '[ext_resource type="Script" path="%s" id="1"]' % SCRIPT]
        for i, (typ, path) in enumerate(ext):
            head.append('[ext_resource type="%s" path="%s" id="%d"]' % (typ, path, i + 2))
        text = "\n".join(head) + "\n\n[resource]\nscript = ExtResource(\"1\")\n" + "\n".join(lines) + "\n"
        (pdir / ("%s.tres" % vid)).write_text(text)
        print("  profiles/%s.tres (engine %s)" % (vid, p["engine"]))
