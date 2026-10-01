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

Contents: 0 Quick rules · 1 Identity · 2 References · 3 Today's baseline ·
4 Stylization dial · 5 Colour palette · 6 Materials/PBR · 7 Shaders ·
8 Textures/detail · 9 Lighting · 10 Shadows · 11 Sky/atmosphere ·
12 Vehicle design · 13 Vehicle materials · 14 Damage/deformation ·
15 Buildings · 16 Roads/highways · 17 Props · 18 Vegetation ·
19 Terrain/water · 20 UI · 21 Typography · 22 Icons · 23 Effects ·
24 Blender · 25 Godot import · 26 LOD/detail · 27 Steam Deck ·
28 Consistency rules · 29 Avoid list · 30 Workflow · 31 Migration order ·
32 Open owner decisions

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
6. **60 fps on the Steam Deck.** Budgets are in §27. Every new effect has
   Low/Medium/High behaviour in `GraphicsQuality`.
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

As of v0.3.1 (2026-10-01), the game uses a bright toy low-poly style:

| Area | Today | Target |
|---|---|---|
| Geometry | `MeshBuilder` flat-shades every triangle. Trees, rocks and clouds are faceted blobs. Vehicle bodies are side profiles extruded with `extrude_profile`, plus box parts. | Smooth shading with bevels. Deformation-ready vehicle topology. |
| Textures | None. Everything is vertex colour or a procedural shader (road markings, windows, water). | Stay procedural-first. Add small generated detail textures where they pay off (§8). |
| Palette | Pastel saturated buildings (`CityBuilder.PALETTE`), bright green grass, blue-tinted asphalt, `adjustment_saturation = 1.15`. | Naturalistic palette (§5), saturation 1.0. |
| Lighting | A good base: sun plus time-of-day keys (`DayNight.KEYS`), SSAO on High, Filmic tonemap, light fog. | More sun/shadow contrast, cooler shadows, more aerial haze (§9, §11). |
| Sky | `ProceduralSkyMaterial` in saturated blue. Faceted mesh clouds. | A paler, hazier horizon and soft clouds. |
| Vehicles | Bodies of 1.6–2.6k tris, 8 cm arch gaps, opaque glass, no interior, racing stripes on the sports car. | §12–13. |
| Damage | Vertex dents (smoothstep falloff, bent normals). Bumpers and spoiler fall off. Lights and glass break. Smoke and sparks. | Add a scrape/primer/bare-metal layer, crumple stiffness, and structure behind lost parts (§14). |
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
first.**

**Rules**

- **Large surfaces** (terrain, walls, roads, sea, big props): chroma ≤ 0.35.
  Chroma here means the highest sRGB channel minus the lowest, on a 0–1 scale.
  Today the pastel buildings are 0.36–0.67 and the grass is 0.39.
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
| asphalt | `#46474A` | `(0.275, 0.278, 0.290)` | road base (today `(0.30, 0.31, 0.35)`, too blue) |
| asphalt_dark | `#393A3D` | `(0.224, 0.227, 0.239)` | repairs, fresh patches, wheel paths |
| asphalt_worn | `#5A5B5D` | `(0.353, 0.357, 0.365)` | worn, sun-bleached patches |
| paint_white | `#E4E2DA` | `(0.894, 0.886, 0.855)` | lane lines, zebra crossings |
| paint_yellow | `#D9A421` | `(0.851, 0.643, 0.129)` | centre and edge lines |
| concrete | `#B4B0A7` | `(0.706, 0.690, 0.655)` | barriers, decks, pillars |
| concrete_stained | `#8E8A82` | `(0.557, 0.541, 0.510)` | bases, drip streaks, joints |
| sidewalk | `#BDB8AE` | `(0.741, 0.722, 0.682)` | paving |
| curb | `#A8A39A` | `(0.659, 0.639, 0.604)` | kerbs |
| grass | `#5E7F3A` | `(0.369, 0.498, 0.227)` | lawns, lowland (today `(0.43, 0.72, 0.33)`, too bright) |
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

