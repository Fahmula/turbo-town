# Turbo Town (v0.1)

A stylized driving sandbox made in Godot 4.7. Drive around a small city, a ring
highway with overpasses, a mountain road, dirt fields, a beach and a stunt park
full of ramps.

Open the folder in Godot and press **Play (F5)**. The game opens on the title
screen (DRIVE! / GARAGE / SETTINGS / CONTROLS / QUIT); Esc or Start opens the
pause menu while driving.

Feature checklist, backlog and known issues: see [PROGRESS.md](PROGRESS.md).
Stable Steam Deck builds and how to make a release: see [RELEASING.md](RELEASING.md).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Gas | W / Up | Right trigger |
| Brake / reverse | S / Down | Left trigger |
| Steer | A D / Left Right | Left stick |
| Handbrake | Space | A (Cross) |
| In the air: spin | A / D | Left stick |
| In the air: flip / barrel roll | Space + W S / A D | A + RT LT / left stick |
| Flip car upright | R | Y (Triangle) |
| Garage: change vehicle / paint | V | D-pad down |
| Back to spawn point | Backspace | Back / Select |
| Teleport | 1-6, Tab = next | D-pad right |
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

Teleports: 1 City Center, 2 Highway, 3 Stunt Park, 4 Mountain Top, 5 Dirt Fields, 6 Beach.

**Garage** (V / D-pad down): pick the sports car, sedan, van, delivery truck,
bus, pickup, buggy or monster truck and a paint colour. Left/right = vehicle, up/down = paint, Enter / A =
drive, Esc / B = back. The game is paused while it's open, and the choice is
remembered next time the game starts.

**Stunts**: big air, flips, barrel rolls, air spins, drifts and near misses
(squeezing past traffic) score points. Tricks chain into a combo with a
multiplier; it's banked after a few seconds back on the wheels, or lost in a
wipeout (landing on the roof) or a big crash. Let go of a flip/roll and the car
turns itself level to land. Best combos and records: RECORDS in the menus
(saved to `user://records.cfg`).

**Races**: six checkpoint races (City Sprint, Highway Loop, Mountain Climb,
Trail Climb, Dirt Rally, Beach Dash). Drive into a green start circle and stop, or pick one
on the RACES page. 3-2-1-GO, then drive through the gates in order: the next
one is lit, an arrow over the car points at it and the minimap marks it.
Gold/silver/bronze times, best times saved. Backspace (or falling in the sea)
puts you back at the last gate; END RACE in the pause menu stops it.

**Settings** (title screen or pause menu): traffic amount (few / normal / busy),
graphics quality (low / medium / high), speed units, driving assists, gamepad
vibration, fullscreen and volume. Saved to `user://settings.cfg`
(`~/.local/share/godot/app_userdata/Turbo Town/` on Linux and the Steam Deck).

## Project layout

