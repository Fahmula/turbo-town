# Turbo Town (v0.1)

A stylized driving sandbox made in Godot 4.7. Walk around a small city, a ring
highway with overpasses, a mountain road, dirt fields, a beach and a stunt park
full of ramps, get into any car, truck or bus you find, or fly a plane from
the airfield.

Open the folder in Godot and press **Play (F5)**. The game opens on the title
screen (PLAY! / GARAGE / SETTINGS / CONTROLS / QUIT); PLAY! puts you on foot
next to your vehicle. Esc or Start opens the pause menu.

Feature checklist, backlog and known issues: see [PROGRESS.md](PROGRESS.md).
Stable Steam Deck builds and how to make a release: see [RELEASING.md](RELEASING.md).
Visual direction (stylized realism) and asset rules: see [ART_BIBLE.md](ART_BIBLE.md).

## Controls

On foot:

| Action | Keyboard | Gamepad |
|---|---|---|
| Walk / run | W A S D / arrows | Left stick (a gentle push walks) |
| Sprint | Shift (hold) | L3 (click; lasts until you stop) |
| Walk slowly | Ctrl (hold) | |
| Jump | Space | A (Cross) |
| Get in a vehicle / flip one back over | F | B (Circle) |
| Look around | Mouse | Right stick |
| Camera distance | C | RB |

Driving:

| Action | Keyboard | Gamepad |
|---|---|---|
| Get out | F | B (Circle) |
| Gas | W / Up | Right trigger |
| Brake / reverse | S / Down | Left trigger |
| Steer | A D / Left Right | Left stick |
| Handbrake | Space | A (Cross) |
| In the air: spin | A / D | Left stick |
| In the air: flip / barrel roll | Space + W S / A D | A + RT LT / left stick |
| Flip car upright | R | Y (Triangle) |
| Garage: vehicle, paint, wheels | V | D-pad down |
| Instant replay | P | X (Square) |
| Back to spawn point | Backspace | Back / Select |
| Teleport | 1-9, Tab = next | D-pad right |
| Camera view (chase / far / hood) | C | RB |
| Look back | Q | LB |
| Look around | Mouse | Right stick |
| Assists on/off (drift mode) | T | |
| Traffic on/off | G | D-pad up |
| Island map | M | D-pad left |
| Horn | E | L3 |
| km/h ↔ mph | U | |
| Help | H / F1 | |
| Pause menu | Esc | Start / Menu |

Flying (planes):

| Action | Keyboard | Gamepad |
|---|---|---|
| Power (hold; let go in the air and it cruises) | Shift | Right trigger |
| Slow down, flaps (brakes on the ground) | Ctrl | Left trigger |
| Bank left / right (steer on the ground) | A / D | Left stick |
| Nose up / down | S / W | Left stick back / forward |
| Loop | hold S | hold the stick back |
| Barrel roll | Space + A / D | A + left stick |
| Help! Level the plane (on the ground: flip upright) | R | Y (Triangle) |
| Get out (landed and stopped) | F | B (Circle) |
| Camera (chase / far / cockpit) | C | RB |
| Flying assists on/off | T | |

"Flying controls" in Settings swaps the nose: push up to climb instead of
pulling back.

Teleports: 1 City Center, 2 Highway, 3 Stunt Park, 4 Mountain Top, 5 Dirt Fields, 6 Beach,
7 Airfield, 8 Harbour, 9 Lighthouse. Garage, teleports, respawn, traffic, map,
help and pause work on foot too.

**On foot**: walk up to any vehicle (yours, one parked in a lot, or a traffic
car that has stopped) and the prompt says "Get in the ..."; press F (B on a
gamepad). Press it again to get out: a moving vehicle stops first, and you
step out by the driver's door, or wherever there's room if a wall is in the
way. Your vehicle stays where you left it (a yellow square on the minimap and
the island map); teleporting on foot brings it with you, and the garage brings
the one you pick to where you stand. An overturned vehicle offers "Flip it back
over". Traffic stops for you (and honks if you stay in the road); a car that
bumps into you just knocks you aside.

