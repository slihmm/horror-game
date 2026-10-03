# Wellmouth (working title: *Descent*)

A first-person underground survival-horror experience for Roblox.

> *I should not be down here.*

You arrive at an expedition camp at dusk. Four groups went into the Wellmouth
before yours. A rope still hangs in the great shaft. Below it the cave goes on
for much longer than it should, and something tall walks the deep passages
carrying the lamps of everyone who didn't come back.

The game is built around atmosphere, sound, darkness, uncertainty and
discovery, not jumpscares. Most rooms are quiet. Some are beautiful. A few
are wrong.

---

## Getting started

The project is managed with [Rojo](https://rojo.space). Tool versions are
pinned in `rokit.toml`.

```bash
rokit install                 # or install rojo / luau-lsp / lune yourself
rojo serve                    # live-sync into Studio (open an empty Baseplate)
rojo build -o Descent.rbxlx   # or build a place file directly
```

**Important Studio settings** (most are already in `default.project.json`):

- `Lighting.Technology = Future` (shadows from the headlamp depend on it)
- `Workspace.StreamingEnabled = true`
- To test persistence in Studio, enable *Game Settings → Security → Enable
  Studio Access to API Services*. Without it, profiles are kept in memory and
  the game tells you progress isn't being saved.

Press **Play**. The server generates the cave first (a few seconds; the
screen reads *the cave is settling*), then spawns players at the camp.

| Input | Action |
| --- | --- |
| WASD / stick | move (forward/back also drives ropes, climbs and squeezes) |
| Shift / L3 | run (limited stamina) |
| C / Ctrl / B | crouch (quieter, required to hide) |
| F / Y | headlamp on/off |
| E / X | interact (hold) |
| A ↔ D | work yourself free when wedged in a squeeze |
| Tab / Select | field journal: lore, satchel, record, settings |

### Verification

```bash
scripts/check.sh   # Rojo build + strict type-check against the Roblox API
scripts/test.sh    # offline tests (Lune): cave planner + monster AI simulation
```

`check.sh` type-checks every script in `--!strict` mode against the current
Roblox API definitions using `luau-lsp`. `test.sh` loads modules from the
built place file in [Lune](https://lune-org.github.io/docs) and exercises
the pure logic:

- **planner**: five seeds. Every story location must be reachable, progress
  must increase along the story, the monster must be able to walk from its
  lair to the final chamber, and the corridor must stay voxel-aligned.
- **dressing**: five seeds built into an emulated terrain (`tests/WorldSim`
  records every terrain write and answers raycasts), then dressed by the real
  surface builder, populator and room dressers. All 31 lore entries must
  land (story beats in their rooms, your journal in the newest camp), lore
  and loot must rest on floors, and navigation nodes must be in open air.
- **monster**: simulated encounters. A noisy, lit player is tracked, chased
  and attacked. A silent, dark, hidden player is not. A shy early monster
  never chases.

Anything that needs the engine (terrain, lighting, physics, audio, UI) has
to be checked in Studio. See *Known gaps*.

---

## Architecture

```
src/
  shared/                     -> ReplicatedStorage.Shared
    Config/                   every tunable value lives here (see below)
    Utility/                  Signal, Trove, MathUtil, Spline, Noise, Weighted, RateLimiter
    Constants.luau            tags, attribute names, folders, collision groups
    Net.luau                  the complete list of remotes (one place to audit)
    HeadlampMath.luau         battery/tint formulas shared by client & server
    Types.luau
  server/                     -> ServerScriptService.Server
    Main.server.luau          ordered Init/Start bootstrap
    Cave/                     generation pipeline (pure planner -> terrain -> dressing)
    Monster/                  MonsterBrain (perception + state machine), MonsterBody (kinematic)
    Services/                 one service per system
  client/                     -> StarterPlayerScripts.Client
    Main.client.luau          ordered Init/Start bootstrap
    Controllers/              one controller per system
  overrides/                  replaces Roblox's default character sounds & health regen
tests/                        Lune harness + specs
```

Services and controllers are singletons using a typed metatable pattern
(`typeof(setmetatable({} :: State, X))`), so the whole codebase checks in
strict mode. Each has optional `Init` (wiring) and `Start` (running) phases,
called in dependency order by the bootstraps.

### Server services

| Service | Responsibility |
| --- | --- |
| `CaveService` | Generates the cave, tracks every player's zone / depth / progress / anchor / hidden room at 4 Hz, opens the ring seal |
| `DataService` | Session-locked profiles: retries with backoff, request budgets, coalesced saves, autosave, BindToClose, validation and migration, in-memory fallback |
| `PlayerService` | Spawning, no name tags, stance, movement noise, fall damage, injury, drowning, health regen, speed sanity checks, proximity text chat |
| `HeadlampService` | Server-side battery and toggle, replicated beam direction, tint ownership |
| `TraversalService` | Rope / climb / squeeze state, stuck & help, exit validation |
| `ExpeditionService` | The run: start, escape, walking out, death, satchel banking, all statistics |
| `StatisticsService` | Profile snapshots to the owning client, validated settings |
| `LeaderboardService` | OrderedDataStore boards with batching and retries, published as JSON |
| `LoreService` | Places the story (tagged → anchored → hidden → pooled) and records reads |
| `LootService` | Rarity rolls biased by danger, the satchel, quiet restocking |
| `HazardService` | Ceilings that shed rock (with a warning crack), bridges that give way |
| `DisorientationService` | The ring loop: per-player landmark mutations, opening the way on |
| `MonsterService` | The Lamplighter: perception input, brain, body, attacks, activation |
| `HorrorDirector` | Tension curve and pacing, event selection, explorer path recording |
| `NoiseService` | The stream of audible events the monster listens to |

### Client controllers

`AudioController` (all sound: library lookup, groups, zone beds, ambient
scheduler, depth muffling, silence) · `UIController` (fades, whispers, lore
reader, vignette, battery glyph) · `CameraController` (first-person feel) ·
`MovementController` · `HeadlampController` · `LightingController` ·
`FootstepController` · `InteractionController` · `TraversalController` ·
`CinematicController` · `RecursionController` · `HorrorController` ·
`MonsterPresenceController` · `MenuController`.

### Client/server split

The server is authoritative for everything that matters: position-derived
statistics, run outcomes, loot, lore records, battery, damage, monster
behaviour, traversal exits, settings validation. Clients only send:
`LookPitch` (unreliable, clamped, rate-limited), `SetStance`,
`ToggleHeadlamp`, `Traversal`, `UpdateSetting` and `CinematicFinished`.
Everything is validated and rate-limited. Interactions use ProximityPrompts,
which the engine range-checks on the server.

Presentation that should differ per player runs on that client only:
shadow figures, landmark mutations, the recursion loop, mimic voices. Two
teammates can genuinely disagree about what they saw.

---

## The cave

Generation is a hybrid. **`CaveLayout`** places the story by hand. A pure,
seeded **planner** (`CavePlanner` → `CavePrimitives`, `RoomPlans`,
`CaveBranches`) then:

1. carves the handcrafted rooms and connects them with wandering tunnels,
   ropes, climbs, a squeeze and the recursion corridor;
2. grows **hidden rooms** first (squeeze-access or a crack behind a boulder);
3. grows branches in two passes: side chambers, dead ends, loops, pits,
   pools, plank bridges, collapses and hiding alcoves. Each branch is tested
   for clearance before it's committed, so procedural rooms never punch into
   story spaces;
4. builds a navigation **graph** that drives monster pathing, zone tracking
   and the "furthest reached" statistic.

`TerrainBuilder` executes the plan in a fixed order: rock shells, then air
carves, floors, details, late carves, and finally water (which only replaces
air). The `Populator` and `RoomDressers` then dress the result with raycasts.
Every prop is built from parts by `PropFactory`. **To replace any prop with
real art, put a Model with the same name in `ServerStorage.Assets.Props`.**

Each run gets a new seed (set `CaveConfig.Seed` to pin one). Story beats stay
in the same rooms; the branches, hidden rooms, loot, pooled lore, patrols and
horror events change.

### The route

Camp → cave mouth → **Upper Cave** (daylight through cracks) → the **Shaft**
(rope descent) → **Wet Cave** and the cistern → **the loop** (the way on
opens only after you pass the skeleton twice, and the skeleton isn't how you
left it) → **Deep Cave** (you hear it first) → **the corridor** (identical
voxel-aligned modules; the client loops you back a few times, then lets you
go) → the **Abandoned Camp** (three camps laid out identically) → a squeeze,
or the lair → **the Old Works** → **the Gathering** → two chimney climbs →
morning.

---

## Systems at a glance

- **Headlamp:** a narrow shadow-casting core, a weak wide spill and a faint
  body glow. It trails the view slightly, flickers, and dims as the battery
  dies. The battery is server-side and found as loot. Teammates see your beam
  sweep the dark.
- **Sound:** zone beds crossfade; one-shots are weighted, cooled down,
  randomised and placed in 3D (often behind you). Everything is muffled with
  depth. Footsteps react to material, stance, sprinting, water and injury.
- **Horror Director:** Calm → Unease → Build → Peak → Relief. Most ticks do
  nothing, a quarter of Build phases are dry, and a minimum gap separates
  events. It considers zone, run time, tension, being alone, teammates,
  monster state and cooldowns. Events: distant/behind footsteps, shadow
  sightings, figures behind you, echo walkers retracing recorded explorer
  paths (sometimes yours), glints in the beam, rockfalls, flicker, darkness,
  screams, objects moving, water, distant BOOMs, silence, knocking, whispers,
  mimicked teammates, and the crowd in the Gathering.
- **Shadow figures** exist until you've seen them and look away, or until you
  approach.
- **The Lamplighter** has these states: Dormant, Patrolling, Listening,
  Investigating, Searching (it checks hiding spots), Tracking, Chasing,
  LostTarget, Returning and Ambushing (silent). It hears noise with distance-
  and rock-dependent error. It sees within a field of view and line of sight;
  a lamp pointed at it gives you away from far off, darkness and crouching
  hide you. It stays shy until the camp, then hunts. Its footsteps are the
  main signal: sparse, echoing BOOMs far away, building to BOOMBOOMBOOM with
  shaking and falling grit up close.
- **Hiding:** crouch inside a crevice or behind slabs. It may walk past, stop,
  listen, look in, or leave and come back. Moving while it looks is what gets
  you found.
- **Squeezes** can wedge you. Shift left/right to work free while the noise
  carries, or a teammate can pull you out.
- **Progress:** satchel loot is banked only if you get out. Statistics are
  Highest Distance, Deepest Descent, Escapes, Time Underground, Secrets Found
  and Fastest Escape (plus deaths and expeditions), each with a leaderboard
  in the journal and on the camp logbook board.

---

## Tuning

Everything tunable is in `src/shared/Config`:

| File | What it controls |
| --- | --- |
| `PlayerConfig` | speeds, stamina, fall damage, drowning, noise levels, speed-check tolerance |
| `CameraConfig` | bob, breathing, sway, landing, shake, FOV, squeeze/rope camera |
| `HeadlampConfig` | brightness, cone angles, range, battery life, flicker, lens tints |
| `LightingConfig` | per-zone lighting presets, the dawn preset |
| `AudioConfig` | per-zone ambience pools (weights, cooldowns, distance, behind-bias), footsteps |
| `SoundLibrary` | asset ids for every sound (see below) |
| `CaveConfig` | generation: shells, tunnels, branch counts and weights, room contents, corridor, ring |
| `CaveLayout` | the handcrafted story spine |
| `MonsterConfig` | speeds, hearing, sight, awareness, chase, search, ambush, activation, presence |
| `HorrorConfig` | director events, cooldowns, pacing phases, dry-phase chance |
| `LootConfig` | items, rarities, zone and hidden-room bias |
| `LoreData` | every piece of the story and where it goes |
| `StatsConfig` / `TraversalConfig` / `ZoneConfig` | statistics, traversals, zone identities |

---

## Audio assets

`SoundLibrary.luau` maps logical names to asset ids. Until real cave audio is
uploaded, entries fall back to sounds that ship with the Roblox client
(`rbxasset://sounds/...`), heavily re-pitched to approximate the intent. For
example, the monster's footstep is `hit.wav` at 0.2× speed. The game is
playable with these, but it will sound far better with real assets.
**Priority uploads:** `MonsterStep`, the six `Bed_*` loops (silent until
assigned), `Step_*`, `Drip`, `DistantFootsteps`, `MonsterBreath`/`Roar`,
`Heartbeat`, `Whisper` and the `Mimic_*` voice lines (the mimic event is
skipped until they exist).

---

## Known gaps / next steps

This was built and verified **without running Roblox Studio** (static type
checking plus offline simulation of the pure logic). Before shipping, do a
Studio pass on:

- **Generation timing and feel:** terrain build time on a live server,
  tunnel widths for the character, the slopes of the climb out, light leaks
  through thin terrain, prop placement on uneven floors.
- **Traversal physics:** characters held by `AlignPosition`/`AlignOrientation`
  with `PlatformStand`; tune if R15 rigs jitter.
- **Lighting balance:** presets are intentionally very dark; tune per display.
- **Monster movement:** kinematic movement on floor-snapped graph nodes; check
  for floor clipping on steep tunnels and chase difficulty (`MonsterConfig`).
- **Art:** every prop and the creature are built from parts. Drop meshes into
  `ServerStorage.Assets` to replace them.
- **Postures:** crouch/rope/climb/squeeze poses are procedural joint offsets
  (`PostureConfig`); verify the angles on R15 rigs. R6 avatars are left unposed.
- **Not yet built:** spatial voice chat effects (Roblox proximity voice works
  as is; reverb via the Audio API would be a nice addition).

## Cloud sessions

`.claude/hooks/session-start.sh` installs rojo, luau-lsp (plus the Roblox
type definitions) and lune, so `scripts/check.sh` and `scripts/test.sh` work
in Claude Code cloud sessions.