### Sky keys (targets for `DayNight.KEYS`)

| Key | Today | Target |
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
| Lit window | `#FFCC80` | `(1.000, 0.800, 0.502)` (matches `building.gdshader` today) |

### Vehicle paints

The player palette keeps today's ten hues (`VehicleCatalog.COLORS`) with values
tuned toward real car paints. The garage swatches stay in the same order.

| Slot | Today | Target hex | Godot `Color` | Finish |
|---|---|---|---|---|
| Red | `(0.93, 0.22, 0.14)` | `#C8231B` | `(0.784, 0.137, 0.106)` | solid |
| Orange | `(1.0, 0.55, 0.15)` | `#E0661B` | `(0.878, 0.400, 0.106)` | solid |
| Yellow | `(1.0, 0.8, 0.12)` | `#E8B51E` | `(0.910, 0.710, 0.118)` | solid |
| Green | `(0.3, 0.8, 0.35)` | `#2E7D3E` | `(0.180, 0.490, 0.243)` | metallic |
| Teal | `(0.2, 0.75, 0.8)` | `#1D8C8F` | `(0.114, 0.549, 0.561)` | metallic |
| Blue | `(0.22, 0.5, 0.95)` | `#2355C4` | `(0.137, 0.333, 0.769)` | metallic |
| Violet | `(0.6, 0.38, 0.9)` | `#6A2FA8` | `(0.416, 0.184, 0.659)` | metallic (Ref 1) |
| Pink | `(0.97, 0.45, 0.65)` | `#D45683` | `(0.831, 0.337, 0.514)` | solid |
| White | `(0.95, 0.95, 0.93)` | `#E6E6E1` | `(0.902, 0.902, 0.882)` | solid (pearl) |
| Graphite | `(0.16, 0.17, 0.2)` | `#2A2C30` | `(0.165, 0.173, 0.188)` | metallic |

**Traffic paints** (per-vehicle `paint_palette` on the `Body` node): use real
street proportions. At least 70% neutrals, 20–25% muted colours, at most 10%
bright. That way the player's car pops.

| Name | Hex | Godot `Color` |
|---|---|---|
| silver | `#A9ADB2` | `(0.663, 0.678, 0.698)` |
| grey | `#6B6E73` | `(0.420, 0.431, 0.451)` |
| black | `#1E1F22` | `(0.118, 0.122, 0.133)` |
| white | `#E6E6E1` | `(0.902, 0.902, 0.882)` |
| navy | `#22324F` | `(0.133, 0.196, 0.310)` |
| dark red | `#7A1E1E` | `(0.478, 0.118, 0.118)` |
| beige | `#B9AC92` | `(0.725, 0.675, 0.573)` |

Buses and delivery trucks use fixed liveries for invented companies (city
yellow for buses, as today).

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
| Asphalt | asphalt | 0.85–0.95 | 0 | markings 0.6–0.7 (today −0.2 in `road.gdshader`) |
| Concrete | concrete | 0.85–0.9 | 0 | |
| Paving / kerb | sidewalk / curb | 0.85 | 0 | |
| Stucco / plaster | building palette | 0.9 | 0 | |
| Limestone | limestone | 0.8 | 0 | |
| Brick | brick | 0.9 | 0 | mortar lines lighter, about +15% value |
| Building window glass | dark blue-grey | 0.05–0.15 | 0 | today `building.gdshader` uses metallic 0.2. Prefer 0 with low roughness. |
| Curtain wall glass | curtain_glass | 0.05–0.1 | 0 | |
| Painted metal (poles, signs) | per object | 0.45–0.6 | 0 | paint is not metal |
| Galvanised steel (guardrails) | `#A7ABAE` | 0.4–0.5 | 1 | |
| Corrugated / roof metal | `#8E9296` | 0.45–0.6 | 1 | |
| Plastic (cones, barrels, bins) | hazard colours | 0.5–0.65 | 0 | |
| Wood | warm browns | 0.75–0.9 | 0 | |
| Rubber / tyre | `#1C1C1E` | 0.85–0.95 | 0 | |
| Grass / foliage | vegetation palette | 0.8–0.95 | 0 | specular 0.25–0.35 |
| Bark / rock / sand | palette | 0.85–0.95 | 0 | |
| Water | sea palette | 0.02–0.1 | 0 | today metallic 0.1. Use 0. |
| Car paint | paint palette | 0.25–0.4 | 0 (solid) / 0.4–0.6 (metallic) | clearcoat (§13) |
| Chrome | `#D9DBDE` | 0.08–0.15 | 1 | sparingly |
| Aluminium rim | `#B8BBBF` | 0.3–0.4 | 1 | |
| Vehicle glass | `#1E2833` | 0.03–0.08 | 0 | today metallic 0.5 (legacy) |
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
  `building.gdshader`). Uniforms with the `source_color` hint are converted
  automatically.
