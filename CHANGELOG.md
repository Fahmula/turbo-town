# Changelog

Player-facing changes per stable release. `tools/release.sh X.Y.Z` uses the
`## [X.Y.Z]` section below as the GitHub Release notes, so write it for the
player (what's new, what's fixed), not as a commit log.

Before releasing: rename `[Unreleased]` to the new version, add the date,
commit, push, then run the release script. Start a fresh `[Unreleased]` after.

## [Unreleased]

### Looks
- A new, more realistic look for the whole island: a warm afternoon sun with
  proper shadows, hazy hills and sea in the distance, natural grass and trees,
  brick and stucco buildings, and grey asphalt and concrete roads.
- Golden sunsets, and at night the city windows glow like warm rooms (some
  cool-white offices too).
- A brand-new sports car: a curved, realistic body with see-through windows
  and seats and a steering wheel inside, real headlights and tail lights, new
  alloy wheels and glossy paint. Its dents, falling-off bumpers and wing work
  as before.
- New sedan: a proper family car with six side windows, chrome trim, big
  headlights, seats inside and new six-spoke wheels.
- New van: a modern people-carrier with big windows, black bumpers and sills,
  twin rear doors, seats inside and new steel wheels.
- Garage: 12 new paint colours that look like real car paint (some sparkle
  like metallic paint), plus fun ones like lime and pink, and racing stripes
  you can switch on for the sports car (X key or the Y button).
- Traffic now looks like a real town: mostly white, black, grey and silver
  cars, some blue and red ones, and the odd bright colour.

### Fixes
- Building windows no longer flicker with a "TV static" pattern, day or night.
- On Low graphics, shadows no longer draw stripes across the road at sunset.
- Crashes cost less: dents only rework the part of the car that was hit.

## [0.3.1] - 2026-10-01

### Fixes
- Menus work with a gamepad again: A presses the highlighted button and B goes
  back (before, you could move between buttons but not pick one).

## [0.3.0] - 2026-10-01

A huge update: a garage full of vehicles, stunts and combos, races, day and
night, new places to explore, crashes where bits fall off, and instant replays.

### Vehicles
- New garage: press V (D-pad down on a gamepad) to pick any vehicle and a
  paint colour. The game remembers your choice next time.
- Three new vehicles: a pickup truck (it shows up in traffic too), a light and
  bouncy dune buggy, and a MONSTER TRUCK with giant wheels that can drive right
  over cars. You can also drive the sedan, van, delivery truck and city bus.
- Every vehicle sounds different: rumbling diesel truck and bus, burbly V8
  pickup, buzzy buggy, and a monster truck with a supercharger whine.
- The camera pulls back for the big vehicles so you can see the road, and the
  hood camera sits up on the roof of the tall ones.

### Stunts
- Score points for big air, flips, barrel rolls, spins, drifts and near misses
  with traffic. Chain tricks into combos for a multiplier, but land on your
  wheels: a wipeout or a big crash loses the combo.
- Air tricks: steer to spin; hold Space (A on a gamepad) and use W/S to flip or
  A/D to barrel roll. Let go and the car turns itself level to land.
- A LOOP-THE-LOOP in the stunt park (go 80+ km/h!) and a round WALL RIDE bowl
  right after it. Both count as stunts.
- RECORDS page with your best combos, biggest air, longest drift and more.

### Races
- Six races: City Sprint, Highway Loop, Mountain Climb, Trail Climb, Dirt Rally
  and Beach Dash. Stop in a green circle to start one, or pick it from the
  RACES menu.
- Drive through the gates in order: the next gate glows, an arrow above your
  car points the way and the minimap shows it. Win gold, silver or bronze, and
  beat your best time.

### New places
- An airfield in the south-east with a long runway, hangars, a control tower
  and planes (press 7 to go there).
- A harbour on the north-west coast with piers, boats, a big crane and stacks
  of containers (press 8).
- Lighthouse Island off the beach, reached over a bridge (press 9).
- A tunnel through a hill on the road to the stunt park.
- A dirt trail zig-zags up the mountain to the summit, with jumps.

### Day and night
- Pick day, sunset, night or a day-and-night cycle in Settings. At night the
  windows light up, street lamps come on, your car has headlights and the
  lighthouse beam sweeps across the sea.

### Crashes
- Bumpers and spoilers can fall off in big crashes, lights break, the glass
  cracks and a smashed engine smokes, loses power and pulls to one side.
  Press R (or respawn) to fix your car.

### Replays
- Press P (X on a gamepad) for an instant replay of the last 8 seconds, with
  TV-style camera angles.
- CRASH CAM: big crashes play back in slow motion. Press Enter / A to skip, or
  switch it off in Settings.

### Maps
- Minimap in the corner: it turns with your car, zooms out when you go fast
  and shows the traffic. Turn it off in Settings.
- Press M (D-pad left) for a map of the whole island with the numbered
  teleport spots.

### Traffic
- Highway traffic changes lanes: cars overtake slow trucks and buses and keep right.
- Honk (E / L3) behind a car and it pulls over or moves a lane over to let you pass.
- Park in a car's lane and it drives around you when the other lane is clear,
  instead of just waiting and honking.
- The highway has proper junctions with traffic lights where the east and west
  avenues cross it: cars get on and off in both directions or go straight across.

### Menus
- New title screen with your car on show: Drive, Garage, Settings, Controls, Quit.
- Esc / Start opens a pause menu (resume, garage, settings, controls, main
  menu, quit).
- Settings: amount of traffic (few / normal / busy), graphics quality (pick Low
  for longer battery on the Steam Deck), time of day, km/h or mph, driving
  assists, vibration, minimap, crash cam, fullscreen and volume. They're
  remembered.
- Gamepads rumble when you crash or land a big jump.

### Fixes
- Smoother driving: the game no longer stutters for a moment each time a
  traffic car appears.
- After pausing, the car could jump forward or get a big kick when the game
  carried on, and the race clock kept running in the pause menu.
- Traffic cars sometimes got flung into the air the moment they appeared.
- City traffic only ever turned right at intersections. Now cars go straight
  and turn left too.

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
