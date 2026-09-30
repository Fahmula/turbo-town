# Changelog

Player-facing changes per stable release. `tools/release.sh X.Y.Z` uses the
`## [X.Y.Z]` section below as the GitHub Release notes, so write it for the
player (what's new, what's fixed), not as a commit log.

Before releasing: rename `[Unreleased]` to the new version, add the date,
commit, push, then run the release script. Start a fresh `[Unreleased]` after.

## [Unreleased]

First stable release (planned as 0.2.0). Everything below is what the game
contains so far.

### Driving
- Sports car with raycast suspension, a slip-based tire model, 5-speed automatic
  gearbox, handbrake slides, jumps, landings and rollovers.
- Kid-friendly assists (traction and stability control, mid-air leveling);
  press T for drift mode without them.
- Chase, far and hood cameras, look back, mouse and right-stick look-around.
- Full keyboard and gamepad controls (Steam Deck controls work as a gamepad).

### World
- Island with a city (16 blocks, parks, plaza, parking lots), a 3-lane ring
  highway with overpasses, a mountain road with a big jump, dirt fields, a beach
  and a stunt park with a 14 m mega ramp, half pipes and gap jumps.
- Knock-over props: cones, barrels, crates, bowling pins, lamp posts, parked cars.
- Teleports (1-6 / Tab), respawn, and auto-respawn after falling in the sea.

### AI traffic
- About 22 AI cars that follow lanes, stop at working traffic lights, give way,
  crash, recover and honk at you if you block them. G toggles traffic.

### Presentation
- HUD with speedometer, gear, RPM, damage and air-time popups.
- Engine, tire, wind, crash and horn sounds; tire smoke, dust, skid marks,
  sparks and cosmetic crash dents.