- **Vertex colour alpha is a flag channel** in the world shaders: windows on or
  off in `building.gdshader`, deck sides in `road.gdshader`. Document any new
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
| `road.gdshader` | procedural lane markings and asphalt patches | `UV.x` = metres across (0 = centre), `UV.y` = metres along. `COLOR.a < 0.5` = plain concrete deck side. Per-road-type parameters live in `road_*.tres`. |
| `intersection.gdshader` | zebra crossings | `UV` = metres from the centre. `COLOR.rgba` = road present on the N, E, S, W sides. |
| `building.gdshader` | wall colour plus procedural windows | `UV` = metres (u along the wall, v up). `COLOR.a = 0` turns windows off. The `night` parameter is set by `DayNight`. |
| `water.gdshader` | animated normals, near-shore tint | world-space position |
| `minimap.gdshader` | round, heading-up minimap (canvas_item) | |

**Rules**

1. **Header comment is mandatory.** Document the UV, COLOR and uniform
   conventions, as the existing shaders do.
2. **Extend shared shaders, don't fork them** per object. Vary per object
   through vertex colour, `instance uniform`, or a few shared material
   variants.
3. **Antialias procedural lines with `fwidth`** (see `line_mask` in
   `road.gdshader`), and fade high-frequency detail with distance (`fade` in
   `building.gdshader`). Nothing may shimmer at 1280×800.
4. **Fragment budget for world surfaces:** ≤ 4 texture samples (≤ 6 on
   High-only paths). No loops longer than about 8 iterations. No `discard`
   except alpha-scissor foliage. No `SCREEN_TEXTURE` or `DEPTH_TEXTURE` reads
   (the one possible exception is water on High, if justified).
5. **Global state:** today `DayNight` sets `night` directly on `building.tres`.
   Once a second shader needs time of day, wetness or quality, switch to global
   shader uniforms (Project Settings → Shader Globals, `global uniform float
   night;`) rather than setting each material.
6. **Quality-aware:** when shaders need to drop detail on Low, add a global
   `quality` uniform (0/1/2) and set it from `GraphicsQuality.apply`.
7. **Lit, not unshaded.** World surfaces use normal lighting. Use `unshaded`
   only for the sky, stars, UI, sparks and emissive markers. Today tyre smoke
   and dust are unshaded, so they glow at night. Fix that when touching effects
   (§23).
8. **Break up repetition** with world-space macro noise (like the patch hash in
   `road.gdshader`). Use triplanar mapping for terrain cliffs and rocks.
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

**Principles** (from Refs 1 and 2)

- **One dominant warm key** (the sun) plus cool sky fill. At midday, sunlit
  areas are about 3–4× brighter than shadows. Shadows are clearly readable but
  never black.
- **Warm light, cool shadows**, achieved with a warm sun colour and blue-ish
  ambient. Never by tinting albedo.
- **Presets** (`DayNight.PRESET_HOURS`): day at 14:00, which is the default;
  sunset at 17:45, the hero look (Ref 2); night at 23:00.
- **Night is moonlit blue, not black.** Roads and buildings stay readable for a
  kid. Warm pools under street lamps, lit windows, headlights.

**Target key values.** These are starting points: tune them by screenshot and
record the final numbers in `DayNight.KEYS`.