**Planes**: three planes are parked on the airfield's apron (teleport 7):
walk up to one and get in like a car, or pick the Plane in the garage and
you're put on the runway (it isn't remembered as the vehicle you start
with). Take off with full power, pulling back at about 80 km/h. With the
assists on (the Assists setting, T) a let-go stick holds the climb or dive
and eases it level, turns don't lose height, the wings come level, full
stick banks to 65 degrees (A / Space + stick rolls all the way round), the
plane won't stall when you let go, and low over the runway with the power
off it settles onto its wheels. R / Y in the air levels the plane where it is.
You can't get out in the air; land, stop, then F / B. Teleports while
flying take you there in the air (the Airfield puts you on the runway), and
far out over the sea the plane turns back by itself. Races are for cars.

**Two players (split-screen)**: pick 2 PLAYERS on the title screen (or ADD
PLAYER 2 in the pause menu). Whoever pressed the button is player 1, with that
controller (plus the keyboard and mouse); player 2 presses A on another
controller, or Enter on the keyboard (then the keyboard is theirs). The screen
splits: player 1 on top, player 2 below, each with their own camera, HUD, car
and buttons. Player 2 starts on foot next to player 1 with their own car (a
sedan until they pick one in the garage; their choice is remembered
separately) and wears a blue T-shirt. A "P1" / "P2" marker floats over the
other player and both maps show them. X (0 on the keyboard, or R3) takes you
to the other player; D-pad right / Tab teleports only you. You can't take the
other player's car (you can flip it back over), traffic lives around both of
you (the same number of cars as for one player), and two planes go side by
side on the runway. Either player's Start pauses the game for both; an
unplugged controller pauses it too. PLAYER 2: LEAVE (pause menu) or MAIN MENU
ends split-screen. Races, instant replays and the crash cam are one-player
only for now. Each half is a wide strip: the camera keeps the full screen's
sideways view and crops the top and bottom, and the HUD is a compact version.

**Garage** (V / D-pad down): pick the sports car, sedan, van, delivery truck,
bus, pickup, buggy, monster truck or plane and set it up. Tabs (Q / E or LB / RB):
CAR (left/right = vehicle), PAINT (colour, racing stripes) and WHEELS (rims,
rim colour, tyres, tyre stripe, brake caliper colour; the camera zooms in on a
wheel). On PAINT and WHEELS, up/down picks a row and left/right changes it.
X / Y = surprise me (a random vehicle, or random choices on the tab), Enter / A =
drive (on foot, the vehicle is brought to you and you get in), Esc / B = back.
Each vehicle keeps its own setup, changes stick even when you back out, and
everything is remembered next time the game starts. The game is paused while
the garage is open.

**Stunts**: big air, flips, barrel rolls, air spins, drifts and near misses
(squeezing past traffic) score points. Tricks chain into a combo with a
multiplier; it's banked after a few seconds back on the wheels, or lost in a
wipeout (landing on the roof) or a big crash. Let go of a flip/roll and the car
turns itself level to land. Best combos and records: RECORDS in the menus
(saved to `user://records.cfg`).

**Replays**: press P (X on a gamepad) to watch the last 8 seconds again, with
TV-style camera cuts. Big crashes play back by themselves in slow motion (the
crash cam; switch it off in Settings). Enter / A skips. The game is paused while
a replay plays and carries on exactly where it was.

**Races**: six checkpoint races (City Sprint, Highway Loop, Mountain Climb,
Trail Climb, Dirt Rally, Beach Dash). Drive into a green start circle and stop, or pick one
on the RACES page. 3-2-1-GO, then drive through the gates in order: the next
one is lit, an arrow over the car points at it and the minimap marks it.
Gold/silver/bronze times, best times saved. Backspace (or falling in the sea)
puts you back at the last gate; END RACE in the pause menu stops it.

**Settings** (title screen or pause menu): traffic amount (few / normal / busy),
graphics quality (low / medium / high / ultra), time of day (day / sunset / night /
day & night cycle), speed units, driving assists, gamepad vibration, minimap,
crash cam, speaker boost, fullscreen and volume. Saved to `user://settings.cfg`
(`~/.local/share/godot/app_userdata/Turbo Town/` on Linux and the Steam Deck).
What is and isn't saved: see **Saving** below.

## Project layout

