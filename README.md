# Turbo Town (v0.1)

A stylized driving sandbox made in Godot 4.7. Drive around a small city, a ring
highway with overpasses, a mountain road, dirt fields, a beach and a stunt park
full of ramps.

Open the folder in Godot and press **Play (F5)**.

Feature checklist, backlog and known issues: see [PROGRESS.md](PROGRESS.md).

## Controls

| Action | Keyboard | Gamepad |
|---|---|---|
| Gas | W / Up | Right trigger |
| Brake / reverse | S / Down | Left trigger |
| Steer | A D / Left Right | Left stick |
| Handbrake | Space | A (Cross) |
| Flip car upright | R | Y (Triangle) |
| Back to spawn point | Backspace | Back / Select |
| Teleport | 1-6, Tab = next | D-pad right |
| Camera view (chase / far / hood) | C | RB |
| Look back | Q | LB |
| Look around | Mouse | Right stick |
| Assists on/off (drift mode) | T | |
| Traffic on/off | G | D-pad up |
| Horn | E | L3 |
| km/h ↔ mph | U | |
| Help | H / F1 | |
| Pause | Esc | Start |

Teleports: 1 City Center, 2 Highway, 3 Stunt Park, 4 Mountain Top, 5 Dirt Fields, 6 Beach.

## Project layout

```
scenes/
  main.tscn                 Game root: world + player car + camera + HUD
  vehicles/sports_car.tscn  The player car (physics, wheels, visuals, audio, FX, damage)
  world/world.tscn          Environment, sun, and the WorldBuilder that generates the map
  props/                    Cone, barrel, crate, bowling pin, lamp, traffic light,
                            parked car, and the parametric Ramp
  dev/physics_test.tscn     Flat test track for tuning the car
scripts/
  vehicle/   vehicle.gd (engine, gearbox, steering, assists), vehicle_wheel.gd
             (raycast suspension + tire model), player_vehicle_controller.gd (input),
             vehicle_body_visual.gd, vehicle_audio.gd, vehicle_effects.gd, vehicle_damage.gd
  traffic/   traffic_network.gd (lane graph built from the roads, turn curves,
             junctions, U-turns), traffic_manager.gd (spawning, signal timing),
             traffic_driver.gd (AI driver), traffic_light_prop.gd, traffic_audio.gd
  camera/    chase_camera.gd
  world/     map_layout.gd (ALL map numbers), terrain/road/city/nature/stunt park/
             landmark builders, mesh_builder.gd (geometry helper)
  props/     prop.gd, ramp.gd (@tool, editable in the editor)
  ui/        hud.gd, speedometer.gd
  game/      game.gd (spawning, teleports, respawn, pause)
  core/      input_setup.gd (all key/gamepad bindings)
  dev/       autotest.gd, dev_tools.gd, audio_check.gd (testing helpers)
assets/      models (.glb from Blender), shaders, materials
tools/blender/make_car.py   Regenerates the car + wheel models: blender -b -P tools/blender/make_car.py
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
  Tweak `max_cars` and spawn distances on the `Traffic` node in `main.tscn`.
* **Input**: all bindings are registered in `scripts/core/input_setup.gd`. Any
  action you define in Project Settings > Input Map overrides the default.

## Adding things

* **A new car**: duplicate `scenes/vehicles/sports_car.tscn`, swap the models
  under `Body` and the wheel `Visual` nodes, then tweak the exported values on the
  root (engine, gears, brakes, steering) and on each wheel (radius, springs, grip,
  which wheels steer/drive). Set `paint_color` on the `Body` node for a new color.
* **A ramp**: instance `scenes/props/ramp.tscn` in any scene and edit its
  shape/length/height/width in the Inspector — it rebuilds live in the editor.
* **Map changes**: edit `map_layout.gd` (city grid, block types, highway size and
  bridge height, mountain, hill road control points, dirt mounds...).

## Testing helpers (command line)

```
godot --path . --headless --fixed-fps 120 res://scenes/dev/physics_test.tscn -- --autotest=accel
    (scenarios: rest, accel, brake, turn, fastturn, handbrake, jump, wall, rollover)
godot --path . -- --tour=/tmp/shots     screenshots from spawn points + viewpoints
godot --path . -- --drive=/tmp/shots    autopilot lap of the highway, park, city, mountain
godot --path . --headless -s res://scripts/dev/audio_check.gd   engine sound levels
godot --path . -- --traffic=/tmp/shots  watch traffic 150 s, log speeds/stuck/crashes
godot --path . -- --rampage=/tmp/shots  player drives wrong-way into traffic
godot --path . --headless --fixed-fps 120 -- --bench     physics cost with/without traffic
godot --path . --headless -s res://scripts/dev/traffic_graph_check.gd   lane graph sanity
godot --path . --headless -s res://scripts/dev/terrain_road_check.gd    terrain poking through roads
```