| Key | Today | Target |
|---|---|---|
| Day sun | `(1.0, 0.97, 0.9)` × 1.25 | `(1.0, 0.95, 0.86)` × 1.3–1.5 |
| Day ambient | `(0.8, 0.88, 1.0)` × 0.9 | `(0.62, 0.74, 0.95)` × 0.55–0.7 (lower = stronger shadows) |
| Sunset sun | `(1.0, 0.55, 0.3)` × 1.0 | `(1.0, 0.6, 0.35)` × 1.1–1.3 |
| Sunset ambient | `(0.9, 0.65, 0.55)` × 0.6 | `(0.55, 0.55, 0.75)` × 0.45–0.55 (warm key, cool violet shadows) |
| Night moon | `(0.55, 0.65, 1.0)` × 0.22 | keep |
| Night ambient | `(0.35, 0.42, 0.7)` × 0.3 | `(0.3, 0.38, 0.62)` × 0.3–0.4 |

**Environment target (High)**

- **Tonemap:** test AgX against the current Filmic. Pick one by screenshot and
  keep it.
- **Exposure:** sunlit concrete should read about 0.75–0.85 sRGB on screen.
- **`adjustment_saturation` 1.0** (today 1.15). If a global grade is needed,
  use one 3D LUT through `adjustment_color_correction`, generated by a script.
- **Glow** on Medium and High only (as today): intensity 0.3–0.5, HDR threshold
  ≥ 1.0, so only emissives, sun glints and sparks bloom.
- **SSAO** on High only (as today). Baked AO everywhere.
- **Reflections:** sky radiance by default. Up to 4 `ReflectionProbe`s with
  `UPDATE_ONCE` may cover the city core on Medium/High for paint and glass
  reflections. Never `UPDATE_ALWAYS`.
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
World3D (`vehicle_picker.gd`: key 1.4, fill 0.4, ambient 0.75, Filmic). Vehicles
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
  shadow-casting, plus contact AO under the body. A dark multiply-blend quad
  under each car (`BLEND_MODE_MUL`, soft vertex-alpha falloff) is allowed as
  extra grounding.
- **Cast shadow OFF** for: particles, skid marks, road markings and decals,
  clouds and sky elements, water, emissive lamp heads, props smaller than
  ~0.3 m, glass shards, distant vegetation impostors.
- **Terrain casts.** The mountain at sunset is a hero moment.
- Fix acne or peter-panning once, on the sun's `shadow_bias` and
  `shadow_normal_bias`. Never with per-object hacks.
- No baked or painted shadows in albedo.

---

## 11. Sky and atmosphere

- **Sky colours** per hour come from `DayNight.KEYS`; targets are in §5:
  a paler, hazier horizon and a mid-saturation zenith.
- **Aerial perspective:** exponential depth fog whose colour is the horizon
  colour (DayNight sets `fog_light_color`). Use `fog_aerial_perspective`
  0.3–0.6 so the fog picks up the sky, and `fog_sun_scatter` 0.1–0.25 for a
  warm glow toward the sun (Ref 2). Pick a density that fogs about 40–55% at
  800–900 m, roughly 0.0006–0.0009 (today 0.00045). Keep `fog_sky_affect` at 0.
- An optional, subtle height-fog layer near sea level for coastal haze.
- **The sea melts into the haze at the horizon** (Ref 1). No hard horizon line.
- **Clouds:** soft, round-topped fair-weather cumulus. Target: drawn in a sky
  shader (two scrolling layers of a tileable 256–512² generated noise texture,
  lit with the sun colour, darkened at night) or as smooth billboards. **No
  faceted mesh clouds.** Today `NatureBuilder._add_clouds` builds faceted blobs
  (legacy).
- **Sun:** a visible disk with a soft glow (today `sun_angle_max` 20°). No lens
  flares or ghosts. Moon and stars at night (as today).
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

**Must-have details (as geometry)**

- Panel shut-lines (bonnet, doors, boot) as 5–8 mm dark grooves on the
  deformable shell, so they bend with dents.