```
scenes/
  main.tscn                 Game root: world + player car + camera + HUD (Game makes player 1's
                            LocalPlayer at startup: the character, its cameras, the Possession)
  player/player_character.tscn  The walking character (model from assets/models/character/)
  vehicles/sports_car.tscn  The default player car (physics, wheels, visuals, audio, FX, damage)
  vehicles/sedan.tscn, van.tscn, box_truck.tscn, bus.tscn, pickup.tscn   Used by
                            traffic and drivable from the garage (every vehicle scene is both)
  vehicles/buggy.tscn, monster_truck.tscn   Garage-only (AWD, long-travel suspension)
  vehicles/plane.tscn       The sport plane (Aircraft), in the garage and parked at the airfield
  props/parked_plane.tscn   A parked plane (a cheap prop; swapped for plane.tscn when you get in)
  world/world.tscn          Environment, sun, and the WorldBuilder that generates the map
  props/                    Cone, barrel, crate, bowling pin, lamp, traffic light,
                            parked cars (drivable: `drive_scene`), and the parametric Ramp
  dev/physics_test.tscn     Flat test track for tuning the car
scripts/
  player/    local_player.gd (one player on this machine: character, vehicle, rigs,
             HUD, input; two in split-screen), player_input.gd (one player's
             devices and actions), possession.gd (what the player controls;
             getting in and out),
             controllable.gd (component: who drives a pawn, which rig controls it),
             player_character.gd (walk/run/sprint/jump, kerbs, animation,
             footsteps, being bumped), player_character_controller.gd (input),
             interactable.gd (things you use with F / B), vehicle_entry.gd (a
             vehicle's doors and safe exit spots), parked_car_entry.gd (parked
             car props you can drive)
  vehicle/   aircraft.gd (a plane: lift, drag, thrust, fly-by-wire controls and kid assists,
             propeller, control surfaces), player_aircraft_controller.gd (flying input),
             vehicle.gd (engine, gearbox, steering, assists), vehicle_wheel.gd
             (raycast suspension + tire model), player_vehicle_controller.gd (input),
             vehicle_body_visual.gd (materials, lamps, indicators, grime, contact shadow),
             vehicle_reflection.gd (the player car's reflection probe), vehicle_audio.gd,
             vehicle_effects.gd, vehicle_damage.gd,
             vehicle_catalog.gd (the garage's vehicle list, blurbs, star ratings,
             stock wheel parts), paint_palette.gd (garage and traffic paints)
  vehicle/custom/ parts_catalog.gd (everything the garage can change: tabs, slots,
             options), loadout.gd (one vehicle's setup: saved per vehicle, put on
             the car), wheel_kit.gd (fits rim + tyre parts to a vehicle's wheels)
  vehicle/audio/  vehicle_sound_profile.gd (what a vehicle class sounds like),
             vehicle_sound_bank.gd (shared tyre/crash/glass sounds), audio_director.gd
             (traffic voice budget, Doppler)
  traffic/   traffic_network.gd (lane graph built from the roads, turn curves,
             junctions, U-turns), traffic_manager.gd (spawning, signal timing),
             traffic_driver.gd (AI driver, turn signals), traffic_light_prop.gd
  camera/    chase_camera.gd (driving), flight_camera.gd (flying), on_foot_camera.gd (walking), camera_blend.gd
             (glides between them), menu_camera.gd (title screen), views.gd (the cameras the
             players see through: one, or one per split-screen view)
  world/     map_layout.gd (ALL map numbers), terrain/road/city/nature/stunt park/
             landmark builders, building_kit.gd / street_kit.gd / tree_kit.gd (the
             buildings, street furniture and trees, built in code), mesh_builder.gd
             (geometry helpers: bevelled boxes, lathes, sweeps, automatic LODs),
             art_palette.gd (world colours), day_night.gd (sun, real skies through
             the day, lights after dark), sky_catalog.gd (generated: each sky photo's
             sun and colours), grass_field.gd (3D grass tufts round the camera),
             tree_scatter.gd / tree_lod.gd / tree_colliders.gd (where trees grow,
             their LOD quadtree, trunk colliders), night_light.gd, lighthouse_beam.gd
  props/     prop.gd, kit_prop.gd (props whose mesh comes from StreetKit), ramp.gd
             (@tool, editable in the editor)
  ui/        hud.gd, speedometer.gd, world_map.gd (top-down island picture drawn
             at startup), minimap.gd (round heading-up minimap), big_map.gd (M),
             vehicle_picker.gd (the garage), game_menu.gd
             (title/pause/settings/controls pages), ui_kit.gd (shared menu look)
  game/      game.gd (title/driving/pause/garage states, spawning, teleports,
             respawn, changing vehicle), graphics_quality.gd (low/medium/high),
             stunt_tracker.gd (tricks, combos, near misses, drifts),
             race_catalog.gd (race routes + medal times), race_manager.gd (gates,
             countdown, timing)
  core/      input_setup.gd (all key/gamepad bindings), settings.gd (Settings
             autoload: saved player settings), records.gd (Records autoload:
             best combos, biggest air...)
  dev/       autotest.gd, dev_tools.gd, audio_check.gd (testing helpers)
assets/models/character/player.glb   The character (tools/blender/make_character.py)
assets/      models (.glb from Blender), shaders (world_common.gdshaderinc is shared;
             vehicle/ = car paint, glass, lamps, trim, tyres), materials (env/ = the
             world's materials), textures (generated), audio (built by tools/audio/;
             profiles/ = one VehicleSoundProfile per vehicle)
tools/blender/make_car.py      Sports car body:  blender -b -P tools/blender/make_car.py
tools/blender/make_sedan.py    Sedan (same command for every script)
tools/blender/make_van.py      Van
tools/blender/make_pickup.py   Pickup
tools/blender/make_truck.py    Delivery truck
tools/blender/make_bus.py      City bus
tools/blender/make_buggy.py    Buggy
tools/blender/make_monster.py  Monster truck
tools/blender/make_wheels.py   All four wheel types (sports, sedan, steel, off-road)
tools/blender/make_plane.py    The sport plane and its wheel (plane_body.glb, plane_wheel.glb)
tools/blender/body_kit.py      Shared loft body builder and modelling helpers
tools/blender/make_character.py  The player character from Quaternius' CC0 Universal Animation
                               Library (downloads it, rebuilds the mesh, keeps the animations)
tools/textures/make_textures.py  Ground detail, cloud and leaf textures:  python3 tools/textures/make_textures.py
tools/textures/fetch_*.py      Download CC0 scans (Poly Haven, ambientCG) and make the game textures:
                               fetch_sky.py (real skies), fetch_road.py, fetch_terrain.py,
                               fetch_building.py, fetch_foliage.py, fetch_props.py; shared helpers in
                               fetch_common.py. Run from the project root, then import in Godot
tools/audio/build_audio.py     Every sound in assets/audio/ (downloads the licensed recordings,
                               makes loops, synthesises the rest, writes the profiles):
                               python3 tools/audio/build_audio.py
ASSET_MANIFEST.md              Every third-party asset: source, creator, licence, attribution
```