```
scenes/
  main.tscn                 Game root: world + player car + camera + HUD
  vehicles/sports_car.tscn  The default player car (physics, wheels, visuals, audio, FX, damage)
  vehicles/sedan.tscn, van.tscn, box_truck.tscn, bus.tscn, pickup.tscn   Used by
                            traffic and drivable from the garage (every vehicle scene is both)
  vehicles/buggy.tscn, monster_truck.tscn   Garage-only (AWD, long-travel suspension)
  world/world.tscn          Environment, sun, and the WorldBuilder that generates the map
  props/                    Cone, barrel, crate, bowling pin, lamp, traffic light,
                            parked car, and the parametric Ramp
  dev/physics_test.tscn     Flat test track for tuning the car
scripts/
  vehicle/   vehicle.gd (engine, gearbox, steering, assists), vehicle_wheel.gd
             (raycast suspension + tire model), player_vehicle_controller.gd (input),
             vehicle_body_visual.gd, vehicle_audio.gd, vehicle_effects.gd, vehicle_damage.gd,
             vehicle_catalog.gd (the garage's vehicle list, blurbs, star ratings, colours)
  traffic/   traffic_network.gd (lane graph built from the roads, turn curves,
             junctions, U-turns), traffic_manager.gd (spawning, signal timing),
             traffic_driver.gd (AI driver), traffic_light_prop.gd, traffic_audio.gd
  camera/    chase_camera.gd
  world/     map_layout.gd (ALL map numbers), terrain/road/city/nature/stunt park/
             landmark builders, mesh_builder.gd (geometry helper)
  props/     prop.gd, ramp.gd (@tool, editable in the editor)
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
assets/      models (.glb from Blender), shaders, materials
tools/blender/make_car.py              Sports car + wheel:  blender -b -P tools/blender/make_car.py
tools/blender/make_traffic_vehicles.py Sedan, van, truck, bus + steel wheel (same command)
tools/blender/make_offroad_vehicles.py Pickup, buggy, monster truck + knobbly wheel
tools/blender/vehicle_kit.py           Shared modelling helpers for the scripts
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
  The map is not visible in the editor viewport — run the game to see it.
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
  Tweak `max_cars`, spawn distances, and the vehicle mix (`car_scenes` +
  `car_weights`) on the `Traffic` node in `main.tscn`. Traffic is a mix of
  sports cars, sedans, vans, delivery trucks and buses; each vehicle scene sets
  its own paint palette (`paint_palette` on its `Body` node) and AI speed
  (`ai_speed_factor`, `ai_max_accel` on the root).
* **Input**: all bindings are registered in `scripts/core/input_setup.gd`. Any
  action you define in Project Settings > Input Map overrides the default.

## Adding things

* **A new car**: duplicate one of the scenes in `scenes/vehicles/`, swap the models
  under `Body` and the wheel `Visual` nodes, then tweak the exported values on the
  root (engine, gears, brakes, steering) and on each wheel (radius, springs, grip,
  which wheels steer/drive). Set `paint_color` on the `Body` node for a new color
  and `driver_eye` on the root for the hood camera. Add it to
  `scripts/vehicle/vehicle_catalog.gd` to make it appear in the garage. The chase
  camera frames bigger vehicles automatically (from their collision boxes).
* **A ramp**: instance `scenes/props/ramp.tscn` in any scene and edit its
  shape/length/height/width in the Inspector — it rebuilds live in the editor.
* **Map changes**: edit `map_layout.gd` (city grid, block types, highway size and
  bridge height, mountain, hill road control points, dirt mounds...).

## Testing helpers (command line)

```
godot --path . --headless --fixed-fps 120 res://scenes/dev/physics_test.tscn -- --autotest=accel
    (scenarios: rest, accel, brake, turn, fastturn, handbrake, jump, wall, rollover)
    add --vehicle=res://scenes/vehicles/bus.tscn to test another vehicle
godot --path . -- --tour=/tmp/shots     screenshots from spawn points + viewpoints
godot --path . -- --drive=/tmp/shots    autopilot lap of the highway, park, city, mountain
godot --path . --headless -s res://scripts/dev/audio_check.gd   engine sound levels
godot --path . -- --traffic=/tmp/shots  watch traffic 150 s, log speeds/stuck/crashes
godot --path . -- --rampage=/tmp/shots  player drives wrong-way into traffic
godot --path . -- --showcase=/tmp/shots one of each traffic vehicle in a filmed convoy
godot --path . -- --garage=/tmp/shots   garage menu + changing into every vehicle (pass/fail checks)
godot --path . -- --menus=/tmp/shots    title/pause/settings/controls menus driven by input (pass/fail)
godot --path . -- --lanes=/tmp/shots    passing a parked player, horn reactions, highway lane changes
godot --path . -- --stunts=/tmp/shots   air, flips, rolls, spins, drift, near miss, wipeout (pass/fail)
godot --path . -- --map=/tmp/shots      minimap / big map screenshots (+ world_map.png)
godot --path . -- --races=/tmp/shots    race flow checks + autopilot drives every race (medal reference times)
godot --path . -- --park=/tmp/shots     loop-the-loop (4 vehicles) and the wall-ride bowl
godot --path . -- --trail=/tmp/shots    buggy + pickup drive the mountain trail to the summit
godot --path . --headless --fixed-fps 120 -- --spawncheck   60 traffic spawns, none may crash
godot --path . -- --junction=/tmp/shots highway/avenue junction: turns used, crashes, jams (150 s)
godot --path . --headless --fixed-fps 120 -- --corner=/tmp   each vehicle lapping the highway with lane changes (roll check)
godot --path . --headless --fixed-fps 120 -- --uturn=/tmp   car U-turns at a dead end
godot --path . --headless --fixed-fps 120 -- --bench     physics cost with/without traffic
godot --path . --headless -s res://scripts/dev/traffic_graph_check.gd   lane graph sanity
godot --path . --headless -s res://scripts/dev/terrain_road_check.gd    terrain poking through roads
```