- Headlights with housing, lens and inner reflector. Tail lights with lens and
  an inner emissive element. Amber indicators are welcome.
- Grille openings with depth (a dark recess). Mirrors on stalks. Small door
  handles. Exhaust tips. A licence-plate recess (blank plate or "TURBO").
- Dark wheel-well liners and a simple dark underbody, so you never see through
  to the sky.
- A simple interior (seats, dash, steering wheel) in dark materials, 300–800
  tris, visible through the glass.

**Wheels:** multi-spoke rims with depth (5–10 spokes). The sports car shows a
dark brake disc and a coloured caliper behind the spokes. Tyres have rounded
shoulders and a slightly lighter sidewall; off-road tyres get chunky tread as
geometry. **The visual radius must match the physics wheel radius** in the
vehicle scene.

**Liveries:** racing stripes and graphics are a hero/player option, not a
traffic default. Buses and trucks carry invented company liveries.

**Reference dimensions (metres).** The vehicle scenes (`scenes/vehicles/*.tscn`)
are the authority for wheel positions and radii.

| Class | Length | Width | Height | Today's model |
|---|---|---|---|---|
| Sports coupé | 4.3–4.6 | 1.85–1.95 | 1.15–1.30 | 4.4 × 1.94, wheels r 0.37 at x ±0.83, axles ±1.35 |
| Sedan | 4.6–4.9 | 1.80–1.88 | 1.40–1.48 | r 0.34, x ±0.80, axles ±1.40 |
| Van | 4.9–5.4 | 1.95–2.05 | 1.9–2.2 | r 0.36, x ±0.86, axles ±1.50 |
| Pickup | 5.2–5.8 | 1.9–2.05 | 1.8–1.95 | see scene |
| Box truck | 6.5–8.0 | 2.3–2.5 | 3.2–3.6 | see scene |
| City bus | 11–12.5 | 2.5–2.55 | 3.0–3.3 | see scene |
| Buggy, monster truck | fictional, keep current proportions | | | see scene |

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
| `Trim`, `Chrome`, `Stripe`, `Tire`, `Rim`, `Hub`, `Cage`, `Frame`, `Box` | fixed looks | per §6 |

New names are fine for fixed materials. Add them to this table.

**Car paint**

- **Solid:** albedo from the palette, metallic 0, roughness 0.28–0.35,
  clearcoat 1.0, clearcoat roughness 0.05–0.12.
- **Metallic:** metallic 0.4–0.6, roughness 0.3–0.4, same clearcoat.
- **Matte** (rare; buggy or monster truck): roughness 0.55–0.7, no clearcoat.
- **Define the paint look in one place.** Today `VehicleBodyVisual._prepare_materials`
  duplicates each model's `Paint`. When adding clearcoat or flake, put it there
  or in a shared `car_paint.tres` so every vehicle changes together. The finish
  (solid or metallic) belongs with the palette entry, not with each model.

**Other vehicle materials**

- **Glass.** Target: alpha-blended tint `#1E2833` at alpha 0.65–0.8, roughness
  0.03–0.08, metallic 0, but only once the vehicle has an interior. Until then
  keep glass opaque and dark. Cracked glass is an opaque, whitish spiderweb.
- **Lights:** lens albedo near white, red or amber, roughness 0.05–0.15.
  Emission energies today: headlight 2.0 (in the model), tail running light
  0.8, brake 4.0, reverse 2.5. Daytime running lights about 1.5.
- **Trim, rims and running gear:** black trim plastic `#222326` at roughness
  0.6. Chrome `#D9DBDE` at roughness 0.1, metallic 1, used sparingly; with sky
  reflections only, big chrome areas look flat. Aluminium rims `#B8BBBF` at
  roughness 0.35, metallic 1. Tyres `#1C1C1E` at roughness 0.9, sidewall
  about 5% lighter. Brake disc `#5A5C5E`, metallic 1, roughness 0.5. Caliper
  is an accent colour.
- **Interior:** dark greys `#2A2B2E`–`#3A3B3F`, roughness 0.7–0.9, no emission.

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