## How things work

* **Vehicle physics**: a `RigidBody3D` (Jolt physics, 120 Hz) with four raycast
  wheels. Each wheel does spring/damper suspension and a slip-based tire model
  with a friction circle. `vehicle.gd` adds an automatic 5-speed gearbox,
  speed-sensitive steering, anti-roll bars, drag/downforce, and kid-friendly
  assists (traction control + stability control, gentle mid-air leveling) that
  can be switched off with **T**.
* **Map**: generated from code at startup (~0.4 s) using the numbers in
  `scripts/world/map_layout.gd`. It's deterministic, so it's the same every run.
  The builders are `@tool` scripts, so the island is also built in the editor:
  open `scenes/main.tscn` (or `scenes/world/world.tscn`) to see it in the 3D
  viewport. Those nodes have no owner, so they're never saved into the scene.
  To change the map, edit `map_layout.gd` or a builder in `scripts/world/`,
  then press **Rebuild map preview** in the World node's Inspector (untick
  *Preview In Editor* if the editor ever feels slow).
* **Players and split-screen**: each player on this machine is a `LocalPlayer`
  (`scripts/player/local_player.gd`): their character, vehicle, Possession,
  the three rigs (on foot, driving, flying: a controller and a camera each),
  HUD, stunt scoring and a `PlayerInput` (which devices are theirs). Game keeps
  one, and its old single-player fields (`game.vehicle`, `game.camera`,
  `game.teleport_to()`...) lead to player 1. Split-screen
  (`Game.add_player` / `remove_player`) adds player 2: InputSetup gives each
  player a copy of the gameplay actions bound to just their devices
  (`p1_accelerate`, `p2_accelerate`...), and `SplitScreen` makes two
  SubViewports sharing the one world; each player's cameras and HUD move into
  their own (the main viewport stops drawing the world). The views take no
  input: each LocalPlayer passes its own mouse look and camera button on.
  Everything in the world that follows "the camera" (grass, tree detail, the
  stars, traffic voices and Doppler, what's in sight) asks `Views`, which knows
  every player's camera. Grass and the "P1" / "P2" markers use render layers
  19 / 20 so they only show in one view. Players' car sounds fade with distance
  in split-screen (two cameras listen). Traffic spawns around whichever player
  has fewer cars and despawns when it's far from both, with the same total.
* **AI traffic**: ~22 cars live around the player. They are ordinary
  `Vehicle`s driven by a `TrafficDriver` instead of the player controller, so
  they crash, dent and flip like your car. Each driver follows a random route
  through a lane graph generated from the road polylines, steers with pure
  pursuit, and picks its speed with the Intelligent Driver Model (cars ahead,
  red lights and give-way points all count as "leaders"). City intersections
  with 3+ roads have demand-actuated traffic lights; left turns and merges give
  way. Hit a traffic car hard and it gets stunned, then drives on or gives up;
  wrecks are removed once you look away. Cars you block will honk at you.
  On the highway cars change lanes (overtake on the left, keep right) after a
  gap check; the east/west avenues cross it at signalized junctions with turns
  on and off in both directions. Honk and the car ahead pulls over or moves a
  lane right; park in a lane and traffic drives around you through the
  oncoming lane when it's clear (trucks and buses wait instead).
  Removed cars wait in a small pool per type and are reused (repaired and
  repainted), and drivers more than 140 m from the player update at half
  rate. `--bench` (with a window) prints spawn and render costs.
  Tweak `max_cars`, spawn distances, and the vehicle mix (`car_scenes` +
  `car_weights`) on the `Traffic` node in `main.tscn`. Traffic is a mix of
  sports cars, sedans, vans, delivery trucks and buses; each vehicle scene sets
  its own paint palette (`paint_palette` on its `Body` node) and AI speed
  (`ai_speed_factor`, `ai_max_accel` on the root).
* **Damage**: crash severity is the car's change of velocity over a quarter of a
  second. Each car shares its model's mesh until its first dent, then gets its
  own copy; the surface data is read from the GPU once per model and cached.
  Dents follow the hits (smooth falloff, normals bent so they show);
  bumpers and spoilers lose health from nearby hits and fall off as debris
  (the models export them as separate meshes); lights break at the end that
  was hit and the glass cracks when the car is badly smashed; a smashed front
  costs up to half the engine power, pulls the steering slightly and smokes.
  Any reset (R, respawn, teleport, garage) repairs the car.
* **Vehicle looks**: the models' materials are swapped by name for the vehicle
  shaders (`assets/shaders/vehicle/`): car paint with a clear coat, metallic
  flop, road grime and a damage layer (scuffs, primer and bare metal written
  into vertex colours by `VehicleDamage`), glass with a crack web, lamps
  (headlights on at night, brake, reverse, amber indicators), grilles and
  tyres. The player's car reflects its real surroundings on Medium/High
  (`VehicleReflection`, a probe re-captured every 14 m). Traffic signals before
  turns and lane changes and puts its hazards on after a crash.
* **Vehicle sound** (`vehicle_audio.gd`): each vehicle's `VehicleSoundProfile`
  holds steady engine loops recorded at known rpm, on and off load; the two
  either side of the current rpm play pitched to it and crossfade, blended by
  throttle load, plus start-up, turbo, pops, shifts, air brakes, beepers and a
  horn. Shared sounds (`VehicleSoundBank`): tyre roll per surface, squeal,
  gravel, wind, scraping, crash tiers by strength and what was hit, glass,
  suspension knocks, splashes; reverb in tunnels. Traffic uses a lighter
  version and the `AudioDirector` lets only the nearest 6 cars play their
  loops (with Doppler). Sources and licences: [ASSET_MANIFEST.md](ASSET_MANIFEST.md);
  CREDITS in the menus.
* **Replay** (`scripts/game/replay.gd`): records the player's body and wheel
  transforms and nearby traffic 60 times a second (10 s ring buffer), then
  poses them from the recording while the tree is paused and puts the live
  state back afterwards. Damage, debris and props aren't recorded. The crash
  cam is triggered by `VehicleDamage.crashed` (severity >= 0.5).
* **Player character and vehicles** (`scripts/player/`): the player controls a
  *pawn*, the character or a vehicle. Anything controllable has a
  `Controllable` component (Vehicle and PlayerCharacter add one) that says
  who drives it right now (the player's `Possession`, a `TrafficDriver`, or
  nobody) and its `kind`, which picks a *rig*: the input controller and camera
  for that kind (`PlayerCharacterController` + `OnFootCamera`,
  `PlayerVehicleController` + `ChaseCamera`, `PlayerAircraftController` +
  `FlightCamera` for planes). Only one rig has a pawn at a
  time, so the character and a vehicle can never both take input, and a
  traffic car is first taken off its driver (`TrafficManager.claim`). A boat
  later is a new kind with its own controller and camera (`Possession.add_rig`).
  Getting in: the `Interactable` nearest the character (a vehicle's
  `VehicleEntry`, a parked car's `ParkedCarEntry`) shows its prompt; F / B
  walks the character to the door for a moment while the `CameraBlend` glides
  to the chase camera, then hides it and hands the vehicle the controls;
  `Game.adopt_vehicle` points the HUD, maps, traffic, stunts, replay,
  headlights, reflections and full engine sound at it. Getting out brakes the
  vehicle to a stop, `VehicleEntry.find_exit` picks a spot (driver's door,
  then the other side, behind, in front, rings further out, the roof: each
  needs walkable ground at about the same height, room for the capsule and no
  wall between the seat and it), the vehicle is parked (handbrake, engine off,
  quiet sound) and the camera glides back keeping its heading. Vehicles you
  left stay parked; up to three older ones are kept, and they go when far away
  and out of sight. Characters are on physics layer 4: vehicles don't collide
  with them (a car would hit a person like a wall); instead the character is
  shoved aside by anything that drives into it, and traffic drivers stop for
  it (`TrafficManager.pedestrians`).
* **Flying** (`aircraft.gd`): a plane is a `Vehicle` (so damage, sound,
  getting in and out, the HUD, maps and replays work as for a car) whose
  engine turns a propeller. Each tick it computes lift from the wing's angle
  of attack (falling off past a 15 degree stall), drag, a side force and
  propeller thrust (fading with airspeed and above 530 m), and three raycast
  wheels carry it on the ground. The controls are fly-by-wire: the stick
  asks for g (the wing's angle of attack is chosen to give it, never past
  the stall) and for a roll rate or (assists on) a bank angle; the nose
  follows the airflow, so banking turns the plane; authority grows with
  airspeed. The model's moving parts (propeller, blur disc, ailerons, flaps,
  elevator, rudder) are found by name. The `FlightCamera` lags behind the
  plane, leans with part of the bank and follows fully when steep or upside
  down.
* **Saving**: two files in `user://` (on Linux and the Deck
  `~/.local/share/godot/app_userdata/Turbo Town/`). `settings.cfg` (the
  `Settings` autoload) holds the options *and* the player's garage: which
  vehicle they drive (`vehicle`) and every vehicle's setup (`loadouts`:
  vehicle id -> only the parts that differ from stock, so new garage slots and
  parts need no save changes). `records.cfg` (`Records`) holds best combos,
  biggest air, longest drift, most flips, near misses, total score and race
  best times. The dev audio panel writes `audio_mix.cfg`. Both autoloads load
  at startup, save on every change, type-check what they read, and migrate
  older formats in `load_file()`; dev/test runs (any command-line user
  argument) never read or write them. Not saved: where you are, on foot or in
  a vehicle (every session starts at the City Center beside your vehicle),
  damage, traffic, parked vehicles you left, the session's stunt score. New
  saved state goes in the same places: an option or a choice about the
  player's things is a key in `Settings.DEFAULTS` (typed, with a default),
  customization follows `Loadout`'s overrides-of-stock pattern, a record goes
  in `Records`. If progress grows (unlocks, money, character outfits, several
  profiles), move the player's things (`vehicle`, `loadouts`) to a
  `user://profile.cfg` with a one-off migration in `load_file()`.
