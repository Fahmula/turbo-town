# Turbo Town Art Bible

The visual rules for Turbo Town. Direction: **stylized realism**. This file is
written for the agents (and people) who build assets and change how the game
looks. Every rule should be something you can act on.

Established 2026-10-01 (game at v0.3.1). The owner approves changes to the
direction itself. Values and techniques can be refined by whoever is doing the
work, as long as this file is updated in the same commit.

## How to use this document

- Before any change to visuals, UI, environment, vehicles, materials, lighting,
  shaders or assets: read **§0 Quick rules**, then the sections for what you're
  touching.
- Precedence: the owner's explicit instruction > this bible > existing assets.
  Most existing assets are **legacy style** (§3). Don't copy them as examples.
- Don't restyle existing assets unless the task asks for it. When it does,
  migrate a whole family at once (§28.7).
- **"Today:"** notes mark where the current game breaks a rule. They're a to-do
  list, not permission to keep doing it.
- If a rule is wrong or blocks good work, change it here in the same commit and
  say why in the commit message.

Contents: 0 Quick rules · 0b Realism · 0c MegaKit experiment · 1 Identity · 2 References · 3 Today's baseline ·
4 Stylization dial · 5 Colour palette · 6 Materials/PBR · 7 Shaders ·
8 Textures/detail · 9 Lighting · 10 Shadows · 11 Sky/atmosphere ·
12 Vehicle design · 13 Vehicle materials · 14 Damage/deformation ·
15 Buildings · 16 Roads/highways · 17 Props · 18 Vegetation ·
19 Terrain/water · 20 UI · 21 Typography · 22 Icons · 23 Effects ·
24 Blender · 25 Godot import · 26 LOD/detail · 27 Steam Deck ·
28 Consistency rules · 29 Avoid list · 30 Workflow · 31 Migration order ·
32 Open owner decisions · 33 Vehicle sound · 34 Characters

---

## 0. Quick rules

1. **Real-world scale, proportions, light and materials. Simplified, clean
   surfaces and shapes.** That's what stylized realism means here.
2. **The world is naturalistic and slightly warm. Saturated colour belongs to
   vehicles, signs, gameplay markers and UI.** Large surfaces have chroma
   ≤ 0.35 (§5).
3. **Smooth-shaded, bevelled forms.** No faceted low-poly organic shapes, no
   toon shading, no outlines.
4. **Honest PBR.** Albedo has no baked light or shadow and stays within sRGB
   0.11–0.94. Roughness follows the table in §6.
5. **One lighting setup**, owned by `DayNight` and `world.tscn`: sun or moon,
   sky ambient, fog. No GI, no SSR, no volumetrics, and no motion blur or DOF
   during gameplay.
6. **60 fps on the Steam Deck on Medium** (and Low); High and Ultra may be
   heavier. Budgets are in §27. Every new effect has Low/Medium/High
   behaviour in `GraphicsQuality`.
7. **Vehicles** are generic, unbranded archetypes with deformation-ready
   topology and **≤ 6,000 deformable vertices**. Keep the name contracts (§13).
8. **Damage** should be satisfying, readable and kid-safe: dents, scrapes,
   parts falling off, broken glass and lights, smoke. Nobody gets hurt, no gore.
   Fire and explosions only if the owner asks.
9. **Assets come from committed generators** (Blender Python, world builders,
   texture scripts). Never hand-edit a generated output.
10. **UI goes through `UiKit`.** Text ≥ 18 px, gamepad first, icons are vector
    shapes (never font glyphs).
11. **Never commit** reference images, real brands or logos, or third-party art
    without a recorded CC0/OFL licence.
12. **Before/after screenshots** (day, sunset, night; Low and High) plus
    `--bench` numbers for every visual change (§30).

---

## 0b. Realism (approved 2026-10-03, released in 0.7.0)

The owner asked "how good can we get things looking", lifted the usual
limits for an experiment on a `realism` branch, then approved it and had it
merged and released (0.7.0). These rules override the rest of the bible
wherever they disagree; the older sections still describe the parts they
don't touch:

- **Direction:** as realistic as Godot and the Steam Deck allow. §4's
  "stylize" column and §29's bans on scanned/photo textures, "chasing
  photorealism", SSIL, SSR, SDFGI and volumetric fog don't apply. Still in
  force: real scale, no real brands or logos, kid-safe damage, readable
  gameplay elements (markings, ramps, gates), no light baked into albedo.
- **Textures:** CC0 scans from Poly Haven and ambientCG, downloaded and
  processed by `tools/textures/fetch_<family>.py` (helpers in
  `fetch_common.py`, cache in `build/texture_sources/`, credits in each
  folder's `SOURCES.md` and in ASSET_MANIFEST.md). Up to 2048², mostly 1024²;
  albedo de-lit and normalised so the palette colour still sets the average;
  normal/roughness/AO packed; never visibly tiling (two scales, per-cell
  rotation, macro variation).
- **Lighting (High):** SDFGI (bounce light, sky occlusion), SSIL, SSAO, SSR,
  light volumetric haze, soft sun shadows (`light_angular_distance` 0.6).
  Medium and Low keep the old cheap path. Moving things are
  `GI_MODE_DYNAMIC`; bulk-instanced foliage, grass and rocks are
  `GI_MODE_DISABLED` (alpha cards voxelised into SDFGI darken themselves).
- **Sky:** six real photographed skies (Poly Haven "pure sky" HDRIs; see §11).
- **Families:** roads, paving and cast concrete (`road_common.gdshaderinc`);
  terrain from material weights with 3D grass tufts (`grass_field.gd`),
  scanned boulders and a spectral sea; facades with wall scans, recessed
  windows, interior-mapped rooms, shop signs and weathering
  (`facade_common.gdshaderinc`); trees with photo leaf clusters and bark,
  woodland on the hills, shrubs and hedges, a quadtree LOD (`tree_lod.gd`,
  `tree_scatter.gd`); street props and landmarks with PBR materials.
- **Steam Deck:** 0.7.0 ran High at about 30 fps with drops below 20 while
  driving (the owner's son, on the Deck); Medium ran at 50+. Measured with
  `--perfsweep` on the dev PC's Intel iGPU (about 1.6× slower than the Deck),
  SDFGI cost the most, worst while moving (it re-voxelises as the camera
  moves), then PCSS soft sun, SSIL, SSR and volumetric haze. So since 0.7.1
  **High is tuned for the Deck** (SSAO at low quality, glow, the car's
  reflection probe, all materials, grass and trees; ambient warmed by
  `DayNight.WARM_BOUNCE` since nothing bounces light) and **Ultra** (new,
  PC) adds SDFGI, SSIL, SSR, volumetric haze and soft sun shadows. On the
  iGPU High went from 40–54 ms to 23–30 ms standing and from 57 ms average /
  172 ms worst to 25 / 43 ms driving. Trees are the dearest remaining family
  (up to ~10 ms there in the park). The package grew from 35 MB to 119 MB.

---

## 0c. Downtown City MegaKit (experiment, branch `experiment/quaternius-downtown-city`)

**Not approved: an experiment for the owner to evaluate (2026-10-03).** The
downtown blocks along the avenue east of the City Center spawn are built from
Quaternius' *Downtown City MegaKit* (free Standard version, CC0,
ASSET_MANIFEST.md) instead of `BuildingKit`. If the owner adopts it, these
rules replace §15 for the blocks that use it. `--legacy-downtown` builds the
old blocks for A/B; `turbo_town/dev/megakit_whole_city` (or `--megakit-city`)
puts every city block in kit buildings.

- **Direction:** pre-war Boston / New York brick-and-stone downtown: shopfront
  bases with sign bands, brick window bays, stone quoins and cornices, slate
  mansards, fire escapes, water tanks. Real 3D facade depth (recessed windows,
  pilasters, cornices) replaces windows painted by a shader.
- **Kit conventions:** metres; 2 m bays (some 4 m), 3 m floors; a wall
  module's outside face is at z = 0 facing +Z, x along the wall. Our ground
  floor is 4 m (3 m modules + a 1 m sign band). Buildings stand on the 2 m
  grid, flush with the sidewalk.
- **Pipeline** (`tools/megakit/`, never hand-edit outputs): the zip is cached
  in `build/` and SHA-256 checked; `build_megakit_textures.py` makes the
  texture arrays; `build_megakit_modules.gd` converts the glTF modules into one
  `MegaKitLibrary` (glass in front of fake interiors, interior walls and floors
  dropped; glass with nothing behind it kept as plain glass; far-LOD proxies).
- **One material** for the whole kit (`megakit.gdshader`): the kit's eight
  texture sets are slices of two texture arrays (albedo; normal XY + roughness
  + AO), each vertex says its slice (CUSTOM0), so **a building is one surface
  and one draw call.** The kit's fake bevels (corner normal on UV2) and wear
  mask (COLOR.g) are re-implemented; metallic is dropped (painted iron is
  paint, §6). Build tangent frames from screen derivatives; guard them where
  UV / UV2 barely change (constant UVs interpolate with float noise and the
  frame turns into static).
- **Colour:** a building gets one palette row (`MegaKit.PALETTES`, instance
  uniform) that recolours the kit's tint slots (brick, alt brick, trim, dark
  trim, accent, metal, flat roof). Brick and trim colours keep chroma ≤ 0.35
  (§5). Palettes: red brick + cream stone, dark brown + white, buff +
  brownstone, deep red + warm grey, painted cream, brownstone, orange-red,
  grey-brown.
- **Grammar** (`DowntownBuilding`): base (metal or stone shopfronts, or a
  masonry ground floor) + sign band; window bays fitted symmetrically, with
  pilasters on some styles; brick corners or stone quoin columns; mitred
  cornices or a slate mansard with dormers. Styles: loft, hotel, commercial,
  mansard, tenement, warehouse. Party and courtyard walls are plain brick
  quads; walls facing open ground get windows. Blocks (`DowntownBlock`):
  corner buildings with two frontages, mid-block buildings 8-20 m wide,
  sometimes a 4 m alley; heights planned first so exposed party walls get a
  faded painted sign.
- **Windows:** the kit's 2D room photos are interior mapped (one-point
  perspective); glass lets the room through by (1 − Fresnel). Ground-floor
  windows show the city's shop interior atlas, one shop per 6 m of frontage.
  At night about half the rooms and most shops are lit; shops spill a warm
  glow onto the sidewalk (`shop_light_spill.gdshader`, no real light).
- **Dressing reused from the city:** shop sign boards (facade.gdshader sign
  style), awnings and roof clutter with water tanks (street_props), the
  StreetKit lamps and signals. Fire escapes are thin boxes in the kit's
  painted-metal slice.
- **Performance:** per building a full mesh (near), a far proxy beyond 90 m
  (window modules become a backing quad + their window quads, heavy pieces
  boxes: ~1/20 of the triangles), a box occluder (occlusion culling is on),
  and on Medium / Low a shadows-only far proxy instead of full-detail shadows.
  Module arrays are decoded once and merged with C++ array ops; the downtown
  builds in ~0.35 s. Numbers: PROGRESS.md log and the experiment report.

---

## 1. Visual identity

**Pitch:** a sun-drenched coastal island town where believable cars get
gloriously smashed up. The light, materials and proportions of a polished
modern car game, with the surface noise, grime and expense stripped out.

**Pillars**

1. **Believable first, then beautiful.** Asphalt reads as asphalt, paint as
   glossy paint, concrete as concrete. Everything is the right size and lit by
   a believable sun.
2. **Clean, not detailed.** Big readable shapes with crisp bevels. Surface
   detail is subtle and large-scale. Detail goes where the camera is: the road,
   the cars, street-level facades.
3. **Light does the heavy lifting.** Strong warm sun, cool sky-lit shadows,
   aerial haze. A good lighting setup is worth more than any texture.
4. **Hero vehicles, quiet world.** The world stays calm in colour so cars (and
   crashes) pop.
5. **Crashes are the show.** Damage must read from the chase camera and feel
   satisfying, never gruesome.
6. **Runs great on a Steam Deck.** A beautiful 60 fps beats a gorgeous 35 fps.
7. **Kid-friendly.** Sunny mood, clear UI, no violence beyond bent metal. The
   main player is the owner's young son.

**Setting:** a temperate-to-subtropical coastal island. A downtown core of
stone-and-glass towers. Low-rise stucco streets toward the beach and harbour.
Conifer-covered hills and a mountain. Dirt fields, airfield, harbour,
lighthouse islet. Default weather is clear with fair-weather cumulus. Time of
day can be day, sunset, night or a cycle.

---

## 2. Reference analysis

The three direction images are stored **locally only** in
`reference images/stylized-realism/`. That folder is gitignored because the
images are other games' copyrighted art and the repo is public. **Never commit
them.** The descriptions below let these rules work without the files. Treat
the images as art direction. Don't reproduce them.

### Ref 1: coastal overpass (`ref1_coastal_overpass.jpg`)

Two cars on a curving elevated highway under a concrete overpass. Pine forest,
autumn shrubs, a misty sea with islands.

Take:
- **Hard warm sunlight with crisp, cool-tinted shadows.** The pillars cast clean
  bands across the road. Shadows give the scene its shape.
- **Strong aerial perspective.** Distance lightens and desaturates toward a
  pale blue-white haze. The far sea and islands are nearly silhouettes.
- **Honest, quiet materials.** Matte warm-grey concrete. Mid-dark asphalt with
  fine grain. Off-white lane paint and an ochre edge line.
- **Vegetation reads as masses.** Dark conifer greens with lighter sunlit tops,
  plus a few autumn ochre, rust and red accents.
- **Cars:** one saturated paint (violet), one muted metallic (mint-grey). Clear
  reflections, dark tinted glass, real stance (wheels fill the arches, low ride
  height).
- **Composition:** big, simple concrete forms and the rhythm of pillars.

Leave out: motion blur, photoreal texture density, and recognisable real car
models.

### Ref 2: coastal city at golden hour (`ref2_coastal_city_golden_hour.jpg`)

A red sports car at a tropical downtown intersection. Cream towers, salmon
low-rise buildings, palms, flowering trees, neon signs, street lamps, a wet road.

Take:
- **A warm golden key light** with a soft glow toward the sun. The sky goes from
  warm on the sun side to clear blue opposite. This is our sunset look.
- **Palette:** warm creams, beiges, salmon, terracotta and muted pinks against
  lush greens and a deep blue sky. Saturation comes from the neon, the flowers
  and the hero car.
- **Facade grammar:** towers with repeated window bays and a distinctive crown.
  Ground floors with shopfronts, awnings and signs. Dense street furniture
  (lamps, mailboxes, bins, hydrants).
- **Layered vegetation:** broadleaf canopies, palms, red flowering trees,
  banana plants.

Leave out: wet road and puddle reflections (they need SSR or planar
reflections), the two-times-of-day key-art trick, heavy bloom, and real-brand
signage. We invent names.

### Ref 3: downtown hood cam with HUD (`ref3_downtown_hood_cam_hud.jpg`)

A hood-camera view down a stone-and-glass street, with a police car, a red
supercar and a translucent mobile-style HUD.

Take:
- **Downtown materials:** pale neoclassical stone, dark glass curtain walls with
  warm-lit interiors, black cast-iron double lamp posts, bollards, kiosks.
- **Bright overcast sky with a strong sun glow.** Lighting can be soft without
  losing form.
- **HUD language:** translucent round controls with thin white icons, a round
  minimap, and an arc-gauge speedometer with a big digital speed and the gear.
  This matches our existing layout: minimap bottom-left, speedometer
  bottom-right.
- **Streets lined with parked cars** in realistic, mostly neutral paints.

Leave out: touch controls, the dashboard-occluded view, recognisable real car
designs, and haze from bloom.

### What all three share (the core of the style)

- Correct real-world proportions and scale.
- One dominant warm light with cool sky fill, and readable shadows.
- Aerial haze in the distance.
- Materials told apart by **value and roughness**, not by noise.
- A neutral world with a saturated hero car.

### Superseded references

The older loose images directly in `reference images/` were the v0.1 toy-style
direction: a mega-ramp stunt game with a blue muscle car, a cartoon desert
crash, and a low-poly city with a "HOT PIZZA" billboard. **Don't use them for
style.** The stunt park's playful content can stay. Its art style follows this
bible.

---

## 3. Where the game is today (legacy baseline)

As of v0.3.1 (2026-10-01), the game used a bright toy low-poly style. Step 1
of the migration (§31: lighting, atmosphere and palette) and step 4 (the whole
vehicle fleet) landed on `dev` the same day; those rows describe the game
after them. The environment upgrade (steps 3, 6 and 7 together, §31) was
previewed in a small area and, once the owner approved it (2026-10-01), rolled
out to the whole island: roads, city blocks, landmarks, stunt park, props,
trees, terrain and sea. The legacy builders, shaders and materials are gone.