**Material damage** (target, not implemented yet)

- **Layer order:** clean paint → scuffed paint (+0.2 roughness, slightly
  lighter) → primer `#8C8C88` at roughness 0.7 → bare steel `#9A9C9E`,
  metallic 1, roughness 0.35. Scrapes are long streaks along the direction of
  travel at the contact point. Impacts make patches.
- **No** rust, burn marks or age dirt: crashes are instant.
- **Driven by a per-vertex mask** in the car paint shader, so damaged cars need
  no extra textures.
- **Broken lights:** the lens goes dark grey (`#2E2E31`, roughness 0.9) with no
  emission (as today). Target: add a few lens shards and an exposed dark
  reflector.
- **Cracked glass:** today a flat light-grey material. Target: a procedural
  crack pattern centred near the impact.

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
  3,000–5,000.** Measured 2026-10-01 on the dev machine: about 0.15 µs per
  vertex per pass (the sports car's 2,252 vertices take 0.33 ms per pass). One
  crash runs several passes, and the Deck's CPU is slower. Going over the cap
  needs a code change first, such as excluding interior and underbody meshes
  or moving dents into a vertex shader. Plan that change; don't silently
  exceed the cap.
- **Topology:** deformable panels need evenly spaced vertices, about 8–15 cm
  apart on large panels (doors, bonnet, roof, sides), quads where possible.
  **No big n-gons or triangle fans.** Today `extrude_profile` closes each side
  of the body with one n-gon, so a dent in the middle of a door moves almost
  nothing. Fix that when remodelling. Avoid long thin triangles.
- **Per-vertex damage data (reserved layout):** an authored crumple factor (1 =
  soft: bumpers, bonnet, wings, boot; ~0.5 doors; ~0.25 pillars, roof, cabin),
  plus runtime scrape and paint-loss masks written by `VehicleDamage`. The
  preferred channel is vertex colour: R = crumple, G = scrape, B = paint loss,
  A = reserved. **Don't export vertex colours on vehicles until the shader and
  code that consume them exist.** glTF multiplies `COLOR_0` into the base
  colour, so the paint would be tinted. When implementing, make sure vehicle
  materials don't use vertex colour as albedo.

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
  `building.gdshader` (`floor_height`, `window_spacing`). Windows look recessed
  0.15–0.25 m (faked in the shader with a darker inner frame and reflective
  glass). Sills and lintels as trim bands.
- **Top:** a 0.5–1.2 m cornice or parapet, plus roof clutter: HVAC boxes, water
  tanks, stair housings, antennas. These are cheap boxes and cylinders (10–30
  tris each), merged.

**Variety and colour**

- Pick a material family and a palette colour per building, then vary value by
  ±5%. Neighbours differ in family or colour; at most two adjacent buildings
  share a family. Heights vary, and the downtown core is taller (as today).
- **Night:** about 55% of windows lit (today `step(0.45, hash)`), mostly warm
  with small variation, plus some cool-white office floors.

**Materials and construction**

- Plaster/stucco, concrete, limestone, brick (pattern from shader lines or a
  tiling texture), glass curtain wall with a mullion grid of 1.5 m × floor
  height, metal cladding for industrial buildings.
- Generated by `CityBuilder` (or by Blender scripts as modular kits), merged
  into chunked meshes (§26), with simple box colliders (as today).
- **Grounding:** darken the bottom 0.5–1.0 m of walls with an AO/grime gradient
  in vertex colour. Add subtle vertical streaks under sills and parapets. Both
  are cheap realism.

**Avoid:** windowless boxes, uniform window grids with no base or top, pastel
candy colours, every building the same height, floating buildings (always sit
them on the sidewalk slab), visible interior faces.

---

## 16. Roads and highways

Geometry is generated by `RoadBuilder`; markings come from `road.gdshader` and
`intersection.gdshader`. **Keep the widths in `MapLayout`.** They're tuned for
gameplay: city road 12 m (two 2.8 m lanes each way), highway three 3.6 m lanes
each way plus a 2.4 m median and 1.4 m shoulders, hill road 9 m, trail 6 m,
kerb 0.15 m.

**Surface**

- Asphalt base `#46474A`, worn patches toward `#5A5B5D`, darker repairs
  `#393A3D`. Fine grain that disappears beyond ~30 m. Subtle darker wheel paths
  in each lane. Occasional crack-sealing lines and patch rectangles on city
  streets; the highway is smoother and more uniform.
- Concrete highway decks and bridges in `#B4B0A7`, with expansion joints every
  20–30 m (thin dark lines across; can live in `road.gdshader`).

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

---

## 17. Environmental props

**Today's catalogue:** traffic cone, barrel, crate, bowling pin (stunt park),
lamp post, traffic light, parked car/sedan/van, ramp (`scenes/props/`), plus
builder-made details (benches, billboards, signs, harbour containers...).

**Rules**

- **Real-world size, simplified shape.** Traffic cone 0.7 m (today 0.72);
  traffic barrel ~1.0 m tall and 0.6 m wide, orange with white reflective
  bands; Jersey barrier 0.8 m; bollard 1.0 m; bench seat 0.45 m; bin 1.0 m;
  hydrant 0.8 m; mailbox 1.3 m; lamp post 6–9 m (today 6.5); signal head 1.0 m.
- **Weight reads visually:** light plastic props (cones, barrels) in bright
  hazard colours; heavy props (barriers, bollards) in concrete or steel.
- **Bevel every edge,** smooth-shade, add AO. Budgets: small props ≤ 300 tris,
  street furniture ≤ 1,500, large props (gas station canopy, billboard) ≤ 3,000.
- **Shared materials:** `props.tres` with vertex colour, or a shared props
  atlas. Hazard colours: orange `#E8661C`, red `#C8231B`, white `#E4E2DA`,
  yellow `#E8B51E`, black `#222326`.
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
  and not faceted blobs (today's trees are legacy). Preferred technique:
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

**Tech**

- **One MultiMesh per species per spatial chunk** (~128–256 m). A MultiMesh is
  culled and LOD-ed as a whole, so chunking is what makes culling and LOD
  work. Today each species is one MultiMesh for the whole island (legacy).
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
- **Water:** sea colours from §5. Target: shore colour from a baked shoreline
  mask (not `DEPTH_TEXTURE`), sky reflection through fresnel (roughness
  0.02–0.08), sun glints, a subtle foam band at the shore, gentle normal-mapped
  waves. The sea stays calm: no big waves.

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

**Existing pipeline:** `tools/blender/vehicle_kit.py` (helpers),
`make_car.py`, `make_traffic_vehicles.py`, `make_offroad_vehicles.py`. Run from
the project root:

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
- **Material names follow the contract** (§13). Detachable parts are grouped by
  object-name prefix in `vehicle_kit.DETACHABLE`: `FrontBumper`/`Bumper` →
  `FrontBumper`, `RearBumper` → `RearBumper`, `Wing` → `Spoiler`. Each becomes
  its own mesh in the `.glb`.
- Export GLB with `use_selection` and `export_apply=True` (`vehicle_kit.export`).

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
| Vehicle body, all meshes under `Body` incl. interior | 6k–10k | ≤ 6,000 deformable vertices (§14). Today 1.6–2.6k. |
| Wheel (one mesh, instanced ×4) | 800–2,000 | not deformed. Today ~830. |
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
  city block), so culling still works while draw calls stay low. Today all the
  city's buildings are one mesh and each tree species is one MultiMesh
  (legacy). Chunk them when those families are reworked.
- Dented vehicles lose automatic LOD (`VehicleDamage` swaps in a plain
  `ArrayMesh`). That's acceptable because only a few are dented at once.
- **Street level is where detail counts:** the chase camera is 1–3 m above the
  road. Spend detail on the bottom ~8 m of the world.

---

## 27. Steam Deck performance

**Target:** 60 fps (16.7 ms) at 1280×800 on the Deck, in the busiest views:
city centre at night with busy traffic, a big crash with parts and smoke, the
overview from the mountain.
- **High** is the default (`Settings.DEFAULTS.graphics = 2`) and should hold
  60 fps.
- **Medium** must always hold 60 fps.
- **Low** is the safety net: FSR at 0.75 scale, no glow or SSAO, 2 shadow
  splits, glow-only lamps.

**Hardware:** AMD APU with a 4-core Zen 2 CPU and an RDNA 2 GPU (8 CUs), 16 GB
shared LPDDR5, 1280×800 7" screen (LCD 60 Hz; the OLED model's 90 Hz doesn't
change our 60 fps target), Vulkan (RADV). It runs the Linux x86_64 export
natively. The dev machine (RTX 4090 Laptop) is more than 10× faster on the GPU,
so desktop frame times prove nothing. Counts (draw calls, objects, triangles,
vertices, particles) do transfer.