* **Pausing**: `Game` processes always (menus, input), so it sets its gameplay
  children (world, traffic, the player car, camera, stunts, races) to
  pausable; anything that should run in menus sets its own process mode.
* **Input**: all bindings are registered in `scripts/core/input_setup.gd`. Any
  action you define in Project Settings > Input Map overrides the default.

## Adding things

* **A new car**: duplicate one of the scenes in `scenes/vehicles/`, swap the models
  under `Body` and the wheel `Visual` nodes, then tweak the exported values on the
  root (engine, gears, brakes, steering) and on each wheel (radius, springs, grip,
  which wheels steer/drive). Set `paint_color` on the `Body` node for a new color
  and `driver_eye` on the root for the hood camera. Add it to
  `scripts/vehicle/vehicle_catalog.gd` to make it appear in the garage (with the
  `rims` / `tyres` its wheel model is made of). The chase camera frames bigger
  vehicles automatically (from their collision boxes).
* **Garage parts**: a new rim or tyre is a builder in `tools/blender/make_wheels.py`
  (rims are built to one standard fit, see its docstring) plus an entry in
  `PartsCatalog.RIMS` / `TYRES`; colours are entries in the other lists there.
  A new kind of customization (spoilers, exhausts...) is a slot: add it to
  `PartsCatalog.SLOTS` and a tab in `TABS`, give it a stock value in
  `Loadout._stock_values()` and put it on the car in `Loadout.apply()`. The
  garage builds its rows from the catalog, and saving works for any slot.