| Area | Today | Target |
|---|---|---|
| Geometry | **Migrated.** World geometry uses `MeshBuilder`'s shape helpers (`add_bevel_box`, `add_lathe`, `add_sweep`, `add_quad_ex`) with per-vertex normals: bevelled and smooth, flat faces flat. Kits: `BuildingKit`, `StreetKit`, `TreeKit`. Vehicles (step 4): smooth loft bodies from `body_kit.py`. | Smooth shading with bevels. Deformation-ready vehicle topology. |
| Textures | Generated by `tools/textures/make_textures.py`: one ground detail texture (grain, blotches, cracks), cloud noise, a water ripple normal map, three leaf atlases (broadleaf, conifer, palm). Everything else is vertex colour or procedural shaders. | Stay procedural-first. Add small generated detail textures where they pay off (§8). |
| Palette | **Migrated (step 1).** World colours follow §5 and live in `ArtPalette` (`scripts/world/art_palette.gd`). Vehicle paints **migrated (step 4)**: `PaintPalette` (§5). | Naturalistic palette (§5). |
| Lighting | **Migrated (step 1).** Warm sun, cool ambient, AgX tonemap, aerial fog, 15:00 day preset (§9, §11). | More sun/shadow contrast, cooler shadows, more aerial haze. |
| Sky | **Migrated.** Colours from step 1; soft lit cumulus and cirrus drawn by `sky.gdshader` (the faceted mesh clouds are gone). | A paler, hazier horizon and soft clouds. |
| World | **Migrated (environment upgrade, 2026-10-01).** Roads, junctions, kerbs, barriers and bridges (§16), buildings (§15), street furniture, signs, landmarks and stunt props (§17), trees (§18), terrain and sea (§19). | Later: guardrails (§32), more street furniture variety, wet weather only if asked. |
| Vehicles | **All eight migrated (step 4)**, then the **vehicle realism pass** (2026-10-02): the vehicle shaders (`assets/shaders/vehicle/`: car paint, glass, lamps, trim, tyres), real reflections on the player's car (`VehicleReflection`), amber indicators and traffic turn signals / hazards, brake calipers, grilles with depth, road grime, a contact shadow. Loft bodies from `body_kit.py` (one `make_<vehicle>.py` each), 5–6k deformable vertices, four wheel types. The sports car (90s/early-2000s Japanese coupé) is the quality baseline. Every vehicle has see-through glass and an interior (the buggy an open cockpit) except the bus, which has opaque tinted glass. | §12–13. Later: LOD tuning, Damage 3.0 crumple stiffness (§14). |
| Damage | Vertex dents (smoothstep falloff, bent normals); a dent only touches the vertices it moves. **Paint damage layer** (scuff → primer → bare metal, vertex colours, §14) round dents and along sliding scrapes. Bumpers and spoiler fall off. Lights break (dark housing, lens shards); glass cracks in a procedural spiderweb at the window nearest the hit. Smoke and sparks. | Crumple stiffness and structure behind lost parts (§14). |
| UI | Dark navy rounded panels, yellow accent, outlined default font, built in code with `UiKit`. | Keep the colours and layout. Add a real font, a type scale and icons (§20–22). |

Treat legacy assets as placeholders. Match them when you add to a family that
hasn't been migrated yet. Never carry their palette or shading into a family
that has been.

---

## 4. Stylization vs realism: the dial

**Fidelity anchor:** light, materials and proportions close to Ref 1. Geometric
detail and texture density like a clean mid-poly game. Overall, roughly halfway
between today's game and Ref 1, leaning toward Ref 1 in lighting.

| Keep realistic | Stylize (simplify or idealize) | Never |
|---|---|---|
| Scale and proportions of vehicles, roads, lanes, kerbs, doors, floors | Surface detail: clean, low noise, wear only at large scale | Photogrammetry, scanned textures, 4K maps |
| Sun and sky behaviour: direction, shadows, ambient, PBR response | Shapes: slightly simplified, generous bevels, crisp silhouettes | Faceted low-poly organic shapes |
| Material identity: asphalt, concrete, paint, glass, chrome, rubber | Colour: a hand-picked, harmonious, slightly warm palette | Candy/pastel large surfaces, pure primaries on walls |
| Mostly neutral traffic colours (like real streets) | Vegetation as clustered canopies, not individual leaves | Toon/cel shading, outlines, posterization |
| Visible mechanics: suspension travel, wheels filling arches, brake discs | Weather: perfect, clean, hazy-bright | Wet-road reflections, ray tracing, real-time GI |
| Damage where you hit: dents, crumpled ends, parts coming off | Damage a bit broader and deeper than real, sparks a bit brighter | Gore, injured people, scary content |
| Real conventions for road markings and signs | Invented brands and place names, playful but plausible | Real brands, logos, trademarked car designs |

**Allowed exaggerations (the only ones):**
- Vehicle lights, grilles, wheels and mirrors up to 10–15% larger, for
  readability.
- Sports car about 5% lower and wider than average. The monster truck is huge
  by design.
- Dents somewhat deeper and broader than a real crash at that speed. Sparks
  brighter and more plentiful.
- Road marking contrast slightly higher than real, for readability at speed.
- Skies cleaner and colour harmony tidier than real.

**Three quick tests for any screenshot:**
- **Squint test.** Blurred, it should read as a real place in good weather:
  sky, haze, sunlit and shadowed planes, road, cars.
- **Toy test.** If it could pass for a mobile toy game (faceted shapes, candy
  colours, outlines, oversized everything), it's too stylized.
- **Budget test.** If it needs ray tracing, photogrammetry, 4K textures or
  per-pixel GI to look right, it's too realistic for us.

---

## 5. Colour palette

Values are sRGB hex, plus the Godot `Color()` floats in sRGB space (the same
space as `Color()` in GDScript, material `albedo_color`, and `MeshBuilder`
vertex colours). Vary each instance by about ±4% in value and ±0.02 in hue so
repeats don't look stamped. **Don't invent new base colours: add them here
first.** In code, the world's base colours live in `ArtPalette`
(`scripts/world/art_palette.gd`); builders read it, and small accents stay
inline.

**Rules**

- **Large surfaces** (terrain, walls, roads, sea, big props): chroma ≤ 0.35.
  Chroma here means the highest sRGB channel minus the lowest, on a 0–1 scale.
  (Before step 1 the pastel buildings were 0.36–0.67 and the grass 0.39.)
- **Accents** (vehicles, signs, flowers, markings, UI): chroma up to 0.90.
- **Gameplay markers** (race gates, start circles, guide arrow) may use
  saturated, emissive colours. They're UI placed in 3D.
- **Albedo range:** every channel between 0.11 and 0.94. The darkest material
  is tyre rubber (~0.11), the brightest is road paint or white trim (~0.91).
  Anything brighter than white must come from emission.
- **Warm bias:** neutrals lean warm (R ≥ B). Exceptions: glass, steel, sky,
  shadows, night.
- **Target on-screen values at midday:** sunlit concrete 0.75–0.85, shadowed
  asphalt 0.14–0.20. Nothing large clips to white in daylight except the sun
  and specular glints.

### Ground and roads

| Name | Hex | Godot `Color` | Use |
|---|---|---|---|
| asphalt | `#46474A` | `(0.275, 0.278, 0.290)` | road base (`ArtPalette.ASPHALT`, road shaders) |
| asphalt_dark | `#393A3D` | `(0.224, 0.227, 0.239)` | repairs, fresh patches, wheel paths |
| asphalt_worn | `#5A5B5D` | `(0.353, 0.357, 0.365)` | worn, sun-bleached patches |
| paint_white | `#E4E2DA` | `(0.894, 0.886, 0.855)` | lane lines, zebra crossings |
| paint_yellow | `#D9A421` | `(0.851, 0.643, 0.129)` | centre and edge lines |
| concrete | `#B4B0A7` | `(0.706, 0.690, 0.655)` | barriers, decks, pillars |
| concrete_stained | `#8E8A82` | `(0.557, 0.541, 0.510)` | bases, drip streaks, joints |
| sidewalk | `#BDB8AE` | `(0.741, 0.722, 0.682)` | paving |
| curb | `#A8A39A` | `(0.659, 0.639, 0.604)` | kerbs |
| grass | `#5E7F3A` | `(0.369, 0.498, 0.227)` | lawns, lowland (`ArtPalette.LAWN`; terrain blends `GRASS_DARK`↔`GRASS_LIGHT`) |
| grass_dry | `#8A8A4A` | `(0.541, 0.541, 0.290)` | hills, fields |
| dirt | `#8C6A48` | `(0.549, 0.416, 0.282)` | trails, dirt fields |
| sand | `#D8C59A` | `(0.847, 0.773, 0.604)` | beach |
| rock | `#8A8580` | `(0.541, 0.522, 0.502)` | cliffs, boulders |

### Vegetation and water

| Name | Hex | Godot `Color` | Use |
|---|---|---|---|
| conifer | `#2F4A2E` | `(0.184, 0.290, 0.180)` | pines and firs (body) |
| broadleaf | `#4C6E2E` | `(0.298, 0.431, 0.180)` | street and park trees |
| foliage_lit | `#7C9A45` | `(0.486, 0.604, 0.271)` | sunlit canopy tops |
| palm | `#5E7A34` | `(0.369, 0.478, 0.204)` | palm fronds |
| autumn_ochre | `#C9A23A` | `(0.788, 0.635, 0.227)` | accent shrubs (≤ 10% of trees) |
| autumn_rust | `#B5582C` | `(0.710, 0.345, 0.173)` | accent shrubs |
| flower_red | `#B8322A` | `(0.722, 0.196, 0.165)` | flowering trees and beds (sparingly) |
| bark | `#5A4636` | `(0.353, 0.275, 0.212)` | trunks |
| sea_deep | `#1E4E6E` | `(0.118, 0.306, 0.431)` | open sea |
| sea_shallow | `#3F8F95` | `(0.247, 0.561, 0.584)` | near shore |

### Buildings

| Name | Hex | Godot `Color` | Use |
|---|---|---|---|
| stucco_warm | `#D8CCB4` | `(0.847, 0.800, 0.706)` | low-rise plaster, towers |
| limestone | `#C8B79A` | `(0.784, 0.718, 0.604)` | downtown stone bases |
| terracotta | `#C98A70` | `(0.788, 0.541, 0.439)` | coastal plaster accent |
| brick | `#8E4A3A` | `(0.557, 0.290, 0.227)` | older blocks |
| seaglass | `#8FB5AE` | `(0.561, 0.710, 0.682)` | coastal plaster accent |
| pale_yellow | `#E2CF9A` | `(0.886, 0.812, 0.604)` | coastal plaster |
| curtain_glass | `#26323C` | `(0.149, 0.196, 0.235)` | glass towers |
| mullion | `#3A3F44` | `(0.227, 0.247, 0.267)` | curtain wall frames |
| trim_white | `#E8E4DA` | `(0.910, 0.894, 0.855)` | window frames, cornices |
| roof | `#6E6C68` | `(0.431, 0.424, 0.408)` | flat roofs, membranes |

The new building kit picks walls per facade style from `ArtPalette`:
`STUCCO_WALLS` (stucco_warm, terracotta, seaglass, pale_yellow, off-white
`#E0DBCF`, dusty rose `#CC9E94`), `LIMESTONE_WALLS` (limestone, pale stone
`#D1C7B3`, concrete grey `#B3ADA3`), `BRICK_WALLS` (brick, dark brick
`#784536`, buff brick `#B39470`), `MULLIONS` (mullion, silver `#8C9199`) and
`PANEL_WALLS` (white panel `#DBD9CF`, grey panel `#A8A399`, slate `#85949F`),
each varied ±4% in value. Shop fascias and awnings use the muted
`SHOP_ACCENTS` (oxblood `#8C332B`, navy `#2E4D73`, bottle green `#38614A`,
ochre `#B88533`, charcoal `#47474D`); fascias are those darkened 45%.

### Street furniture (`StreetKit`)

| Name | Godot `Color` | Use |
|---|---|---|
| iron | `(0.13, 0.135, 0.14)` | lamp posts, bollards, bench frames |
| signal grey | `(0.2, 0.21, 0.2)` | traffic signal poles and arms |
| hazard yellow | `(0.91, 0.71, 0.12)` | signal backplate borders, push buttons |
| hydrant red | `(0.72, 0.14, 0.1)` | hydrants |
| bin green | `(0.16, 0.24, 0.2)` | litter bins |

### Sky keys (in `DayNight.KEYS` since step 1)

| Key | Before (v0.3.1) | Now |
|---|---|---|
| Day zenith | `(0.16, 0.45, 0.92)` | `#3D7CC9` `(0.239, 0.486, 0.788)` |
| Day horizon / fog | `(0.62, 0.82, 0.98)` | `#D6E3EC` `(0.839, 0.890, 0.925)`: paler, hazier |
| Sunset zenith | `(0.25, 0.28, 0.58)` | `#3A4A8C` `(0.227, 0.290, 0.549)` |
| Sunset horizon | `(1.0, 0.55, 0.32)` | `#F2A66B` `(0.949, 0.651, 0.420)` |
| Night zenith | `(0.01, 0.02, 0.07)` | `#070B1A` `(0.027, 0.043, 0.102)` |
| Night horizon | `(0.05, 0.08, 0.18)` | `#1A2238` `(0.102, 0.133, 0.220)`: a little brighter, for readability |

### Light colours

| Light | Hex | Godot `Color` |
|---|---|---|
| Warm street lamp (~3000 K) | `#FFE2B0` | `(1.000, 0.886, 0.690)` |
| Cool LED (highway, airfield) | `#E8F0FF` | `(0.910, 0.941, 1.000)` |
| Headlight | `#FFF4E0` | `(1.000, 0.957, 0.878)` |
| Lit window | `#FFAD5C` | `(1.0, 0.68, 0.36)` warm rooms; about 15% are cool-white offices `(0.8, 0.88, 1.0)` (`facade.gdshader`) |

### Vehicle paints

**Source of truth: `scripts/vehicle/paint_palette.gd` (`PaintPalette`).** Owner
decision (2026-10-01): garage colours are believable car paints plus a few
fun brighter ones; traffic is mostly white, black, grey and silver, with blue
and red fairly common and other colours rare.

- **Garage** (`PaintPalette.GARAGE`, 12 swatches, six per row): red, sunset
  orange, yellow, lime, racing green, teal, bright blue, midnight purple,
  pink, white, silver, graphite. `GARAGE_METALLIC` marks the metallic ones
  (green, teal, blue, purple, silver, graphite). Saves from before snap to the
  closest new colour when loaded.
- **Traffic** (`PaintPalette.TRAFFIC`, weighted): white 22, black 16,
  silver 16, dark grey 8, grey 6, blue 5, navy 4, red 5, dark red 3, dark
  green 3, champagne 3, brown 2, then yellow, orange, teal, purple and lime
  at 0.5–1.5 each. Vehicles without their own `paint_palette` use this mix,
  and so do the parked-car props (`traffic_paint`).