**Baseline** (2026-10-01, v0.3.1, High, highway spawn, chase camera,
`--bench` with a window):
- 589 draw calls and 1,849 objects without traffic; 733 and 2,113 with 22 cars.
- Vehicle bodies 1.6–2.6k tris with 8–12 surfaces; wheels ~830 tris with 3
  surfaces each.
- Dent cost about 0.15 µs per vertex per pass (desktop CPU).

**Budgets** (busiest view, High)

| Metric | Budget |
|---|---|
| Draw calls | ≤ 1,200. Any single feature adding more than ~100 needs discussion. |
| Visible primitives, incl. shadow passes | ≤ 1.5 M |
| Deck GPU frame time | ≤ 13 ms on High, ≤ 11 ms on Medium |
| Shadow casters | the directional light only (§10) |
| Visible local lights | ≤ 16, none with shadows |
| Live particles | ≤ 1,500 |
| Transparent overdraw | no full-screen transparent layers; foliage uses alpha scissor |
| Texture memory | ≤ 256 MB |
| Deformable vertices per vehicle | ≤ 6,000 |
| Draw surfaces per vehicle | ≤ 10 on the body, ≤ 2–3 per wheel |

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
    markings (`road.gdshader`), car paint (`VehicleBodyVisual` or a shared paint
    material). Today the world palette is scattered (`CityBuilder.PALETTE`,
    colours in `TerrainBuilder` and `NatureBuilder`...). When migrating,
    gather it into one palette script (for example
    `scripts/world/art_palette.gd`) that the builders read.

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