* **A ramp**: instance `scenes/props/ramp.tscn` in any scene and edit its
  shape/length/height/width in the Inspector — it rebuilds live in the editor.
* **Map changes**: edit `map_layout.gd` (city grid, block types, highway size and
  bridge height, mountain, hill road control points, dirt mounds...).

## Testing helpers (command line)

Add `--audio-driver Dummy` to any of these to keep them silent (the game still
mixes its sound, so `--audio` can record it).

```
godot --path . --headless --fixed-fps 120 res://scenes/dev/physics_test.tscn -- --autotest=accel
    (scenarios: rest, accel, brake, turn, fastturn, handbrake, jump, wall, rollover)
    add --vehicle=res://scenes/vehicles/bus.tscn to test another vehicle
godot --path . -- --tour=/tmp/shots     screenshots from spawn points + viewpoints
godot --path . -- --drive=/tmp/shots    autopilot lap of the highway, park, city, mountain
godot --path . --headless -s res://scripts/dev/audio_check.gd   every vehicle's sound profile loads and covers its rev range
godot --path . --audio-driver Dummy -- --audio=/tmp/shots   scripted drive recorded to session.wav (+ traffic voice budget);
    then: python3 tools/audio/check_recording.py /tmp/shots   (clicks, dropouts, clipping, levels)
    add --stems for one recording per mix bus, --speakers=on|off for the Deck / flat mix
godot --path . --audio-driver Dummy -- --mixpanel=/tmp/shots   the dev audio mix panel (F8 in the game)
godot --path . -- --lookdev=/tmp/shots  every vehicle from fixed cameras, day/sunset/night
    add --vehicles=a,b --views=front34,rear34,side,wheel,chase,lamps --times=day --damaged
godot --path . -- --traffic=/tmp/shots  watch traffic 150 s, log speeds/stuck/crashes
godot --path . -- --rampage=/tmp/shots  player drives wrong-way into traffic
godot --path . -- --showcase=/tmp/shots one of each traffic vehicle in a filmed convoy
godot --path . -- --garage=/tmp/shots   garage menu, customising + changing into every vehicle (pass/fail checks)
godot --path . -- --onfoot=/tmp/shots   the character: walk/run/sprint/jump, in and out of every vehicle type
                                        (keyboard + gamepad), traffic and parked cars, exits by walls, overturned
                                        and damaged vehicles, being bumped, garage/teleport/race/sea on foot,
                                        leak check (pass/fail)
godot --path . -- --onfootbench         character cost: draw calls / CPU / GPU shown vs hidden, physics time
godot --path . -- --charsheet=/tmp/shots  the character from fixed cameras at day/sunset/night + animation strips
godot --path . -- --split=/tmp/shots    two players: joining with a second gamepad, each player's own controls
                                        (simulated pads 0 and 1), views, cars, teleports, X to the other player,
                                        garage, planes, traffic around both, pause, leaving and rejoining (pass/fail)
godot --path . --gpu-index 0 --resolution 1280x800 -- --splitbench=/tmp/perf   one view vs split-screen: GPU and
                                        frame time, draw calls at Low / Medium / High (--levels=0,1 --views=city_city)
    add --graphics=0..3 to any dev run to use Low / Medium / High / Ultra
godot --path . --gpu-index 0 -- --perfsweep=/tmp/perf   GPU cost of each graphics effect, Medium/Low, trees and grass,
                                        standing and driving (--gpu-index 0 = a weak integrated GPU, close to the Deck)
godot --path . -- --wheels=/tmp/shots   every rim, rim colour, tyre and tyre stripe in the garage + on the road (shots)
godot --path . -- --menus=/tmp/shots    title/pause/settings/controls menus driven by input (pass/fail)
godot --path . -- --lanes=/tmp/shots    passing a parked player, horn reactions, highway lane changes
godot --path . -- --stunts=/tmp/shots   air, flips, rolls, spins, drift, near miss, wipeout (pass/fail)
godot --path . -- --map=/tmp/shots      minimap / big map screenshots (+ world_map.png)
godot --path . -- --races=/tmp/shots    race flow checks + autopilot drives every race (medal reference times)
godot --path . -- --park=/tmp/shots     loop-the-loop (4 vehicles) and the wall-ride bowl
godot --path . -- --trail=/tmp/shots    buggy + pickup drive the mountain trail to the summit
godot --path . -- --landmarks=/tmp/shots drive the tunnel, bridge, runway and a pier (+ views)
godot --path . -- --night=/tmp/shots    sunset / night / cycle checks and screenshots
godot --path . -- --scenery=/tmp/shots  fixed city/bridge views, day/sunset/night, Low/High, draw calls per view
    add --views=a,b --quick --stress --profile --traffic-on to narrow or measure
godot --path . -- --damage=/tmp/shots   crash into walls: parts off, lights/glass, pull, power, repair
    add --vehicle=<id> (sedan, van, box_truck, bus, pickup, buggy, monster_truck) to run a main-game test in another vehicle
godot --path . -- --replay=/tmp/shots   pausing freezes the car, instant replay, crash cam (pass/fail)
godot --path . --fixed-fps 60 -- --flight=/tmp/shots  the plane: take-off, cruise, turns, loop, roll, stall, help
                                        button, teleports, the island edge, landing, getting out and in, replay,
                                        parked planes, taxiing, crash, garage (pass/fail)
godot --path . --gpu-index 0 -- --flightbench=/tmp/perf   GPU cost flying over the city at 60 / 150 / 300 m,
                                        Medium / Low / High
godot --path . --headless --fixed-fps 120 -- --spawncheck   60 traffic spawns, none may crash
godot --path . -- --junction=/tmp/shots highway/avenue junction: turns used, crashes, jams (150 s)
godot --path . --headless --fixed-fps 120 -- --corner=/tmp   each vehicle lapping the highway with lane changes (roll check)
godot --path . --headless --fixed-fps 120 -- --uturn=/tmp   car U-turns at a dead end
godot --path . --headless --fixed-fps 120 -- --bench     physics cost with/without traffic, spawn cost
godot --path . --fixed-fps 120 -- --bench                same + real spawn and render costs (window)
godot --path . --headless -s res://scripts/dev/traffic_graph_check.gd   lane graph sanity
godot --path . --headless -s res://scripts/dev/terrain_road_check.gd    terrain poking through roads
```
