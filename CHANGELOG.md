# Changelog

Player-facing changes per stable release. `tools/release.sh X.Y.Z` uses the
`## [X.Y.Z]` section below as the GitHub Release notes, so write it for the
player (what's new, what's fixed), not as a commit log.

Before releasing: rename `[Unreleased]` to the new version, add the date,
commit, push, then run the release script. Start a fresh `[Unreleased]` after.

## [Unreleased]

### Vehicles
- New garage: press V (D-pad down on a gamepad) to drive the sedan, van,
  delivery truck or city bus, and to pick a paint colour. The game remembers
  your choice next time.
- The camera pulls back for the truck and bus so you can see the road, and the
  hood camera sits on the roof of the tall vehicles.

### Stunts
- Score points for big air, flips, barrel rolls, spins, drifts and near misses
  with traffic. Chain tricks into combos for a multiplier, but land on your
  wheels: a wipeout or a big crash loses the combo.
- Air tricks: steer to spin; hold Space (A on a gamepad) and use W/S to flip or
  A/D to barrel roll. Let go and the car turns itself level to land.
- RECORDS page with your best combos, biggest air, longest drift and more.

### Traffic
- Highway traffic changes lanes: cars overtake slow trucks and buses and keep right.
- Honk (E / L3) behind a car and it pulls over or moves a lane over to let you pass.
- Park in a car's lane and it drives around you when the other lane is clear,
  instead of just waiting and honking.
- The highway has proper junctions with traffic lights where the east and west
  avenues cross it: cars get on and off in both directions or go straight across.
- Fixed: city traffic only ever turned right at intersections. Now cars go
  straight and turn left too.

### Menus
- New title screen with your car on show: Drive, Garage, Settings, Controls, Quit.
- Esc / Start now opens a pause menu (resume, garage, settings, controls,
  main menu, quit).
- Settings: amount of traffic (few / normal / busy), graphics quality (pick Low
  for longer battery on the Steam Deck), km/h or mph, driving assists,
  vibration, fullscreen and volume. They're remembered.
- Gamepads rumble when you crash or land a big jump.

## [0.2.0] - 2026-09-30

First stable release for the Steam Deck. Drive around Turbo Town with a
gamepad or keyboard: a city full of traffic, a highway, a mountain road, a
beach and a stunt park.

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
- Traffic is now a mix of sports cars, sedans, vans, delivery trucks and city
  buses in lots of colours. Trucks and buses drive slower and take corners
  carefully. Parking lots have sedans and vans too.
- Traffic cars that get wedged back up and try again instead of giving up.

### Presentation
- HUD with speedometer, gear, RPM, damage and air-time popups.
- Engine, tire, wind, crash and horn sounds; tire smoke, dust, skid marks,
  sparks and cosmetic crash dents.