1. **Lighting, atmosphere and palette regrade:** `DayNight.KEYS`, saturation
   1.0, an AgX test, aerial fog, sky colours, then terrain, grass, asphalt and
   building colours. Mostly numbers, huge impact.
2. **Smooth shading and bevels for world geometry:** a smooth-normals option in
   `MeshBuilder`; trees, rocks; soft clouds in the sky.
3. **Roads:** asphalt variation, marking wear, sidewalk paving, Jersey barriers,
   overpass detail, drainage streaks.
4. **Vehicles:** remodel every body with deformation-ready topology, interiors
   and better wheels; clearcoat car paint; glass.
5. **Damage 3.0:** crumple stiffness, the scrape/primer/bare-metal layer,
   structure behind detachable parts, a cracked-glass pattern.
6. **Buildings:** facade grammar (base, middle, top), districts, roof clutter,
   chunking.
7. **Vegetation:** card-based trees, palms, chunked MultiMeshes with LOD.
8. **UI:** font, type scale, icons, gamepad prompts.
9. **Effects:** lit smoke, surface-coloured dust, water splash, landing puffs.

---

## 32. Open owner decisions

- **Font:** Barlow is suggested. It needs a download of OFL font files.
- **Fire and explosions in crashes:** off unless the owner wants them.
- **Traffic colours:** realistic, mostly neutral traffic (this bible) versus
  today's colourful traffic.
- **Player paint list:** today's ten hues kept, with the tuned values in §5.
- **When to start the migration** (§31), and in what order.

---

*Revision log*
- 2026-10-01: created (stylized realism direction, from three reference
  images; baseline measured at v0.3.1).