- **Per-type palettes** (uniform pick, on the scene's `Body` node): vans are
  mostly white; delivery truck cabs and buses carry fleet liveries.
- **Finish:** `VehicleBodyVisual.paint_material()` looks up the metallic
  amount by colour and always adds the clear coat (§13).

### UI

Keep the existing `UiKit` values. They already fit.

| Role | Godot `Color` | Where today |
|---|---|---|
| Accent / focus / primary | `(1.0, 0.84, 0.29)` | `UiKit.ACCENT` |
| Panel | `(0.05, 0.08, 0.15, 0.72–0.88)` | `UiKit.PANEL_BG`, HUD panels |
| Text outline | `(0.05, 0.08, 0.2)` | `UiKit.OUTLINE` |
| Text on accent | `(0.08, 0.1, 0.18)` | `UiKit.DARK_TEXT` |
| Info / speed | `(0.25, 0.8, 1.0)` | speedometer band |
| Danger / redline / needle | `(1.0, 0.3, 0.2)` | speedometer |
| Go / success | `(0.3, 1.0, 0.45)` | race start circle, "GO!" |
| Drift mode | `(1.0, 0.5, 0.9)` | speedometer "DRIFT" |
| Medal gold / silver / bronze | `#FFC93C` / `#C9D1D9` / `#CD7F4A` | proposed |

---

## 6. Material / PBR guidelines

Use the metallic/roughness workflow: `StandardMaterial3D`, `ORMMaterial3D`, or
spatial shaders.

| Material | Albedo (§5) | Roughness | Metallic | Notes |
|---|---|---|---|---|
| Asphalt | asphalt | 0.85–0.95 | 0 | `road_surface.gdshader`: 0.9, wheel paths 0.84, crack sealing 0.55, markings 0.66 |
| Concrete | concrete | 0.85–0.9 | 0 | |
| Paving / kerb | sidewalk / curb | 0.85 | 0 | |
| Stucco / plaster | building palette | 0.9 | 0 | |
| Limestone | limestone | 0.8 | 0 | |
| Brick | brick | 0.9 | 0 | mortar lines lighter, about +15% value |
| Building window glass | dark blue-grey | 0.05–0.15 | 0 | `facade.gdshader`: 0.05 |
| Curtain wall glass | curtain_glass | 0.05–0.1 | 0 | |
| Painted metal (poles, signs) | per object | 0.45–0.6 | 0 | paint is not metal |
| Galvanised steel (guardrails) | `#A7ABAE` | 0.4–0.5 | 1 | |
| Corrugated / roof metal | `#8E9296` | 0.45–0.6 | 1 | |
| Plastic (cones, barrels, bins) | hazard colours | 0.5–0.65 | 0 | |
| Wood | warm browns | 0.75–0.9 | 0 | |
| Rubber / tyre | `#1C1C1E` | 0.85–0.95 | 0 | |
| Grass / foliage | vegetation palette | 0.8–0.95 | 0 | specular 0.25–0.35 |
| Bark / rock / sand | palette | 0.85–0.95 | 0 | |
| Water | sea palette | 0.02–0.1 | 0 | `water.gdshader`: roughness 0.08 |
| Car paint | paint palette | 0.13 (solid) / 0.2 (metallic) | 0 (solid) / 0.35–0.6 (metallic) | clear coat 0.6; `car_paint.gdshader` (§13) |
| Chrome | `#D9DBDE` | 0.08–0.15 | 1 | sparingly |
| Aluminium rim | `#B8BBBF` | 0.3–0.4 | 1 | |
| Vehicle glass | `#1E2833` | 0.04 | 0 | `vehicle_glass.gdshader`: alpha 0.7 → 0.96 with Fresnel |
| Black trim plastic | `#222326` | 0.55–0.7 | 0 | |
| Light lens | white / red / amber | 0.05–0.15 | 0 | emission per §13 |

**Rules**

- **Metallic is binary:** 0 for non-metals, 1 for bare metal and chrome. The
  only in-between values are 0.4–0.6 for metallic car paint, as a stand-in for
  flake. Glass and water are not metallic.
- **Roughness carries material identity.** Two materials with the same colour
  should still read differently through roughness.
- **Specular:** leave at the default 0.5, except foliage and grass (0.25–0.35)
  so plants don't look shiny.
- **Vertex colour as albedo:** world meshes built with `MeshBuilder` use vertex
  colour with `vertex_color_use_as_albedo = true` and
  `vertex_color_is_srgb = true` (see `assets/materials/*.tres`). Custom shaders
  receive `COLOR` raw in sRGB and must convert it (`srgb_to_linear` in
  `world_common.gdshaderinc`). Uniforms with the `source_color` hint are converted
  automatically.
- **Vertex colour alpha is a flag channel** in the world shaders: windows on or
  material classes in `street_props.gdshader`, deck sides in `road_surface.gdshader`. Document any new
  use in the shader's header comment.
- **Ambient occlusion:** bake it into vertex colour (world) or into an AO/ORM
  texture (models). Darken contact areas: wall bases, under props, wheel wells,
  canopy undersides. It's free and grounds everything.
- **No lighting baked into albedo:** no painted highlights, no sun direction, no
  cast shadows. Albedo should look flat-lit.
- **Colour variation without new materials:** use vertex colour, `instance
  uniform` parameters in a shared shader, or MultiMesh instance colours. Never
  one material per colour.
- **Emission** is only for light sources: lamps, vehicle lights, windows at
  night, neon, screens, sparks, gameplay markers. Daytime emission energy stays
  ≤ 1.0, except brake lights and lit headlights (§13).
- **Transparency:** avoid it. Use alpha scissor for foliage cards and fences.
  Use alpha blend only for vehicle glass, particles, water and UI.
- **Few materials:** reuse the shared materials in `assets/materials/`. Today
  the whole world uses about 12 shared materials, and that spirit should stay.
  Vehicle bodies get at most 10 surfaces.

---

## 7. Shaders

**Existing shaders** (`assets/shaders/`):

| Shader | What it does | Conventions |
|---|---|---|
| `water.gdshader` | sea: two scrolling ripple normal maps, turquoise shallows and a foam band from a shoreline depth mask baked at startup | `shore` texture and `shore_rect` set by `NatureBuilder`; no depth-buffer reads |
| `minimap.gdshader` | round, heading-up minimap (canvas_item) | |
| `world_common.gdshaderinc` | shared include for the new world shaders: global uniforms, `srgb_to_linear`, stable hashes, `band`/`grid_line` (antialiased lines that fade to their average), `detail_fade` | the ground detail texture tiles every 4 m in world space |
| `road_surface.gdshader` | asphalt: grain, wear, wheel paths, repairs, crack sealing, chipped paint, gutters, drains, manholes, stop lines, bridge expansion joints; concrete deck sides | `UV.x` = metres across (0 = centre), `UV.y` = metres along, `UV2` = stop line positions, `COLOR.b < 0.5` = bridge deck, `COLOR.a < 0.5` = deck side; parameters in `materials/env/road_*.tres` |
| `junction.gdshader` | junction square: the same asphalt, worn zebras, an oily middle | `UV` = metres from the centre, `COLOR.rgba` = road on the N, E, S, W sides |
| `paving.gdshader` | sidewalks, kerb stones, plaza tiles, car park asphalt, lawns | `COLOR.a` = surface in steps of 0.25 (see the header) |
| `concrete.gdshader` | barriers, piers, girders: pores, blotches, drip streaks | `COLOR.a`: 1 cast (formwork lines), 0.5 barrier (joints every 6 m) |
| `facade.gdshader` | building walls with windows: shopfronts, reveals that tilt the normal, sills, brick and ashlar patterns, curtain walls, lit rooms at night | `UV.x` = bays, `UV.y` = metres up, `UV2` = (seed, style); see the header |
| `street_props.gdshader` | every StreetKit prop, roof clutter, awnings | `COLOR.a` = material class (/15); `instance uniform signal` lights a signal lens |
| `foliage.gdshader` | TreeKit trees: alpha-scissor leaf cards, solid cores, bark, wind sway | `COLOR.a`: 1 card, 0.5 core, 0 bark |
| `terrain.gdshader` | terrain: grass clumps, dry and lush patches, rock with strata on slopes | vertex colour from `TerrainBuilder` |
| `sky.gdshader` | sky gradient, sun/moon disk, soft lit cumulus and cirrus | colours set by `DayNight`; no `TIME`, so radiance only updates on change |
| `vehicle/car_paint.gdshader` | car paint: gloss + clear coat, metallic flop and close-up flakes, toned-down ground reflections, road grime (`dirt`), the damage layer | object space (origin at wheel-centre height); vertex colour = damage mask, stored inverted (G = 1 − scrape, B = 1 − paint loss), see §14 |
| `vehicle/vehicle_glass.gdshader`, `vehicle_glass_opaque.gdshader` (+ `.gdshaderinc`) | tinted glass with Fresnel opacity, procedural crack web round `crack_center` | the opaque one is the bus's |
| `vehicle/vehicle_lamp.gdshader` | `Headlight`, `TailLight`, `ReverseLight`: lens over chrome reflector, ribs / projector ring, emission by kind and state; reads the global `night` | UV0 kind tags from `body_kit` (§13); per-car state uniforms set by `VehicleBodyVisual` |
| `vehicle/vehicle_trim.gdshader` | black trim; honeycomb grilles and slatted grilles with dark holes | UV0 kind tags (§13) |
| `vehicle/vehicle_tyre.gdshader` | tread vs sidewall by object-space radius, moulded band, dust | wheel models are 0.37 m round X |
| `vehicle/vehicle_interior.gdshader` | cabins: light headliner (faces pointing down), dark fabric seats/floor (up), satin plastic (sideways), fine weave up close | object-space normals of the `Interior` faces |
| `vehicle/contact_shadow.gdshader` | soft multiply-blend patch under each vehicle (§10) | `instance uniform strength` |
| `vehicle/vehicle_common.gdshaderinc` | stable hashes, value noise, `vh_step` (fwidth-antialiased steps), `vh_kind` (decodes the UV tags) | |

**Rules**

1. **Header comment is mandatory.** Document the UV, COLOR and uniform
   conventions, as the existing shaders do.
2. **Extend shared shaders, don't fork them** per object. Vary per object
   through vertex colour, `instance uniform`, or a few shared material
   variants.
3. **Antialias procedural lines with `fwidth`** (see `line_mask` in
   `road_surface.gdshader`; `band` and `grid_line` in `world_common.gdshaderinc`),
   and fade high-frequency detail with distance (`detail_fade`, and the `far`
   fade in `facade.gdshader`). Nothing may shimmer at 1280×800. **Hash only stable
   inputs:** round an interpolated vertex colour or UV before hashing it (see
   `seed` in `facade.gdshader`). Otherwise the hash turns tiny per-pixel
   float wobble into TV-static speckles.
4. **Fragment budget for world surfaces:** ≤ 4 texture samples (≤ 6 on
   High-only paths). No loops longer than about 8 iterations. No `discard`
   except alpha-scissor foliage. No `SCREEN_TEXTURE` or `DEPTH_TEXTURE` reads
   (the one possible exception is water on High, if justified).
5. **Global state:** global shader uniforms (Project Settings → Shader
   Globals): `night` (set by `DayNight`) and `quality` (by
   `GraphicsQuality.apply`). The world shaders read them through
   `world_common.gdshaderinc`.
6. **Quality-aware:** on Low (`quality == 0`) the new world shaders skip their
   fine detail samples, and foliage stops swaying.
7. **Lit, not unshaded.** World surfaces use normal lighting. Use `unshaded`
   only for the sky, stars, UI, sparks and emissive markers. Today tyre smoke
   and dust are unshaded, so they glow at night. Fix that when touching effects
   (§23).
8. **Break up repetition** with world-space macro noise (like the patch hash in
   `road_surface.gdshader`). Use triplanar mapping for terrain cliffs and rocks.
9. **No** toon ramps, outlines or inverted hulls, posterization, cel shading,
   dithering looks, or fake rim-glow.
10. **Use `StandardMaterial3D` when no custom logic is needed.** Each distinct
    feature combination compiles a new shader variant on first use, which can
    hitch on the Deck. Reuse materials, and at runtime duplicate an existing
    material and change its parameters (as `VehicleBodyVisual` does) rather
    than building new feature combinations.
11. **Target shaders** to build when a task asks for them: car paint (clearcoat,
    optional noise flake, damage-layer blend), sky with cloud layers, terrain
    splat with triplanar cliffs, foliage with wind sway and spherical normals,
    and water with sky fresnel, sun glints and shore foam from a baked mask.

---

## 8. Texture and detail guidelines

**Procedural and vertex colour come first.** Use textures only where procedural
can't deliver: brick or paving patterns up close, tyre sidewalls, light lenses,
signs and graphics, leaf cards.

**Sources, in order of preference**

1. Procedural in a shader.
2. Generated by a committed script (Python/NumPy, a Blender bake, or a Godot
   `@tool` script) in `tools/textures/`, writing into `assets/textures/`. Commit
   both. Use fixed seeds so re-running reproduces the texture exactly.
3. CC0 libraries such as ambientCG or Poly Haven. Downloading needs the
   owner's OK first. Record the source URL and licence in `assets/CREDITS.md`,
   downscale to budget, and use only de-lit albedo.
4. Never use images of unknown licence, photos with baked shadows, or anything
   that shows real brands.

**Budgets**

| Use | Max size | Texel density |
|---|---|---|
| Vehicle shared detail atlas (lenses, grilles, tyre sidewall, badges) | 1024² | ~512 px/m on the details |
| Road / sidewalk tiling detail | 512² per 2–4 m tile | 128–256 px/m |
| Building facade tiles and trims | 512–1024² | ~128 px/m |
| Terrain detail (grass, dirt, rock, sand) | 512² at 4 m tiles | 128 px/m, plus macro variation |
| Foliage leaf atlas | 1024² | |
| Shared props atlas | 1024² | ~256 px/m |
| UI icons | SVG | |

- **Hard cap 2048²**, and only for atlases with a reason. No 4K.
- **Total texture memory ≤ 256 MB.**
- **Formats:** commit lossless PNG (sRGB for colour, linear for data). Godot
  imports them VRAM Compressed (BPTC/S3TC; the export preset enables
  `s3tc_bptc`) with mipmaps. Import normal maps as Normal Map. Godot uses the
  OpenGL (Y+) convention, the same as Blender bakes.
- **Packing:** ORM, meaning R = AO, G = roughness, B = metallic, used with
  `ORMMaterial3D`.
- **Naming:** `<family>_<thing>_<map>.png`, where map is `albedo`, `orm`,
  `normal`, `emission` or `mask`. Example: `road_asphalt_albedo.png`.
- **Tiling must never show.** Use world-space macro variation, random rotation
  or offset per instance, or two scales blended.

**Where detail goes, in priority order:** (1) the player vehicle, (2) the road
surface within ~30 m of the camera, (3) traffic vehicles, (4) street-level
facades (first two floors) and street furniture, (5) near vegetation. Anything
else gets a good silhouette and the right colour, nothing more.

---

## 9. Lighting

**Single source of truth:** `scripts/world/day_night.gd` (`KEYS`: sky top,
horizon, light colour and energy, ambient colour and energy, fog colour, per
hour) plus `scenes/world/world.tscn` (Environment and Sun). Change lighting
there. Never add lights to fix the look of a level.

**Principles** (from Refs 1 and 2). Shadowed asphalt at midday should read
about 0.15–0.25 sRGB on screen, neutral with a slight cool tint, never navy.

- **One dominant warm key** (the sun) plus cool sky fill. At midday, sunlit
  areas are about 3–4× brighter than shadows. Shadows are clearly readable but
  never black.
- **Warm light, cool shadows**, achieved with a warm sun colour and blue-ish
  ambient. Never by tinting albedo.
- **Presets** (`DayNight.PRESET_HOURS`): day at 15:00, which is the default
  (moved from 14:00 in step 1: a lower sun gives longer shadows); sunset at
  17:45, the hero look (Ref 2); night at 23:00.
- **Night is moonlit blue, not black.** Roads and buildings stay readable for a
  kid. Warm pools under street lamps, lit windows, headlights.

**Key values** (in `DayNight.KEYS` since step 1; tuned by screenshot):

| Key | Before (v0.3.1) | Now |
|---|---|---|
| Day sun | `(1.0, 0.97, 0.9)` × 1.25 | `(1.0, 0.95, 0.86)` × 1.4 |
| Day ambient | `(0.8, 0.88, 1.0)` × 0.9 | `(0.86, 0.88, 0.92)` × 0.9 with sky contribution 0.2 (environment upgrade; step 1's `(0.62, 0.74, 0.95)` × 0.65 at 0.5 turned shadowed asphalt navy) |
| Day fog | `(0.66, 0.8, 0.96)` | `(0.8, 0.86, 0.92)` |
| Sunset sun | `(1.0, 0.55, 0.3)` × 1.0 | `(1.0, 0.6, 0.35)` × 1.2 |
| Sunset ambient | `(0.9, 0.65, 0.55)` × 0.6 | `(0.55, 0.55, 0.75)` × 0.5 (warm key, cool violet shadows) |
| Night moon | `(0.55, 0.65, 1.0)` × 0.22 | unchanged |
| Night ambient | `(0.35, 0.42, 0.7)` × 0.3 | `(0.3, 0.38, 0.62)` × 0.35 |

The ground half of the sky (what paint and glass reflect below the horizon) is
an earthy `DayNight.GROUND_BOUNCE`, scaled by the light's energy.

**Environment target (High)**

- **Tonemap: AgX** with `tonemap_agx_contrast` 1.4 (chosen over Filmic in
  step 1: same sunny look, but bright emissives and sunsets keep their hue).
- **Exposure** 1.0. Sunlit concrete should read about 0.75–0.85 sRGB on screen.
- **`adjustment_saturation` 1.1.** This offsets AgX's own desaturation; the
  result is still far calmer than the old 1.15 with Filmic. If a global grade
  is needed, use one 3D LUT through `adjustment_color_correction`, generated
  by a script.
- **Glow** on Medium and High only (as today): intensity 0.3–0.5, HDR threshold
  ≥ 1.0, so only emissives, sun glints and sparks bloom.
- **SSAO** on High only (as today). Baked AO everywhere.
- **Reflections:** sky radiance by default. Up to 4 `ReflectionProbe`s with
  `UPDATE_ONCE` may cover the city core on Medium/High for paint and glass
  reflections. Never `UPDATE_ALWAYS`. The project's reflection atlas holds 4
  (`rendering/reflections/reflection_atlas/reflection_count`).
- **The player's car reflects its real surroundings** on High
  (`VehicleReflection`, owned by `Game._fit_reflection`): one `UPDATE_ONCE`
  probe that is re-centred on the car only after it has driven 20 m and at
  most every 1.2 s (Godot re-renders a ONCE probe when it moves, one cube
  face per frame), drawing only the nearest 90 m. 44 × 16 × 44 m box,
  captures layer 1 only (the world,
  not cars: every vehicle mesh is on visual layer 2, `Vehicle.VISUAL_LAYER`;
  wheels on layer 3, `WHEEL_LAYER`, so alloy rims keep the bright sky),
  `reflection_mask` = vehicles only (roads and buildings keep their sky
  reflections), no shadows, `mesh_lod_threshold` 8, ambient off (the probe's
  captured street is far darker than the scene's flat ambient). Traffic that
  drives through the box gets the same reflections. Medium and Low: sky
  only (each capture costs extra draw calls for a few frames, see §27).
- **Off:** SDFGI, VoxelGI, LightmapGI (the world is generated at runtime),
  SSIL, SSR, volumetric fog, and DOF or motion blur during gameplay.

**Local lights**

- Only lights that physically exist in the world: street lamps (`OmniLight3D`,
  16 m range, distance fade starting at 70 m over 25 m, as today), vehicle
  headlights (`SpotLight3D`, 55 m), the lighthouse beam, landmark lights.
- Every night light is a `NightLight` (group `night_lights`) or owned by a
  system with a Low fallback: on Low the lamp head glows but there's no real
  light (as today).
- **No shadows on omni or spot lights.**
- **≤ 16 visible local lights in any view.**
- Use the colours from §5 (warm lamps, cool LED, headlights, windows). Far away,
  emissive surfaces stand in for real lights.

**Garage and menus:** the garage preview has its own studio lighting in its own
World3D (`vehicle_picker.gd`: key 1.4, fill 0.4, ambient 0.75, AgX 1.4,
saturation 1.1, matching the world). Vehicles
must look the same there as in the world: same paint materials, similar
exposure, same tonemapper.

---

## 10. Shadows

- **Only the sun or moon** (`DirectionalLight3D`) casts shadows. The per-quality
  settings live in `GraphicsQuality.apply`: 2048 or 4096 atlas, 2 or 4 splits,
  140/200/260 m distance, very-low/low/medium soft filter.
- **Crisp near the camera** (Ref 1's pillar shadows): keep the first split small
  (today 0.06 of max distance), PCF soft filter low or medium, `shadow_blur`
  ≤ 1.5.
- **Every vehicle and large prop casts.** Vehicles must always look grounded:
  shadow-casting, plus contact AO under the body. Every vehicle has a dark
  multiply-blend patch under it (`contact_shadow.gdshader`, made by
  `VehicleBodyVisual`: ground height from the wheels, fades out in the air,
  drawn to 90 m).
- **Cast shadow OFF** for: particles, skid marks, road markings and decals,
  clouds and sky elements, water, emissive lamp heads, props smaller than
  ~0.3 m, glass shards, distant vegetation impostors.
- **Terrain casts.** The mountain at sunset is a hero moment.
- Fix acne or peter-panning once, on the sun's `shadow_bias` and
  `shadow_normal_bias`. Never with per-object hacks. Low uses
  `shadow_normal_bias` 4.0 (its 2048 atlas striped the ground under a low sun);
  Medium and High use 2.0 (`GraphicsQuality.apply`).
- No baked or painted shadows in albedo.

---

## 11. Sky and atmosphere

- **Sky colours** per hour come from `DayNight.KEYS`; targets are in §5:
  a paler, hazier horizon and a mid-saturation zenith.
- **Aerial perspective:** exponential depth fog whose colour is the horizon
  colour (DayNight sets `fog_light_color`). Use `fog_aerial_perspective`
  0.3–0.6 so the fog picks up the sky, and `fog_sun_scatter` 0.1–0.25 for a
  warm glow toward the sun (Ref 2). Since step 1: aerial perspective 0.4, sun
  scatter 0.15, density 0.0005 (about a third fogged at 800 m; 0.0007 looked
  overcast in testing, the old 0.00045 left a hard sea horizon). Keep
  `fog_sky_affect` at 0.
- An optional, subtle height-fog layer near sea level for coastal haze.
- **The sea melts into the haze at the horizon** (Ref 1). No hard horizon line.
- **Clouds (realism branch):** real photographed skies. `tools/textures/fetch_sky.py`
  turns six CC0 Poly Haven "pure sky" HDRIs (dawn, morning, day, sunset,
  dusk, moonlit night) into 4096×1024 upper-hemisphere textures with the
  sun's core clamped out, and writes `SkyCatalog` (each photo's sun
  direction, colour, horizon and zenith colours). `DayNight.SKY_KEYS`
  crossfades them by hour with a brightness per key, puts the light at each
  photo's sun height, turns each photo so its sun sits where the light is,
  and takes the fog colour from the sky's horizon. Before the branch the
  clouds were drawn from `clouds.png` (still in the repo, unused).
  **No faceted mesh clouds.**
- **Sun:** the photo's own (clamped) sun with glow; `sky.gdshader` can draw a
  disc (`disc`, off). No lens flares or ghosts. Stars at night (as today).
- **No weather by default.** If rain is ever added, no SSR puddles: darken
  roughness and add a few streaks.

---

## 12. Vehicle design

**Design language**

- **Generic, unbranded archetypes** of real vehicle classes. Today's roster:
  sports coupé, sedan, van, box truck, city bus, pickup, buggy, monster truck.
  Each must read as its class from silhouette alone at 50 m.
- **No real brands**, badges, model names or trademarked design signatures
  (kidney grilles, famous light signatures, mascots). Mix cues from different
  eras and makers so no single real model is recognisable. Badges are simple
  invented geometric emblems.
- **Real proportions.** Arch gap 3–5 cm on road cars (today 8 cm), 8–15 cm on
  off-road vehicles. Wheels sit 5–20 mm inside the body sides. Ride height
  realistic for the class.
- **Glass area** about 30–38% of body height on cars, with realistic pillar
  rake.
- **Surfaces:** smooth, gently curved panels with crisp feature lines (shoulder,
  sill). Big bevels on the outer shell (3–8 cm), tighter ones on panel edges
  (5–15 mm). No boxy primitives.

**The fleet: one design language per class (step 4, owner-approved)**

The sports car sets the quality bar: materials, detail density, geometry
quality and finish. The other classes match that bar but are **not**
variations of the sports car; each has its own character. The generator
docstrings (`tools/blender/make_<vehicle>.py`) hold the full brief.

| Class | Character |
|---|---|
| Sports coupé (`make_car.py`) | 90s/early-2000s Japanese-inspired front-engined coupé: long bonnet, fender peaks, fastback cabin, small wing. Keep this character; don't push it more realistic. |
| Sedan (`make_sedan.py`) | Mid-2000s Japanese-style family sedan: three boxes, upright cabin with six side windows, chrome window trim. Taller and plainer than the coupé on purpose. |
| Van (`make_van.py`) | Modern European-style passenger van: one box, steep windscreen, black cladding and bumpers all round, sliding-door rail, twin rear doors. |
| Pickup (`make_pickup.py`) | Full-size American-style truck: tall flat bonnet, huge chrome-framed grille, chrome bumpers, crew cab, separate open bed. |
| Delivery truck (`make_truck.py`) | Japanese-style cab-over light truck: flat front, wrap-round windscreen, ribbed aluminium box with a roller door, visible chassis. |
| City bus (`make_bus.py`) | Modern low-floor bus: huge windscreen, continuous dark window band, glass doors, roof air-con, opaque tinted glass. |
| Buggy (`make_buggy.py`) | Classic desert sand-rail: small open tub with a cockpit dip, full tube roll cage and light bar, exposed engine, rear wing. |
| Monster truck (`make_monster.py`) | Retro 80s/90s show truck: boxy regular-cab pickup high on a tube chassis, chrome coil-overs, roll bar, exhaust stacks. |

**Must-have details (as geometry)**

- Panel shut-lines (bonnet, doors, boot) as 5–8 mm dark grooves on the
  deformable shell, so they bend with dents.
- Headlights with housing, lens and inner reflector. Tail lights with lens and
  an inner emissive element. **Amber indicators** front and rear on every road
  vehicle (traffic signals with them before turns and lane changes, and puts
  the hazards on after a crash); off-road toys (buggy, monster truck) may skip
  them.
- Grille openings with depth (a dark recess). Mirrors on stalks. Small door
  handles. Exhaust tips. A licence-plate recess (blank plate or "TURBO").
- Dark wheel-well liners and a simple dark underbody, so you never see through
  to the sky.
- A simple interior (seats, dash, steering wheel) in dark materials, 300–800
  tris, visible through the glass.

**Wheels:** multi-spoke rims with depth (5–10 spokes). Open alloy wheels show a
dark brake disc and a caliper behind the spokes (`Vehicle.brake_calipers`,
`caliper_color`: red on the sports car, dark grey on the sedan; the caliper is
`brake_caliper.glb`, mounted on the hub so it steers but doesn't spin). Tyres have rounded
shoulders and a slightly lighter sidewall; off-road tyres get chunky tread as
geometry. **The visual radius must match the physics wheel radius** in the
vehicle scene.

**Garage wheels (player option):** rims and tyres are also separate parts
(`assets/models/wheels/rim_<id>.glb`, `tyre_<id>.glb`) that `WheelKit` puts
together on the player's car; traffic and parked cars keep their combined
stock wheels. The rules:
- Every rim is built to **one standard fit: bead radius 0.243 m, width
  0.254 m** (the sports rim), axis X, +X outward, at the 0.37 m base. WheelKit
  scales it to the tyre (X by tyre width / 0.254, Y and Z by tyre bead /
  0.243), so any rim fits any tyre and the stock rims rebuild today's wheels
  exactly. Tyres keep their native size (outer radius 0.37).
- Rims use `Rim` (the part the garage recolours) and `Hub` (fixed: disc,
  centre, lug nuts); `Tire` may fake dark holes (the shader renders rubber).
  Tyres use `Tire` only.
- **Open** rims (`PartsCatalog.RIMS[...]["open"]`) include the brake disc and
  keep the caliper's space clear (x −0.058..+0.016, radius 0.118..0.196 at
  the standard fit); they get a caliper in the chosen colour. Closed rims
  (steel, beadlock, dish) have no disc and no caliper.
- Rim colours follow §13: bare-metal finishes (silver, chrome, gunmetal,
  gold, bronze) are metallic 1, painted ones (black, white, red, blue, lime,
  body colour) metallic 0 with a light clear coat. "Stock" keeps each rim's
  own finish.
- Tyre stripes (whitewall, coloured lines) are a band in the tyre shader
  (`stripe_radii`, fractions of the sidewall height in `PartsCatalog`), not
  geometry. They're a player-only retro option like racing stripes.
- Garage parts are cosmetic: the physics wheel never changes.

**Liveries:** racing stripes and graphics are a hero/player option, never a
traffic default. Buses and trucks carry invented company liveries.

**Racing stripes (garage option):** a model may include a separate mesh named
`Stripes` (material `Stripe`), projected onto the body with dense sampling
along its length so it never dips under curved panels.
- `VehicleBodyVisual` hides it unless `stripes` is on, and gives it a
  contrasting colour (`PaintPalette.stripe_color`).
- Only the player's garage choice turns it on (saved as `stripes`). Traffic
  and parked cars never show it.
- The garage shows the toggle (X / gamepad Y) only for vehicles that have
  stripes.

**Reference dimensions (metres).** The vehicle scenes (`scenes/vehicles/*.tscn`)
are the authority for wheel positions and radii.

| Class | Length | Width | Height | Today's model |
|---|---|---|---|---|
| Sports coupé | 4.3–4.6 | 1.85–1.95 | 1.15–1.30 | 4.45 × 1.27 h; wheels r 0.37 at x ±0.83, axles ±1.35 |
| Sedan | 4.6–4.9 | 1.80–1.88 | 1.40–1.48 | 4.70 × 1.47 h; r 0.34, x ±0.80, axles ±1.40 |
| Van | 4.9–5.4 | 1.95–2.05 | 1.9–2.2 | 4.99 × 2.01 h; r 0.36, x ±0.86, axles ±1.50 |
| Pickup | 5.2–5.8 | 1.9–2.05 | 1.8–1.95 | 5.44 × 1.75 h; r 0.40, x ±0.86, axles ±1.60 |
| Box truck | 6.5–8.0 | 2.3–2.5 | 3.2–3.6 | 6.96 × 3.33 h; r 0.45, x ±0.95, axles ±1.90 |
| City bus | 11–12.5 | 2.5–2.55 | 3.0–3.3 | 8.89 × 3.25 h (shortened for the town's streets); r 0.50, x ±1.00, axles ±2.20 |
| Buggy | fictional | | | 3.85 × 1.82 h (cage); r 0.42, x ±0.92, axles ±1.25 |
| Monster truck | fictional | | | 4.72 × 3.30 h; r 0.95, x ±1.32, axles ±1.65 |

Lengths and heights are measured from the models (height from the ground);
widths are left out because the mirrors dominate them.

---

## 13. Vehicle materials

**Material names are a code contract.** They're case-sensitive.

| Name | Used by code | Look |
|---|---|---|
| `Paint` | `VehicleBodyVisual` recolours it (`paint_color`) | car paint (below) |
| `Headlight` | `VehicleDamage` swaps it to a broken material | emissive lens |
| `TailLight` | `VehicleBodyVisual` brake emission; `VehicleDamage` | red lens |
| `ReverseLight` | `VehicleBodyVisual` reverse emission | white lens |
| `Glass` | `VehicleDamage` swaps it to cracked glass | tinted glass |
| `Trim`, `Chrome`, `Interior`, `Stripe`, `Tire`, `Rim`, `Hub`, `Cage`, `Frame`, `Box`, `Roof`, `GlassDark`, `Caliper` | fixed looks | per §6. `Interior`: dark cabin parts. `Cage`: roll cages, chassis tubes. `Box`: the truck's aluminium box. `Roof`: the bus's light grey roof. `GlassDark`: opaque windows painted on the body with nothing behind them (they never crack). `Caliper`: recoloured per vehicle. |

**The vehicle shaders replace the imported materials by name at runtime**
(`VehicleBodyVisual.apply_vehicle_materials`, used by every vehicle and the
parked-car props): `Paint`/`Stripe` → `car_paint`, `Glass` → `vehicle_glass`
(opaque glass → `vehicle_glass_opaque`), `Headlight`/`TailLight`/`ReverseLight`
→ `vehicle_lamp`, `Trim` → `vehicle_trim`, `Interior` → `vehicle_interior`,
`Tire` → `vehicle_tyre`. The swapped
material keeps the contract name as its `resource_name`. Paint, lamps and tyres
are per car (colour, state, dust); trim and intact glass are shared. The
Blender values are what the garage of an older build showed; the shaders own
the look now.

**UV kind tags (body_kit).** One lamp or trim surface holds several things, so
`body_kit.patch()`/`box()`/`tube()` take `kind=` and write UV0 =
(kind × 10 + 5 + s, t), where (s, t) are metres from the patch centre
(untagged faces are 0, 0; the glTF export flips V, `vh_kind` undoes it). Kinds:
1 `LAMP` (headlight beam, tail/brake, reverse), 2 `DRL` (daytime running light;
rear position light that never brakes), 3 `INDICATOR` (amber; left = x < 0),
4 `AUX` (fog lamps, light bars: night only), 5 `BRAKE_ONLY` (third brake
light), 6 `GRILLE_MESH` (honeycomb), 7 `GRILLE_SLATS`.

**Detachable meshes are matched by exact name:** `FrontBumper`, `RearBumper`,
`Spoiler`. A wing exported as "Wing" silently never falls off (it happened once;
the legacy pipeline renamed it on export, `body_kit` does not).

New names are fine for fixed materials. Add them to this table.

**Car paint** (`car_paint.gdshader`)

- **Solid:** albedo from the palette, metallic 0, roughness 0.13, clear coat
  0.6 at roughness 0.05.
- **Metallic:** metallic 0.35–0.6 (from `PaintPalette`), roughness 0.2, same
  clear coat, plus colour flop (brighter facing the camera, ×0.6 at grazing
  angles) and flakes that glint within ~3 m (faded out beyond, no shimmer).
- **Why the base is glossy:** inside a reflection probe Godot drops its
  clear-coat reflection and uses the base layer's, so a rough base (the old
  0.32) blurred the player's reflections to grey. The clear coat still adds
  the sharp sun highlight.
- **Ground reflections are toned down** (specular × 0.55 where the reflection
  points below the horizon): the sky's ground half is pale, and real lower
  doors reflect dark asphalt.
- **Grime:** `dirt` 0–1 dusts the lower body (object-space height between
  `dirt_top` and 0.6 m below it, broken up by splash noise), roughening it and
  killing the clear coat; the tyres' sidewalls get the same dust. Driving on
  dirt adds to it (`VehicleBodyVisual`, never washes off by itself); traffic
  starts with a random 0–0.45 (most cars clean); the buggy (0.35) and monster
  truck (0.3) start dusty.
- **Matte** (rare; buggy or monster truck): roughness 0.55–0.7, no clearcoat.
- **The paint look is defined in one place:** `VehicleBodyVisual.paint_material()`
  makes the per-car `car_paint` material. Vehicles and parked-car props both
  use it, so every car changes together. The finish (solid or metallic)
  belongs with the palette entry, not with each model.

**Other vehicle materials**

- **Glass.** `vehicle_glass.gdshader`: tint `#1E2833`, alpha 0.7 looking
  straight in rising to 0.96 edge-on (Fresnel, so windows mirror the street at
  a glance and show the cabin head-on), roughness 0.04, metallic 0, but only on
  vehicles that have an interior (the Blender material's alpha exports as glTF
  `BLEND`; that's how the swap tells the two kinds apart). The bus has no interior, so its
  `Glass` is opaque dark tint (`vehicle_materials(glass_alpha=1.0)`); it still
  cracks. A see-through cabin also needs inward-facing door
  cards, headliner and pillars, or you see out through the far side (backface
  culling). Cracked glass: a procedural spiderweb (13 jittered radial cracks,
  broken rings, a crushed milky centre, frosting) round the glass vertex
  nearest the hit, about 0.75 m across, on that car's own copy of the glass.
- **Lights** (`vehicle_lamp.gdshader`): unlit, a headlight is a glossy lens
  over a chrome reflector (metallic, it mirrors the street), a tail light a deep
  red lens, an indicator an amber one; reflector ribs and projector rings come
  from the patch coordinates. Emission energies: headlight beam 0 by day, 6.0
  at night (global `night`); DRL 2.4 by day, 1.6 at night; tail position 0.25 by
  day, 1.4 at night; brake 5.5; reverse 3.5; indicators 5.0 blinking at about
  85 flashes a minute; aux lamps 3.5 at night. Broken lamps: dark dull housing
  with a few lens shards left, no emission (the lamp's `broken` uniform).
- **Trim, rims and running gear:** black trim plastic `#222326` at roughness
  0.6. Chrome `#D9DBDE` at roughness 0.1, metallic 1, used sparingly; with sky
  reflections only, big chrome areas look flat. Aluminium rims `#B8BBBF` at
  roughness 0.35, metallic 1. Tyres `#1C1C1E` at roughness 0.9, sidewall
  about 5% lighter. Brake disc `#5A5C5E`, metallic 1, roughness 0.5. Caliper
  is an accent colour. Hubs, discs and alloy rims are bare metal (metallic 1);
  painted steel and beadlock rims are paint (0). Tyres (`vehicle_tyre.gdshader`):
  tread `#1A1A1C` at roughness 0.93, sidewall `#1F1F21` at 0.82 with a slightly
  glossier moulded band.
- **Interior** (`vehicle_interior.gdshader`): dark greys `#2A2B2E`–`#3A3B3F`,
  roughness 0.55 (plastic) to 0.92 (fabric), no emission, plus a light warm
  grey headliner (about `#7C7A74`) so the cabin reads through the glass.

---

## 14. Vehicle damage and deformation

**Goals:** satisfying, readable from the chase camera (5–8 m away),
mechanically plausible, kid-safe, cheap.

**Severity tiers** (`VehicleDamage.total_damage`, 0–100)

| Tier | What it looks like |
|---|---|
| Scuffed (< 15) | small 3–8 cm dents and paint scuffs at the contact point; sparks |
| Damaged (15–40) | clear dents at the impact; scrapes show primer; lights broken at the end that was hit; a bumper may fall off |
| Smashed (40–70) | deep crumple at the end that was hit (panels pushed back up to ~0.3 m); parts off; glass cracked (today above 55); smoke if the front is hit |
| Wrecked (70–100) | heavily crumpled ends and darker, heavier smoke, but **still clearly the same vehicle and still drivable** |

**Geometry**

- **Dents are smooth and broad, never spiky.** Today they use a smoothstep
  falloff with a 0.5–1.1 m radius. No self-intersection, no flipped faces.
  Depth caps today: `max_dent` 0.32 m per hit, `max_total_dent` 0.5 m in total.
- **Crumple zones:** the front and rear ends and outer panels deform most; the
  cabin (pillars, roof) deforms least. The target is a per-vertex stiffness
  value (contract below).
- **Wheels never deform and never come off.** That's an owner decision: losing
  a wheel made cars undrivable for a kid.
- **Normals bend with dents** so they show in the light (today ×2.5).
- **The silhouette survives.** A wreck is still recognisable.
- **Detachable parts** (`FrontBumper`, `RearBumper`, `Spoiler`) fall off as
  debris, lie around for 30 s, then get tidied away (as today). Model a dark
  structural beam (`#2A2A2C`; `Trim`, or a new `Structure` material) behind
  every detachable part, so losing it never reveals a hole, backfaces or sky.
  Detachable parts must be closed meshes, because they tumble.

**Material damage** (done in the vehicle realism pass)

- **Layer order:** clean paint → scuffed paint (+0.25 roughness, slightly
  lighter, no clear coat) → primer `#8C8C88` at roughness 0.7 → bare steel
  `#9A9C9E`, metallic 1, roughness 0.35. Scrapes are streaks along the body
  (noise stretched along its length); impacts make blotchy patches.
- **No** rust, burn marks or age dirt: crashes are instant.
- **Driven by a per-vertex mask** in `car_paint.gdshader`, so damaged cars need
  no extra textures. `VehicleDamage._dent` writes it with each dent (scrape
  0.35–0.85, paint loss 0.25–1.15 at the centre, by severity) and `scrape()`
  writes streaks without denting where bodywork slides along something faster
  than 4 m/s (`Vehicle.scrape_speed`, at most 5 times a second). It lives in
  the car's own dented mesh, so a repair clears it.
- **Broken lights:** dark dull housing (`#2E2E31`-ish, roughness 0.85) with a
  few lens shards catching the light, no emission.
- **Cracked glass:** a procedural spiderweb at the window nearest the impact
  (§13).

**Effects on impact:** sparks on metal-to-hard hits, glass bits, optional small
paint chips, dust on dirt, and engine smoke when the front is smashed (today),
going from white-grey to darker grey at Wrecked. Specs are in §23.

**Kid safety (hard rules):** no people shown hurt, no blood, no screams. Any
future occupants are simple silhouettes that never visibly get hurt. No fire or
explosions unless the owner asks.

**Data contracts for vehicle bodies**

- **Deformable meshes** are every `MeshInstance3D` under the vehicle's `Body`
  node (`VehicleDamage.body_path`). GDScript processes *all* their vertices on
  every dent pass. **Limit: ≤ 6,000 vertices across them (hard cap); aim for
  3,000–5,000.** Count the *exported* vertices (the .glb's POSITION counts,
  after normal and material splits), not Blender's.
  Measured on the dev machine, in a window (headless runs skip the GPU upload
  and read about 3× too low):
  - Before step 4: about 0.5 µs per vertex per pass, because every vertex was
    recomputed on every dent. The old sports car (2,252 vertices) took 1.2 ms.
  - Since step 4, `_dent` only touches vertices inside the dent, skips
    far-away surfaces, and keeps everything else as it was. The new sports car
    (5,749 vertices) takes 1.2–1.3 ms per pass.

  One crash runs several passes, and the Deck's CPU is slower. Going over the
  cap needs a code change first. Plan that change; don't silently exceed the
  cap.
- **Topology:** deformable panels need evenly spaced vertices, about 8–15 cm
  apart on large panels (doors, bonnet, roof, sides), quads where possible.
  **No big n-gons or triangle fans.** (The legacy `extrude_profile` closed
  each side with one n-gon, so a dent in a door moved almost nothing. The loft
  bodies are quad grids; flat parts that must dent use `body_kit.panel_box`.)
  Avoid long thin triangles.
- **Per-vertex damage data (reserved layout):** an authored crumple factor (1 =
  soft: bumpers, bonnet, wings, boot; ~0.5 doors; ~0.25 pillars, roof, cabin),
  plus runtime scrape and paint-loss masks written by `VehicleDamage`. The
  channel is vertex colour, **stored inverted** so a mesh without colours
  (Godot's default is white) reads as undamaged: G = 1 − scrape, B = 1 − paint
  loss (in use since the realism pass), R = 1 − crumple and A reserved. The
  models still export no vertex colours; only dented runtime meshes have
  them. Vehicle materials never use vertex colour as albedo.

---

## 15. Buildings and architecture

**Districts** (matched to the map)

| District | Where | Look | Ref |
|---|---|---|---|
| Downtown core | central city blocks (high `centrality` in `CityBuilder`) | 8–20+ floor towers: limestone or concrete bases, dark glass curtain walls, setbacks, crowns | 3, 2 |
| Coastal low-rise | outer city blocks toward the beach and harbour | 2–6 floors of stucco in warm cream, terracotta, sea-glass, pale yellow; awnings; flat roofs with parapets | 2 |
| Harbour / industrial | harbour, airfield | corrugated metal sheds, containers, cranes, concrete aprons | |
| Roadside | gas station, highway services | clean modern canopies and signs | |

**Facade grammar: every building has a base, a middle and a top.**

- **Base** (ground floor 4.2–5 m tall): shopfronts with big glazing (lit inside
  at night), entrances recessed 0.3–0.6 m, awnings (muted stripes allowed), a
  signage band with invented shop names, bollards and planters.
- **Middle:** repeated window bays. Floor height 3.4 m and bay width 3.2 m match
  `facade.gdshader` (`ground_floor` 4.6 m, `floor_height`; bays are fitted to
  each wall, about 3 m). Windows look recessed
  0.15–0.25 m (faked in the shader with a darker inner frame and reflective
  glass). Sills and lintels as trim bands.
- **Top:** a 0.5–1.2 m cornice or parapet, plus roof clutter: HVAC boxes, water
  tanks, stair housings, antennas. These are cheap boxes and cylinders (10–30
  tris each), merged.

**Variety and colour**

- Pick a material family and a palette colour per building, then vary value by
  ±5%. Neighbours differ in family or colour; at most two adjacent buildings
  share a family. Heights vary, and the downtown core is taller (as today).
- **Night:** about 55% of windows lit, about 85% of them warm and 15% cool-white
  offices, with per-window brightness variation and a brighter ceiling
  (`facade.gdshader`).

**Materials and construction**

- Plaster/stucco, concrete, limestone, brick (pattern from shader lines or a
  tiling texture), glass curtain wall with a mullion grid of 1.5 m × floor
  height, metal cladding for industrial buildings.
- Generated by `CityBuilder` with `BuildingKit`: one facade mesh and one
  clutter mesh per block (§26), box colliders per mass.
- **Grounding:** darken the bottom 0.5–1.0 m of walls with an AO/grime gradient
  in vertex colour. Add subtle vertical streaks under sills and parapets. Both
  are cheap realism.

**Avoid:** windowless boxes, uniform window grids with no base or top, pastel
candy colours, every building the same height, floating buildings (always sit
them on the sidewalk slab), visible interior faces.

**The kit** (`BuildingKit`, `scripts/world/building_kit.gd`): one to four
parcels per block, heights snapped to a 4.6 m ground floor plus 3.4 m floors,
dressed by style:

| Style | Where | Facade |
|---|---|---|
| Curtain wall (on a 2-floor limestone podium) | downtown towers over 30 m | glass with mullions every half bay, opaque spandrels, a metal coping |
| Limestone | downtown and midtown | tall windows with stone surrounds, ashlar joints, cornice |
| Brick | midtown, edges | running bond, white frames, stone sills, cornice |
| Stucco | edges (low-rise) | punched windows, sills, cornice |
| Ribbon | offices | continuous window bands, dark frames, coping |

Every building gets a plinth, shopfronts (big glazing, a fascia in a muted
accent, sometimes striped awnings) or a lobby base, a string course, a
cornice or coping, a parapet and roof clutter (stair housing, HVAC units with
fans, vents, sometimes a timber water tank or an antenna mast); towers step
back in one or two tiers. Windows are drawn by `facade.gdshader` with bays
fitted to each wall, so no window is cut at a corner. A darker apron on the
paving grounds each building.

---

## 16. Roads and highways

Geometry is generated by `RoadBuilder`; markings come from
`road_surface.gdshader` and `junction.gdshader`. **Keep the widths in `MapLayout`.** They're tuned for
gameplay: city road 12 m (two 2.8 m lanes each way), highway three 3.6 m lanes
each way plus a 2.4 m median and 1.4 m shoulders, hill road 9 m, trail 6 m,
kerb 0.15 m.

**Surface**

- Asphalt base `#46474A`, worn patches toward `#5A5B5D`, darker repairs
  `#393A3D`. Fine grain that disappears beyond ~30 m. Subtle darker wheel paths
  in each lane. Occasional crack-sealing lines and patch rectangles on city
  streets; the highway is smoother and more uniform.
- Concrete highway decks and bridges in `#B4B0A7`, with expansion joints every
  20–30 m (thin dark lines across, every 24 m in `road_surface.gdshader`).

**Markings** (real-world conventions, generic, US-style yellow centre lines as
today)

- White lane lines 0.10–0.15 m wide, yellow centre and edge lines. Dashes 3 m
  with a 5 m gap in the city, 4 m with an 8 m gap on the highway (as today).
- Light wear: 5–20% breakup noise, more at intersections. Roughness 0.6–0.7,
  slightly glossier than the asphalt.
- Zebra crossings and stop lines at signals. Optional arrows, from the shader
  or from mesh decals in a shared atlas.
- **Readability comes first.** Markings must stay obvious at speed from the
  chase camera, at night in the headlights, and on Low.

**Kerbs and sidewalks:** the 0.15 m kerb keeps its bevel (it's drivable, which
matters for gameplay), in `#A8A39A`. Sidewalk paving in `#BDB8AE` with a
0.6–1.0 m slab grid from shader lines, faded with distance. Tree pits, drain
grates and manholes as decals or atlas details.

**Highway structures** (Ref 1)

- Concrete Jersey barriers about 0.8 m tall with the classic sloped profile, in
  `#B4B0A7` with a darker stained base.
- Overpass decks with thick concrete fascias, visible girders and undersides,
  tapered rectangular or round pillars on footings, and drainage streaks below
  the deck edges.
- Galvanised W-beam guardrails (§6) on rural and mountain roads and bridges.
- **Signs:** overhead gantries. Highway signs in green `#1E6B3C` with white
  text and border; warning signs as yellow diamonds; regulatory signs in white
  and red. Place names are our own (City Center, Harbour, Airfield...).
- Tall highway lamps in cool LED are optional; city lamps are warm.

**Rural and mountain:** narrower asphalt with edge lines and gravel shoulders
(blending into dirt). The trail is packed dirt `#8C6A48` with tyre ruts. White
marker posts with orange reflectors (as today).

**Avoid:** blue-tinted asphalt (today), pure white markings, perfectly uniform
asphalt, Z-fighting decals, shimmering markings (always use `fwidth` AA), and
repetition you can see along long straights.

**As built** (`road_surface.gdshader`, `junction.gdshader`,
`paving.gdshader`, `concrete.gdshader`): asphalt grain, sun-worn and darker
patches at two scales, wheel paths, repair patches (9 m cells, ~12% on city
streets), crack sealing, paint chips (5–15%), gutters, drains every 27 m,
manholes every 31 m, stop lines 3.4 m before signalized junctions (just ahead
of where `TrafficNetwork` stops cars), expansion joints every 24 m on bridge
decks. Kerbs: 1.2 m kerb stones on the same drivable 0.35 m slope; sidewalks:
0.9 m slabs. New Jersey barriers have the real profile (0.81 m, 55°/84°
faces) with joints every 6 m. Overpass sections have 1.3 m fascias, a soffit,
five girders, and piers of two bevelled columns on footings under a cap beam.
Overhead sign gantries are galvanised box trusses on posts with footings;
the signs are green with a white border. The dirt trail is plain ground in
`paving.gdshader` with `StreetKit` marker posts. No guardrails yet: they would
block driving off the hill roads (§32).

---

## 17. Environmental props

**Today's catalogue:** traffic cone, barrel, crate, bowling pin (stunt park),
lamp post, traffic light, parked car/sedan/van, ramp (`scenes/props/`), plus
builder-made details (benches, billboards, signs, harbour containers...).

**The kit** (`StreetKit`): street lamp (iron, flared base, bowed arm, slim
luminaire), traffic signal (mast arm and brace, black backplate with a yellow
border, visors, street-name blade, pedestrian signal), hydrant, litter bin,
bench, signal cabinet, bollards, bus shelter, marker post, and the stunt
props: traffic cone (0.72 m, two reflective bands), oil drum (tinted per prop
through the `tint` instance uniform), wooden crate with battens, giant
bowling pin. Ramps keep their shapes and colours but are painted plywood
decks with panel seams (class 15) and hazard-striped edges on a steel frame.
Each is one mesh on `street_props.gdshader` (one draw call; lamps glow from
the global `night`, signal lenses from an instance uniform), built in code
once and shared. Physics props are `KitProp` scenes (`street_lamp`,
`traffic_signal`, `hydrant`, `street_bin`, `bench`, `signal_cabinet`,
`traffic_cone`, `barrel`, `crate`, `bowling_pin`) with visibility ranges (120-150
m small, 250 m lamps and signals); bollards are static and merged. Landmarks
(`LandmarksBuilder`) use the same materials and bevelled, lathed parts.

**Rules**

- **Real-world size, simplified shape.** Traffic cone 0.7 m (today 0.72);
  traffic barrel ~1.0 m tall and 0.6 m wide, orange with white reflective
  bands; Jersey barrier 0.8 m; bollard 1.0 m; bench seat 0.45 m; bin 1.0 m;
  hydrant 0.8 m; mailbox 1.3 m; lamp post 6–9 m (today 6.5); signal head 1.0 m.
- **Weight reads visually:** light plastic props (cones, barrels) in bright
  hazard colours; heavy props (barriers, bollards) in concrete or steel.
- **Bevel every edge,** smooth-shade, add AO. Budgets: small props ≤ 300 tris,
  street furniture ≤ 1,500, large props (gas station canopy, billboard) ≤ 3,000.
- **Shared material:** `materials/env/street_props.tres`
  (`street_props.gdshader`): vertex colour for albedo, the material class in
  the vertex alpha. One draw call per prop. Hazard colours: orange `#E8661C`,
  red `#C8231B`, white `#E4E2DA`, yellow `#E8B51E`, black `#222326`.
- **Physics props:** collision primitives within ~5 cm of the visual, and
  start with `sleeping = true` (as today).
- **Signs and branding:** invented brands with simple flat graphics.
  Kid-friendly humour is welcome. No real brands.
- **Stunt park exception:** ramps, bowling pins and the loop can be playful in
  colour, but they're still physically based materials (painted wood, steel,
  concrete) and read as a real stunt arena.
- **Placement:** props sit on surfaces (never floating or sunk), aligned to
  roads and kerbs, scattered with fixed seeds.

---

## 18. Vegetation

**Biomes**

| Where | Species and look |
|---|---|
| City streets and parks | broadleaf street trees with round canopies; a few flowering trees (red/pink accents); hedges; lawns |
| Beach and harbour | palms (8–15 m); dune grass clumps |
| Hills and mountain | conifers (8–18 m) in clusters; scattered shrubs; ≤ 10% autumn-tinted accents |
| Dirt fields | dry grass, sparse shrubs |

**Look**

- **Canopies are clustered masses** with soft shading: not individual leaves,
  and not faceted blobs. Technique (`TreeKit`):
  leaf-cluster cards (alpha scissor, from a generated 1024² leaf atlas) around
  a low-poly canopy volume, with **normals pointing outward from the canopy
  centre** ("spherical normals") for soft, cloud-like light. Trunk plus 2–5
  main branches as tapered cylinders.
- **Sunlit tops are lighter and yellower** (`foliage_lit`), undersides darker
  (an AO gradient in vertex colour).
- **Per-instance variation** through MultiMesh instance colour or an instance
  uniform: ±6% value, ±0.02 hue.
- **Wind:** a subtle vertex sway in the shader (≤ 5 cm at canopy tips, slower
  for big trees), switched off beyond ~80 m and on Low.
- **Grass:** no field-wide grass blades; terrain colour variation does that
  job. Optional sparse grass and flower clumps (MultiMesh, alpha-scissor cards)
  within 40–60 m of the camera on High, along road edges and in parks.

**Budgets:** tree LOD0 1,500–4,000 tris (each card counts as 2 tris, ≤ 300
cards); LOD1 ≤ 800; far LOD ≤ 100 or a billboard impostor; palms 1,000–2,500.

**The kit** (`TreeKit`): two broadleaf variants (~7 m, 143 cards in 11
clusters around a solid core, four limbs, ~530 tris), a conifer (~9 m, tiers
of drooping needle sprays round a solid cone, ~320 tris) and a palm (~9 m,
a leaning ringed trunk, 12 arching fronds from `leaves_palm.png`, ~540 tris)
on the coast, with solid `_far` versions (~170 tris) and automatic LODs. `NatureBuilder` puts them in
one MultiMesh per variant per 128 m chunk, near meshes to 170 m and far
meshes beyond (with fades), and tints each tree ±6% by instance colour.

**Tech**

- **One MultiMesh per species per spatial chunk** (128 m). A MultiMesh is
  culled and LOD-ed as a whole, so chunking is what makes culling and LOD
  work.
- **Alpha scissor** (threshold ~0.5) with culling disabled for cards. **Never
  alpha-blend leaves.** Fewer, larger cards beat many small ones on the Deck
  (overdraw).
- Trunk colliders stay cylinders (as today). Keep trees off roads, steep slopes
  and keep-clear zones (rules in `NatureBuilder`).

---

## 19. Terrain and water

- **Terrain:** vertex-colour blends of grass, dry grass, dirt, rock and sand,
  with smooth per-vertex normals (both as today), regraded to the §5 palette.
  Target: tiling 512² detail textures (4 m tiles) blended by vertex-colour
  weights, world-space macro noise, triplanar mapping on slopes steeper than
  ~35°, rock on steep slopes (as today).
- `terrain.gdshader` adds grass clumps and grain near the camera, dry and lush
  patches at 80–250 m scales, and rock with strata on slopes steeper than about
  35°. Boulders are smooth lumpy ellipsoids in `concrete.gdshader`.
- **Water:** sea colours from §5. `water.gdshader` gets the depth from a
  shoreline mask baked from the terrain heights at startup (no
  `DEPTH_TEXTURE`): turquoise shallows, a pulsing, broken foam band at the
  waterline. Two scrolling ripple normal maps (faded with distance) catch the
  sky (fresnel) and the sun at roughness 0.06. The sea stays calm: no big
  waves.

---

## 20. UI visual language

**Today:** all UI is built in code. `UiKit` (`scripts/ui/ui_kit.gd`) holds the
shared look: yellow accent, navy panels at 88%, rounded panels (radius 18),
buttons (radius 12), a 3 px yellow focus ring. `hud.gd` duplicates the panel
and label helpers with 72% panels. The speedometer and minimap are drawn with
`_draw()`.

**Direction:** keep the structure and colours; they already match Ref 3's
layout. Refine toward a clean automotive instrument rather than a cartoon.

**Rules**

- **All new UI goes through `UiKit`.** Extend it; don't hardcode colours or
  styleboxes elsewhere. When touching `hud.gd`, move its duplicate helpers
  into `UiKit`.
- **Layout:** HUD at the screen edges only. Keep the centre third clear while
  driving (popups are brief). Safe margins ≥ 24 px at the 1600×900 reference.
  Minimap bottom-left, speedometer bottom-right (speed, gear, RPM arc), score
  top-right, toasts and race status top-centre, trick popups centre.
- **Panels:** translucent navy at 72–88%. Radius 14–18 for panels, 10–12 for
  buttons and chips. An optional 1 px inner border in white at 8–12%. No
  textures, bevels or emboss; only subtle gradients.
- **Colour meaning** (values in §5): yellow = focus, primary action, key hints;
  white = content; cyan = speed/info; green = go/success; red = damage, danger,
  redline; violet-pink = drift mode; gold/silver/bronze = medals.
- **Text over the 3D world:** thinner outlines than today (2–3 px) or a soft
  drop shadow. No outline on text inside panels.
- **Motion:** 150–250 ms ease-out for panels and popups. Numbers ease smoothly
  (the speedometer already lerps). No bouncing or wobble, except one scale
  punch on stunt popups.
- **Gamepad first:** everything focusable, the yellow focus ring always visible,
  button prompts that match the device in use. The mouse works too.
- **For a young player:** short words, big text, icon plus text for actions,
  text contrast ≥ 4.5:1 against its panel.
- **Steam Deck:** the project has no stretch mode, so UI sizes are raw pixels.
  The Deck shows 1280×800 (or a 1600×900 window scaled to about 0.8×). Check
  every screen at 1280×800 (`godot --path . --resolution 1280x800`).
- **3D in UI:** the garage preview's studio lighting stays consistent with §9.

---

## 21. Typography

**Today:** Godot's built-in default font everywhere (`ThemeDB.fallback_font`),
sizes 14–64, with outlines.

**Target**

- **One family in two widths.** Suggested: **Barlow** (body) plus **Barlow
  Semi Condensed / Condensed Bold** (headings, buttons, HUD numbers), both SIL
  OFL. Adding a font means downloading a file, so **ask the owner first**. Put
  font files and `OFL.txt` in `assets/fonts/`, set the font as the theme
  default in `UiKit`, and make the `_draw()` code (speedometer, maps) use
  `UiKit`'s fonts instead of `ThemeDB.fallback_font`.
- **Until a font is added,** keep the default font everywhere. Never add a
  third font.
- **Numbers** (speed, timers, scores) use tabular figures (`FontVariation`
  OpenType feature `tnum`) so digits don't jitter, in a heavy weight.
- **Case:** headings and buttons in ALL CAPS with +1–2 px tracking. Body and
  help text in sentence case.
- **Type scale** (px at the 1600×900 reference):

  | Role | Size |
  |---|---|
  | Display (title) | 64 |
  | H1 (toasts, popups, big speed) | 40 |
  | H2 (page titles) | 32 |
  | H3 (buttons, race status) | 26 |
  | Body | 22 |
  | Small (hints, gauge ticks), **minimum** | 18 |

  Today these are below the minimum: help text 17, "H = help" 15, speedometer
  ticks 15, units and "DRIFT" 14, minimap "N" 14. Fix them when touching those
  screens.
- Panel line length ≤ 50 characters; line height 1.2–1.35.
- For a font drawn at many sizes, enable MSDF on the font import.

---

## 22. Icons

- **Style:** simple and geometric with rounded joins. Solid fills, or 2–3 px
  strokes at 32 px. One colour: white on dark, yellow when focused or active.
  A consistent 24/32/48 px grid with 2 px padding.
- **Format:** SVG in `assets/ui/icons/` (set the import scale for crispness), or
  drawn in `_draw()` for simple shapes. Today the garage arrows are triangles
  drawn in code because the default font has no arrow glyphs.
- **Never use font glyphs or emoji** for icons or arrows.
- **Gamepad prompts:** Steam Deck/Xbox layout. A/B/X/Y as white letters in dark
  circles (monochrome, like the Deck's own buttons). LB/RB/LT/RT as rounded
  shapes. The D-pad as a cross with the active direction highlighted. Keyboard
  keys as light rounded rectangles with dark text.
- **Map icons:** the player is a red-orange arrow, traffic is small white dots,
  teleport spots and races are coloured numbered roundels, plus a north marker
  (all as today).
- **Consistency:** the same stroke weight and corner radius across the set.
  Build icons from simple primitives so a script can generate them.

---

## 23. Effects

| Effect | Today | Spec |
|---|---|---|
| Tyre smoke | white-grey puffs, unshaded | `#EDEDED` at alpha 0.4–0.55, **lit** (responds to sun and night), grows 2–3× over a 1.5–2.5 s life, ≤ 40 particles per wheel |
| Dust | brown puffs on dirt | coloured from the surface (dirt or sand, lightened), lit |
| Skid marks | MultiMesh quads, dark at 55% | `#141416` at alpha 0.4–0.6; older marks fade; never on dirt |
| Sparks | emissive, velocity-aligned streaks | hot white → orange `#FF9A3C` → red, 0.3–0.7 s, with gravity. The brightest thing on screen; glow is fine. |
| Glass bits | small transparent boxes | glass tint, 1–1.5 s |
| Engine smoke | grey puffs from the bonnet | white-grey, darkening toward `#4A4A4E` as damage rises; lit; rises and drifts |
| Debris | detached parts as rigid bodies | real parts in their own materials |
| Water splash | none | white foam burst and droplets when a car hits the water (future) |
| Landing puff | none | a short dust burst on hard landings (future) |

**Rules**

- **Particles are lit by the scene** (per-vertex shading is enough). Only
  sparks, lamp glows, lights and gameplay markers are unshaded or emissive.
- **Overdraw is the Deck's enemy.** Puff quads ≤ 2.5 m, ≤ 40 per emitter, fade
  particles near the camera, ≤ ~1,500 live particles in total.
- Particles never cast shadows (as today). Emitters stop beyond ~80 m from the
  camera.
- **Camera effects:** impact shake and speed FOV (as today). **No** motion blur,
  chromatic aberration, film grain, lens dirt, vignette stronger than 10%,
  screen distortion or heat haze, or full-screen flashes (photosensitivity).
- **The slow-motion crash cam** replays the same effects, so they must look good
  at 0.25× speed: no obviously looping sprites.

---

## 24. Asset creation in Blender

**Principle:** every model is generated by a committed Python script run
headless. The `.glb` is a build output. To change a model, change the script,
rerun it, and commit both.

**Existing pipeline:**
- **New-style bodies:** `tools/blender/body_kit.py`. It provides
  `BodySpec`/`LoftBody` (a spec-driven loft: profiles, cabin regions, window
  list, door and shut lines, bumper split, inner cabin), projected decal
  patches, lathe and spoke helpers, materials and export. Each vehicle has
  its own script: `make_car.py` (sports car), `make_sedan.py`, `make_van.py`,
  `make_pickup.py`, `make_truck.py` (delivery truck), `make_bus.py`,
  `make_buggy.py` and `make_monster.py`.
- **Wheels:** `make_wheels.py` builds all four types (sports `wheel.glb`, sedan
  `wheel_sedan.glb`, steel `wheel_steel.glb`, off-road `wheel_offroad.glb`) at
  a 0.37 m base radius; scenes scale them uniformly. It also exports every rim
  and tyre as a garage part into `assets/models/wheels/` (the contract is in
  §12 "Garage wheels" and the script's docstring); the combined wheels are
  composed from the same rim and tyre builders, so they never drift apart.
- The legacy extruder (`vehicle_kit.py`, `make_traffic_vehicles.py`,
  `make_offroad_vehicles.py`) was deleted once the last vehicle migrated, so it
  can't overwrite the new models. It's still in git history.

How the loft works: cross-sections at stations front to back, each a list of
right-half points from the bottom centre to the top centre, mirrored. Face
materials are chosen by station and segment, so windows, pillars, shut lines
and bumpers are regions of one quad grid. Arches come from raising the
section's bottom over the wheels, and the nose and tail round off in plan
view. Lessons:
- Never recalculate normals on open shells; the winding is authored.
- Open shapes (beds, tubs) use `section_override`/a custom section that runs
  over the rim and down the inside to the centre line, so the mirror still
  closes (see `make_buggy.py`'s tub and `make_monster.py`'s bed).
- Check vertex counts on the exported .glb.
- Preview headless with a Workbench render before importing into Godot.

Run from the project root:

```bash
blender -b -P tools/blender/make_car.py
```

Output goes to `assets/models/`.

**Conventions (keep these)**

- Metres, scale applied, Blender Z-up (the glTF export converts to Godot's
  Y-up).
- **Vehicles:** the front points to Blender +Y (Godot −Z). The origin is at
  wheel-centre height, midway between the axles. Wheel positions and radius
  match the vehicle scene.
- **Lamps and grilles are tagged** with `kind=` on `patch()`/`box()`/`tube()`
  (§13, UV kind tags); every `Part` has a UV layer for it.
- **Material names follow the contract** (§13). Detachable parts are their own
  `bk.Part` named exactly `FrontBumper`, `RearBumper` or `Spoiler` (the Part
  name becomes the Godot node name). Each becomes its own mesh in the `.glb`.
- Export with `bk.export` (GLB, selection only, transforms applied).

**Modelling rules for the new style**

- **Bevel all hard edges** (an angle-limited bevel modifier: 2–3 segments on
  outer shells, 1–2 on small parts) and **shade smooth by angle** at 30–35°
  (`smooth_by_angle`). Add a **Weighted Normal** modifier (face-area weighting,
  keep sharp) on bevelled hard-surface parts, so flat faces shade flat and the
  bevels catch the light. This is the signature of the style.
- **Deformation-ready vehicle shells (§14):** build from an evenly subdivided
  base. One way: model the form, Remesh at 0.08–0.12 m voxels, shrinkwrap back
  onto the original, then Decimate (planar) down to the vertex budget. After
  booleans, check there are no n-gons or fans on deformable panels.
- **Clean meshes:** manifold, outward normals (recalculate), no interior faces,
  no zero-area faces, duplicate vertices merged (0.1 mm).
- **Separate objects only where behaviour differs** (detachable parts, wheels).
  Join everything else, to keep draw calls low. ≤ 10 material slots per body.
- **UVs:** when a texture or atlas is used, unwrap UV0 (Smart UV Project, or
  explicit UVs for trims) at a consistent texel density. No UV1 (there are no
  lightmaps).
- **AO:** for world props that use vertex colour, bake AO into vertex colour
  (Cycles bake). For vehicles, put AO in a texture once they have UVs, never in
  vertex colour (reserved, §14).
- **Budgets:** §26.
- **Verify** with a headless preview render to the scratchpad (Workbench or
  Eevee PNG), then in Godot with `--garage` and `--showcase` screenshots. For
  vehicles, also run `--damage`.
- **Other families** (props, building kits, trees) follow the same principle:
  `tools/blender/make_<family>.py` writing to `assets/models/<family>/`.
  Code-generated geometry (`MeshBuilder`) is equally valid for world, building
  and road parts. Use whichever keeps one source of truth.

---

## 25. Asset import into Godot

- **Files:** `.glb` files go in `assets/models/` (a subfolder per family for new
  work). Commit the `.import` file (it holds import settings and the uid);
  never commit `.godot/`.
- **Import settings:** keep the current defaults unless there's a reason:
  `meshes/generate_lods=true`, `create_shadow_meshes=true`,
  `ensure_tangents=true` (needed for normal maps). Materials stay embedded
  (`materials/extract=0`) because the code looks them up by `resource_name`.
- **External materials:** if you replace imported materials with Godot material
  resources (`assets/materials/<family>/*.tres`, through external materials in
  the import settings or a post-import script), **set `resource_name` to the
  contract name** (`Paint`, `TailLight`...). Otherwise `VehicleBodyVisual` and
  `VehicleDamage` won't find them.
- **Textures:** PNGs in `assets/textures/<family>/`, imported VRAM Compressed
  with mipmaps; normal maps flagged as normal maps.
- **Scenes:**
  - Vehicles: `scenes/vehicles/<id>.tscn`, with `Body` (`VehicleBodyVisual`)
    holding the model and wheels with `Visual` nodes. Register drivable
    vehicles in `scripts/vehicle/vehicle_catalog.gd`.
  - Physics props: `scenes/props/<name>.tscn` (`RigidBody3D` + `prop.gd`).
  - Follow the existing scenes as templates.
- **Naming:** snake_case files, PascalCase node names, contract material names.
- **After importing,** check the model in the garage (`--garage`), in traffic
  (`--showcase`), and in crashes (`--damage`). Make sure the detachable mesh
  names survived the import.

---

## 26. LOD and detail guidelines

**Triangle budgets (LOD0)**

| Asset | Tris | Notes |
|---|---|---|
| Vehicle body, all meshes under `Body` incl. interior | 6k–10k | ≤ 6,000 deformable vertices (§14). Today 5.7–8.2k tris, 4.9–5.9k vertices. |
| Wheel (one mesh, instanced ×4) | 800–2,000 | not deformed. Today 2.0–2.4k, a little over: trim the tread/lugs first if primitives get tight. |
| Garage rim / tyre part | rim ≤ 1,400, tyre ≤ 1,300 | any pair ≤ ~2,600 (today 2.3–2.6k; the stock pairs are exactly today's wheels). Player car only. |
| Small prop | ≤ 300 | |
| Street furniture | ≤ 1,500 | |
| Large prop | ≤ 3,000 | |
| Tree | 1,500–4,000 | cards count as 2 tris each |
| Palm | 1,000–2,500 | |
| Mid-rise building incl. roof clutter | 1,000–4,000 | windows in the shader |
| Landmark (lighthouse, crane, hangar) | ≤ 10,000 | |

**Distances**

| Asset | Full detail | Reduced | Cull |
|---|---|---|---|
| Vehicles | < 30 m | automatic mesh LOD (import) | traffic despawns at range (spawner) |
| Small props | < 40 m | automatic LOD | `visibility_range_end` 120 m, 20 m fade |
| Lamps, signals, street furniture | < 60 m | automatic LOD | 250 m (lamp light fades at 70–95 m, as today) |
| Trees | < 80–150 m | LOD1 to 400 m | impostor out to the fog |
| Grass clumps | < 30 m | | 60 m |
| Buildings | always drawn; facade detail fades in the shader | | |
| Particles | | | stop emitting beyond 80 m |

**Rules**

- Use Godot's automatic mesh LOD for imported meshes (the default), plus
  `visibility_range_begin`/`_end` with a fade for hard cut-offs. **No visible
  popping within 30 m.**
- **Static world geometry is merged by family into chunks** of ~100–250 m (or a
  city block), so culling still works while draw calls stay low: one facade
  and one clutter mesh per city block, one tree MultiMesh per species per
  128 m.
- **Code-built meshes get automatic LODs** too: `MeshBuilder.with_lods`
  (indexes the mesh and calls `ImporterMesh.generate_lods`, like the glTF
  importer) for StreetKit props, TreeKit trees and the per-block facade and
  clutter meshes. In the aerial view it saved ~160k primitives with no
  visible change; it adds about 80 ms to the world build.
- Dented vehicles lose automatic LOD (`VehicleDamage` swaps in a plain
  `ArrayMesh`). That's acceptable because only a few are dented at once.
- **Street level is where detail counts:** the chase camera is 1–3 m above the
  road. Spend detail on the bottom ~8 m of the world.

---

## 27. Steam Deck performance

**Target:** 60 fps (16.7 ms) at 1280×800 on the Deck **on Medium**, in the
busiest views: city centre at night with busy traffic, a big crash with parts
and smoke, the overview from the mountain. (Owner, 2026-10-03: don't limit the
look to the Deck; the Deck needn't run the top presets at 60.)
- **Medium** must always hold 60 fps on the Deck: it's the Deck setting.
- **High** is the default (`Settings.DEFAULTS.graphics = 2`); since 0.7.1 it
  is tuned to stay close to the Deck, but it may be heavier than 60 fps there.
  **Ultra** is for PCs and may be much heavier.
- Don't count on frame generation to fix performance: native frame rate and
  sensible presets come first. Keep profiling every change for regressions
  (the iGPU with `--gpu-index 0` is a rough Deck stand-in, about 1.6× slower).
- **Low** is the safety net: FSR at 0.75 scale, no glow or SSAO, 2 shadow
  splits, glow-only lamps.

**Hardware:** AMD APU with a 4-core Zen 2 CPU and an RDNA 2 GPU (8 CUs), 16 GB
shared LPDDR5, 1280×800 7" screen (LCD 60 Hz; the OLED model's 90 Hz doesn't
change our 60 fps target), Vulkan (RADV). It runs the Linux x86_64 export
natively. The dev machine (RTX 4090 Laptop) is more than 10× faster on the GPU,
so desktop frame times prove nothing. Counts (draw calls, objects, triangles,
vertices, particles) do transfer.

**Baseline** (2026-10-01, High, highway spawn, chase camera, `--bench` with a
window):
- After step 1: 605 draw calls and 1,845 objects without traffic. At v0.3.1 it
  was 589 and 1,849; the +16 are shadow casters from the lower 15:00 sun
  (identical counts with the old 14:00 sun). With traffic the count depends on
  where the cars are (733 at v0.3.1, 826 after step 1, for 22 cars).
- Desktop GPU time was unchanged by step 1 in a back-to-back A/B run (1.37–1.44
  ms before, 1.37–1.39 ms after). The same bench read 0.60 ms earlier that day,
  so desktop GPU times swing with the laptop's power state: only compare A/B
  runs made back to back.
- After the sports car (step 4 prototype): 648 draw calls and 1,896 objects
  without traffic. The model has a couple more surfaces than before, and the
  parked cars in the lots use it too.
- **After the whole fleet (step 4):** 733 draw calls and 2,023 objects without
  traffic, +85 / +127 against the sports-car-only build in a back-to-back A/B
  (three runs each). With 22 traffic cars: 929–993 against 779–863. Desktop GPU
  and render-CPU times were the same within noise. The cost is surfaces: the
  sedan, van, pickup and bus went from 8–9 to 12–13 (interiors, chrome, light
  patches), and traffic plus the parked cars (sedan, van, sports car) use them.
  One run read 1,553 with traffic: placement varies, and a car near the camera
  costs about 25 surfaces times the shadow passes. **Check dense city traffic on
  the Deck** against the 1,200 budget; trims are listed in PROGRESS.md.
- Bodies now: 5.7–8.2k tris, 4.9–5.9k exported vertices, 8–9 surfaces on the
  main mesh and 12–15 with bumpers/wing (a hidden `Stripes` mesh costs
  nothing). Wheels: 2.0–2.4k tris, 3 surfaces.
- Dent cost: see §14 (windowed, about 1.2 ms per pass for a car).

- **After the environment upgrade** (2026-10-01, whole map, High):
  - Highway bench (`--bench`, window): 305 draw calls and 622 objects without
    traffic (v0.4.0: 733 and 2,023), 466 and 936 with 22 cars (v0.4.0: 1,027
    and 2,628). Lamps and signals are one mesh each (the old ones were four to
    six), small props cull at 120–150 m and parked cars at 200 m.
  - City views (`--scenery`, no traffic): avenue 257 draw calls / 683k
    primitives, downtown street 729 / 1.29 M, aerial over the city 892 / 1.34 M
    (v0.4.0: 1,166 / 1.16 M). The aerial view was 1.54 M before parked-car
    culling and automatic LODs; terrain is still ~260k of it.
  - GPU: desktop timings can't resolve it (±15% run to run). At 2× resolution
    the preview area measured +3% (buildings) to +28% (views full of tree
    cards) against v0.4.0. Low skips the detail samples, the second ripple
    sample and the tree sway.
  - World build: ~0.75–0.85 s on the dev machine (was ~0.45 s); about 80 ms of
    it is automatic LOD generation. **Check load time and the busiest views on
    the Deck.**

- **After the vehicle realism pass** (2026-10-02, `dev`, back-to-back with
  the commit before it):
  - Highway bench: 306 draw calls without traffic (+1, the contact shadow);
    447–637 with 22 cars (466–543 before; placement varies). 18 cars driving:
    8.54–8.91 ms per physics tick wall clock (8.50–8.85 before). Desktop GPU
    and render CPU the same within noise.
  - City drive at 80 km/h (`--bench`, new): 1,436 draw calls on average,
    1,992 at the peak, without the reflection probe; with it (High) +112 on
    average and the same peak, no measurable CPU/GPU difference here. Note
    the city drive is already over the 1,200 budget without any of this: an
    environment item.
  - Sound: the game uses +0.06 CPU cores with every vehicle sound playing
    versus all stopped (traffic on). The player's car plays 6–10 audible
    voices, traffic loops for at most 6 cars.
  - Deformable vertices: +18 to +68 per body (indicator patches), max 5,953.

- **After the player character** (2026-10-03, `--onfootbench`, city centre,
  22 cars): the character adds ~10–13 draw calls and no measurable GPU time
  (iGPU at Medium ≈ +0.2 ms in alternating A/B runs, inside the noise), and
  ~0.3 ms of CPU per 60 fps frame on foot (dev CPU). Driving is unchanged
  (`--bench` A/B against the commit before: same physics tick, same 1,542
  draw calls on the city drive). The same view on the iGPU is 35–44 ms at
  Medium with or without it: the city centre itself is the Deck's problem.

**Budgets** (busiest view, High)

| Metric | Budget |
|---|---|
| Draw calls | ≤ 1,200. Any single feature adding more than ~100 needs discussion. |
| Visible primitives, incl. shadow passes | ≤ 1.5 M |
| Deck GPU frame time | ≤ 11 ms on Medium; High as close to 13 ms as it reasonably gets |
| Shadow casters | the directional light only (§10) |
| Visible local lights | ≤ 16, none with shadows |
| Live particles | ≤ 1,500 |
| Transparent overdraw | no full-screen transparent layers; foliage uses alpha scissor |
| Texture memory | ≤ 256 MB |
| Deformable vertices per vehicle | ≤ 6,000 |
| Draw surfaces per vehicle | ≤ 10 on the body mesh (detachable parts add 2–6), ≤ 2–3 per wheel (garage wheels on the player's car: 3–4) |
| Player character | ≤ 20k triangles, ≤ 5 surfaces, ≤ 4 bone influences, single-sided (§34) |

**Rules**

- **Every new visual feature declares its Low/Medium/High behaviour** in
  `GraphicsQuality.apply` (or uses a `NightLight`-style Low fallback), and Low
  must be meaningfully cheaper.
- **Prefer:** vertex colour, shared materials, MultiMesh, merged static meshes,
  short shaders. The Deck is weak on fill rate and bandwidth: avoid overdraw
  and big transparent particles.
- **Avoid:** real-time GI, SSR, SSIL, volumetric fog, DOF, motion blur, TAA
  (ghosting at speed), shadowed local lights, per-frame mesh or material
  rebuilds, `SCREEN_TEXTURE`, lots of small unique materials (shader-variant
  compile hitches).
- **Measure:**

  ```bash
  godot --path . --fixed-fps 120 -- --bench
  ```

  It prints draw calls, objects and render times; compare them with the
  baseline above. The Godot debugger's Monitors show draw calls, primitives
  and video RAM. `tools/release.sh X.Y.Z --dry-run` checks that the export
  builds and runs. The owner tests on the Deck before a release.
- **Update the baseline** in this section when a change moves it meaningfully,
  and record what the owner reports from real Deck play.

---

## 28. Visual consistency rules

1. **Scale:** 1 unit = 1 metre, with real dimensions (tables above). Check new
   assets in a screenshot next to a car (4.4 m) and a kerb (0.15 m).
2. **One light setup:** `DayNight` plus `world.tscn`. No extra directional
   lights or per-area environments (the garage's own world is the exception).
3. **Palette and materials** come only from §5 and §6. New colours are added to
   the tables first.
4. **Edges** are bevelled and smooth-shaded. No faceted organic shapes in new
   work.
5. **Grounding:** everything touches the ground with contact AO. Nothing floats
   or clips.
6. **Detail density follows camera proximity** (§8).
7. **Migrate by family.** Restyle a whole family at once: all buildings, all
   trees, all vehicles, all props, the road shader, the UI. Never put one
   building or one tree type in the new style next to old ones. New content in
   an unmigrated family matches that family's current look; say in the commit
   that it's legacy-style and will migrate with its family.
8. **Check every visual change at day, sunset and night, on Low and High.**
9. **Gameplay readability wins ties.** Road markings, race gates and start
   circles, ramp edges and hazards stay obvious even if that's less realistic.
10. **Single sources of truth:** lighting (`DayNight`), UI look (`UiKit`), road
    markings (`road_surface.gdshader`), car paint (`VehicleBodyVisual` or a shared paint
    material), world palette (`ArtPalette` in `scripts/world/art_palette.gd`:
    builders read it for base colours; small accents stay inline).

---

## 29. Things to avoid

**Style**
- Faceted low-poly or flat-shaded organic forms (trees, rocks, clouds, terrain)
  in new work.
- Toon or cel shading, outlines, inverted hulls, posterization, halftone,
  painterly filters.
- Candy or pastel saturated large surfaces, neon-green grass, primaries on
  walls, blue-tinted asphalt, pure black or white albedo.
- Chasing photorealism: photogrammetry, 4K textures, micro-detail noise, grunge
  overlays, wet-road reflections, ray tracing.
- Lighting, shadows or highlights baked into albedo; photo textures with
  lighting in them.
- Exaggerated proportions (giant wheels on ordinary cars, chibi cars), except
  the monster truck by design.

**Tech**
- SDFGI, VoxelGI, LightmapGI, SSIL, SSR, volumetric fog, gameplay DOF or motion
  blur, chromatic aberration, film grain, lens flares or dirt, heavy vignette,
  TAA.
- Shadows on omni or spot lights. More than one directional light in the world.
- Alpha-blended foliage. Big transparent particles near the camera. Full-screen
  effects.
- One material per object or per colour. Unique material variants created at
  runtime. Rebuilding meshes or materials every frame.
- Textures with no generator script or recorded CC0 source. Anything larger
  than 2048².
- Hand-editing `.glb` files or generated meshes. Changing an asset without
  updating its generator.
- Breaking the name contracts: `Paint`, `Headlight`, `TailLight`,
  `ReverseLight`, `Glass`, `FrontBumper`, `RearBumper`, `Spoiler`.
- More than 6,000 deformable vertices per vehicle. N-gon or fan topology on
  deformable panels. Open meshes for detachable parts.
- Exporting vertex colours on vehicles before the damage shader consumes them
  (it tints the paint).

**Content**
- Real brands, logos, trademarked car designs, real company names. Copying the
  reference images.
- Committing reference images or other third-party art to the public repo.
- Injury, blood, people getting hurt. Fire or explosions without the owner's
  request. Anything scary for a young child.

**UI**
- Text under 18 px (at the 1600×900 reference). Font glyphs or emoji as icons.
  A third font. Colours hardcoded outside `UiKit`. Clutter in the centre of the
  screen. Anything that only works with a mouse.

**Process**
- Restyling assets the task didn't ask for. Mixing old and new styles within a
  family. Shipping visual changes without day/sunset/night and Low/High
  screenshots and `--bench` numbers. Treating desktop fps as proof of Deck
  performance.

---

## 30. Workflow checklist for visual changes

1. Read §0 and the sections for the asset type.
2. Take **"before" screenshots** into the scratchpad, never the repo:

   ```bash
   godot --path . -- --tour=/tmp/shots/before
   ```

   Add `--night`, `--garage`, `--damage`, `--showcase` or `--map` as relevant
   (see the README's testing helpers).
3. Change the **generator** (Blender script, builder, shader, texture script),
   not its outputs.
4. Regenerate (`blender -b -P tools/blender/<script>.py`). Godot reimports on
   the next run.
5. Take **"after" screenshots** with the same commands and compare them side by
   side. Check Low and High (Settings), and day, sunset and night.
6. Run `godot --path . --fixed-fps 120 -- --bench` and compare draw calls and
   objects with §27. Mention any change in the commit message.
7. Run the existing tests for the area: damage → `--damage`; vehicles →
   `--garage`, `--showcase`, plus the physics autotests if collision or wheels
   changed; menus → `--menus`.
8. Add a line under `## [Unreleased]` in CHANGELOG.md for anything a player
   would notice. Update this bible if you set a new rule or value.
9. Commit with a clear message. Releases happen only when the owner asks
   (RELEASING.md).

---

## 31. Suggested migration order (only when the owner asks)

Cheapest and biggest wins first:

1. ✅ **Lighting, atmosphere and palette regrade** (done 2026-10-01):
   `DayNight.KEYS`, AgX, aerial fog, sky colours, then terrain, grass, asphalt,
   concrete, vegetation and building colours (`ArtPalette`). Also fixed
   speckled windows (unstable shader hash) and Low-quality shadow striping at
   sunset.
2. ✅ **Smooth shading and bevels for world geometry** (done 2026-10-01 with
   the environment upgrade): `MeshBuilder` shape helpers, smooth trees and
   rocks, soft clouds in the sky shader.
3. ✅ **Roads:** asphalt variation, marking wear, sidewalk paving, Jersey
   barriers, overpass detail, drainage streaks. Done (2026-10-01, on `dev`)
   together with steps 6 and 7, landmarks, props, terrain and sea: previewed
   in a representative area first, then rolled out to the whole map once the
   owner approved the look.
4. ✅ **Vehicles** (done 2026-10-01 on `dev`): every body remodelled with
   deformation-ready topology, interiors and better wheels; clearcoat car
   paint; glass. The sports car prototype came first and set the quality bar
   (`body_kit.py`, `make_car.py`), with faster dents and clear coat for all
   paint; then the other seven, one design language per class (§12), four
   wheel types, the `PaintPalette` garage and traffic colours, and garage
   racing stripes.
5. **Damage 3.0:** crumple stiffness and structure behind detachable parts.
   The scrape/primer/bare-metal layer, the cracked-glass pattern and broken
   lamps with shards were done in the vehicle realism pass (2026-10-02).
6. ✅ **Buildings:** facade grammar (base, middle, top), districts, roof clutter,
   chunking.
7. ✅ **Vegetation:** card-based trees, palms, chunked MultiMeshes with LOD.
8. **UI:** font, type scale, icons, gamepad prompts.
9. **Effects:** lit smoke, surface-coloured dust, water splash, landing puffs.

---

## 32. Open owner decisions

- **Font:** Barlow is suggested. It needs a download of OFL font files.
- **Fire and explosions in crashes:** off unless the owner wants them.
- ~~Traffic colours~~ and ~~player paint list~~: decided 2026-10-01 (§5).
- ~~Racing stripes~~: decided 2026-10-01, a garage option, never on traffic
  (§12).
- **Next migration step** (§31), and when to merge `dev` into `main`.
- **Guardrails** on the mountain and hill roads would stop cars driving off
  the road (gameplay). Wanted, and where?

---

## 33. Vehicle sound

Sound follows the same direction as the look: **believable first**, clean and
readable, kid-friendly (crashes are big and fun, never scary).

- **Sources:** real recordings where they beat what we can make, synthesis
  where it's as good (electronic beeps, wind, hisses, starters, knocks).
  Licences per `ASSET_MANIFEST.md` (CC0/public domain first, CC BY with the
  attribution in the manifest and the CREDITS page; never BY-SA, NC, GPL or
  ripped material). Every file comes out of `tools/audio/build_audio.py`
  (pinned URLs + SHA-256, fixed seeds); never hand-edit `assets/audio/`.
- **Engines are layered, never one loop:** steady loops at known rpm, on and
  off load, crossfaded with equal power by rpm and blended by load
  (`VehicleAudio`). New engine character = a new set in `recorded.py` plus a
  profile in `tools/audio/profiles.py`. Keep pitch factors between ~0.6 and
  1.6 (the loops' rpm should cover idle to redline after `rpm_scale`;
  `audio_check.gd` enforces it).
- **Levels:** loops are written at −18 dBFS RMS, one-shots peak at −1 dBFS;
  dB numbers in profiles and `VehicleAudio` are relative to that. A hard
  limiter on the master bus catches pile-ups. The player's vehicle plays
  **without distance attenuation** (the camera trails it at a fixed
  distance), through the Player bus at +4 dB, so the numbers are what you
  hear: engine at full throttle 0 dB (the loudest steady sound; idle about
  −6), start-up −7, tyre squeal up to −4.4, horns −6 to −9, air brake −11,
  reverse beeper −9. (Until 2026-10-02 it was 3D with `max_db` 0, which
  capped every loud sound at one level: the start-up and squeal came out as
  loud as the engine at full throttle.)
- **Small speakers** (owner, 2026-10-02: quiet engines on the Steam Deck):
  the Deck's speakers play almost nothing below ~300 Hz, where most of an
  engine recording is (the inline six loses ~13 dB, the diesel ~10, the
  fours ~5; squeal, horns and hisses lose nothing). Check every mix change
  through a Deck speaker model too (`highpass(x, 300 Hz, 4th order)` on an
  `--audio --speakers=on --stems` recording), not only full range.
- **Mix architecture** (`AudioMix`, 2026-10-02, owner: engine too quiet on
  the Deck against road, grass, brakes and crashes; skids and metal too
  piercing everywhere). The player's vehicle feeds category buses: Engine,
  Tyres (road, suspension), Surface (gravel, grass), Skid (squeal, air
  brakes), Impacts (crashes, metal, glass, debris, scraping), Environment
  (wind, water), Signals (horn, beeper), all into the Player group bus
  (tunnel reverb, +4 dB). Traffic: Traffic (de-harsh shelf, compressor) and
  TrafficEngine; UI for menu sounds. Master: speaker tone, glue compressor,
  limiter at −1 dBFS (nothing clips). Processing: the engine gets a
  **harmonic exciter** (Godot's waveshape distortion below ~300 Hz only: the
  firing note grows odd harmonics the small speakers can play), a tone EQ
  and a compressor; Skid and Impacts get a −6 to −9 dB high shelf from
  2.5–3 kHz, a low-pass and fast compression (Impacts also a limiter).
  **Hierarchy** while driving: engine on top; road ~10–14 dB under it,
  gravel ~9–15, skid in a slide ~6–11, crashes about level with the engine
  in a short burst. Two profiles, "flat" (PC, headphones) and "deck"
  (setting "Speaker boost": Auto = deck on a Steam Deck), with the tuned
  values in `assets/audio/mix.cfg` once saved. Godot's compressor doubles
  its overshoot, so its `ratio` reads far stronger than it is: `AudioMix`
  works in real ratios (`godot_ratio`). Godot's 10-band EQ isn't flat at
  0 dB (about +2.5 dB with ripple): use shelves for gentle tone.
- **Tuning live:** the dev audio panel (`AudioMixPanel`: F8, or hold both
  sticks in for a second; touch on the Deck) has every fader and setting,
  meters, mute / solo, and saves to `user://audio_mix.cfg`. Off for a
  release: `turbo_town/dev/audio_mix_panel=false` in project.godot.
- **Seamless:** loops are crossfaded at the seam (and cut on whole periods
  for pitched ones like horns); Godot imports everything as QOA (about a
  fifth of PCM; loops measured seamless). Players fade in over 40 ms, pause
  only after 0.15 s of silence, and the player's loops are primed silently
  so every start is a resume. `--audio` + `check_recording.py` should find
  no clicks, dropouts or clipping; it can flag a sharp natural onset (a
  throttle bark, a gravel crunch), so look at what it flags.
- **Tyres sit under the engine** (owner, 2026-10-02: the first road sound
  was a hissy roar and annoyed): road roll is a dark roar, nothing above
  ~2 kHz but enough at 300-800 Hz for the Deck's small speakers, rising
  ~10 dB per doubling of speed (full at ~100 km/h) with little pitch change.
  Tyre squeal only in a real slide (from where skid marks start, skid
  0.2-0.5); light wheelspin pulling away stays quiet. No brake squeal.
- **Budget (Steam Deck):** the player's vehicle may play ~10–14 voices at
  once; traffic gets loops for the nearest 6 cars within 95 m (2 engine
  layers + tyres each, `AudioDirector`), plus short crashes and horns. Engine
  loops are stored at 32 kHz, off-load loops at 22.05 kHz, the rest at
  44.1 kHz; `assets/audio/` stays under ~15 MB in the repo (QOA in the
  build).
- **Kid safety:** no screams, sirens of panic or injury sounds. Horns are
  friendly, crashes are metal and glass.

## 34. Characters

The player's character (2026-10-03, the on-foot milestone). Same direction as
everything else: **stylized realism**, believable first.

- **Proportions:** a real adult, ~1.8 m, ordinary fit build (no
  bodybuilder, no chibi, no big heads or hands). Silhouette reads at 30–60 m:
  a clear head, a shirt shape, legs.
- **Face:** simple and friendly: nose, brow, ears, simple eyes, eyebrows,
  short hair with some volume. No photoreal skin, pores, wrinkles or
  subsurface tricks; nothing uncanny. At the on-foot camera (3.6 m, 70° FOV)
  the face is ~25 px tall on the Deck: the shape matters, not detail.
- **Clothes:** real shapes (sleeves with hems, a waistband, trouser cuffs,
  sneakers with a sole band), not colours painted on a body. The shirt is a
  medium-saturation colour so the player spots their character in a
  naturalistic world (a gameplay element, like a vehicle's paint, §0 rule 2).
- **Materials:** flat PBR colours (a tiny palette texture at most), one
  surface per material: skin ~0.55 roughness, cotton ~0.85, denim ~0.8,
  shoes ~0.6, hair ~0.6. Albedo within sRGB 0.11–0.94. Today: five materials sharing one 16×16
  palette texture (4×4-texel cells; every face's UVs sit on one cell centre,
  so mips never blend cells): `Char_Skin` 0.55 (skin sRGB 0.76, 0.56, 0.44;
  lips, mouth and eyes are cells on it), `Char_Hair` 0.6 (dark brown 0.21,
  0.14, 0.10, also the brows), `Char_Shirt` 0.85 (red-orange 0.77, 0.30,
  0.20: the world is greens, greys, sand and sea blue, and it stays clear of
  the UI yellow and marker colours), `Char_Trousers` 0.8 (denim 0.21, 0.30,
  0.46), `Char_Shoes` 0.6 (off-white upper 0.88, 0.87, 0.84, dark sole 0.31,
  0.30, 0.29). **Single-sided**: the surface is closed; double-sided
  materials (Blender's default, exported as glTF `doubleSided`) cost +1.3 ms
  on the iGPU at Medium.
- **Rig and animation:** the Universal Animation Library (Quaternius, CC0)
  skeleton, 53 bones, all clips in place (no root motion); the game moves the
  body and scales clip speed to ground speed (`PlayerCharacter`: walk
  1.45 m/s, jog 4.0, sprint 6.4 at speed 1). Never re-time clips in the
  model: tune `*_anim_speed` instead.
- **Generator:** `tools/blender/make_character.py` downloads the library
  (pinned URL + SHA-256) and rebuilds the mesh; never hand-edit
  `assets/models/character/player.glb`. It fuses the mannequin's ~100
  segments into one skin (a signed-distance volume, 3.5 mm voxels), slims it
  toward the bones, sculpts a head, hair, T-shirt, jeans and sneakers into
  the volume, meshes and decimates it (face kept denser), cuts the surface
  exactly along each material border, transfers and smooths the weights and
  exports the kept clips. ~25 s, the same file every run.
- **Budget:** ≤ 20k triangles, ≤ 5 surfaces, ≤ 4 bone influences per vertex,
  no textures over 256². Same on every quality level (one skinned mesh is
  cheap; it casts the sun shadow on all levels, it's what grounds it).
  Measured (2026-10-03): 17,286 triangles, 8.6k vertices, 5 surfaces, 53
  bones, 1.6 MB. In the city centre with traffic it adds ~10–13 draw calls;
  GPU time is lost in the noise (RTX: none; iGPU at Medium ≈ +0.2 ms,
  alternating A/B). CPU: the character, its input and the interaction scan
  take ~0.13–0.16 ms per physics tick on the dev CPU (~0.3 ms per 60 fps
  frame). In a vehicle it's hidden with physics and animation off: driving
  costs the same as before (`--bench` A/B).
- **Kid safety:** the character can't be hurt. A car that drives into it
  shoves it aside with a short stagger (no ragdoll, no injury or death
  animation, no sound of pain; the library's death clip is left out); it
  can't fall to its death (the sea or the void respawns it).
- **Look-dev:** `--charsheet=<dir>` shoots it from fixed cameras at day,
  sunset and night plus strips of every locomotion clip.

---

*Revision log*
- 2026-10-01: created (stylized realism direction, from three reference
  images; baseline measured at v0.3.1).
- 2026-10-01: step 1 done; §3, §5, §6, §7, §9–§11, §15, §27, §28 and §31
  updated with the tested values.
- 2026-10-01: step 4 sports car prototype; §3, §13, §14 (corrected dent-cost
  measurements), §24, §27 and §31 updated.
- 2026-10-01: step 4 done (whole fleet); §3, §12 (fleet design languages,
  measured dimensions), §13 (new fixed materials), §14, §24 (per-vehicle
  scripts, legacy extruder removed), §26, §27 (fleet A/B baseline, surface
  budget clarified) and §31 updated.
- 2026-10-01: environment upgrade preview (`ArtZone`); §3, §5, §6, §7, §9
  (neutral day ambient), §11 (sky shader clouds), §15–§19, §27 and §31–§32
  updated.
- 2026-10-01: environment upgrade rolled out to the whole map (owner
  approved); legacy builders, shaders and materials removed. §3, §5, §6, §7,
  §15–§19, §26 (per-block chunks, automatic LODs), §27 (new baseline), §28
  and §31 updated.
- 2026-10-02: vehicle realism pass (on `dev`): vehicle shaders, the player's
  reflection probe, indicators, calipers, grime, contact shadow, the paint
  damage layer and cracked-glass pattern. §3, §6, §7, §9, §10, §12, §13, §14,
  §24, §27 and §31 updated; §33 (vehicle sound) added.
- 2026-10-02: §33 tyre rule after the owner's first listen (softer, darker
  road roll; squeal only in slides; brake squeal removed).
- 2026-10-02: §33 levels and small speakers after the owner's Steam Deck
  listen (player sounds unattenuated, explicit levels; speaker boost).
- 2026-10-02: §33 mix architecture (category buses, exciter, de-harshing,
  hierarchy, profiles) and the dev audio panel.
- 2026-10-02: garage wheels (on `dev`): rims and tyres as separate parts
  with one standard rim fit, rim finishes, tyre stripes, calipers only on
  open rims. §12, §24, §26 and §27 updated.
- 2026-10-03: the player character (branch `player-character`): §34
  Characters added; §27 baseline (on-foot cost). §0 rule 6 and §27 target:
  60 fps on the Deck is the Medium preset's job, High/Ultra may be heavier,
  no relying on frame generation (owner, 2026-10-03).
