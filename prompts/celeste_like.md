# Goal and Priorities

Create a complete, playable PICO-8 cartridge for an original single-screen
Celeste-like platformer. The result is judged in this order:

1. Complete self-contained cartridge and clean boot.
2. Responsive mechanics, reliable collision, and a solvable level.
3. Deliberate visual composition closely following the supplied references.
4. Deterministic demo driven only through normal logical inputs, ending in a saved GIF.
5. Optional extras only after the first four priorities work.

Aim for a cartridge that looks and plays like the references. A technically valid cart made
from placeholder rectangles on a flat background scores badly.

# How To Work

Work in short cycles: decide one thing, edit the cartridge, run a check, read the result.

These are cheap and unlimited. Reach for them instead of working things out on paper:

- `python3 bench/route_check.py --from-cart <file>.p8 --solve` — geometry oracle
- `timeout 10 pico8 -x <file>.p8 2>&1` — boot check
- the `pico8` MCP tools — boot, play, read state, screenshot

Every question about reach, spacing, headroom, or solvability has a tool that answers it. Ask
the tool and read its answer. Run the same check again after any change that could affect it.

## The file exists first

Your first write creates the deliverable. Before looking at an image, searching the web, or
planning a route, put this on disk in one write:

- the exact 3-line header
- the design-notes comment, with your first draft of the 16x16 level grid inside it
- a minimal Lua that boots: `_init`, `_update`, `_draw`, the movement constants, a player that
  falls and lands, and the grid drawn as solid tiles

That draft is allowed to be rough and the grid is allowed to be wrong; both get fixed by the
tools. What matters is that from this point on there is a cartridge to run, measure, and
improve, and that everything you learn lands in it instead of staying in your head.

Then three invariants hold for the rest of the task:

- the cartridge on disk boots
- the cartridge on disk holds your current best design, including the current grid
- nothing you work out stays outside the file

Expected rhythm, with the tools doing the arithmetic:

    read this prompt
    write the .p8: header, notes with a draft 16x16 grid, bootable skeleton   <- first write
    pico8 -x -> it boots
    route_check --from-cart -> adjust the grid in the file -> re-run -> contract passes
    view both reference images, skim one web reference, note the palette in the file
    fill in the foundation: collision, dash, drawing, terrain from the grid
    MCP boot -> walk, jump, dash -> read state
    add spikes, strawberries, goal -> MCP: die and respawn, collect, win
    draw sprites and compose the scene -> MCP screenshot at native size, compare to assets
    route_check --solve -> take the reported move list
    write the demo controller from that move list, one phase at a time
    MCP run from launch -> watch it reach CLEAR!
    final boot check, one unattended demo run, stop

# Reference Pass

Once the skeleton is on disk, view `assets/sprites.png` and `assets/screenshot.png` with the
read tool, and skim one or two web pages about Celeste Classic PICO-8 for style and feel. Two
helper commands are plenty if you want exact pixel values; the goal is a palette and a set of
silhouettes you can draw, and that answer arrives by looking. Record what you take from them
as a line or two in the cartridge's notes, then move on: the contracts below are
authoritative.

The screenshot is a 10x nearest-neighbour enlargement of a 128x128 frame. Match its palette,
contrast, snowy cavern treatment, sprite scale, and mood while inventing your own geometry.
Take style from the references and code from yourself. Leave the cartridges in `results/`
alone; they are other entries in this benchmark.

# Geometry Oracle

`bench/route_check.py` answers layout questions using the same movement constants listed
below. It is authoritative for spacing and reach; the running cartridge is authoritative for
gameplay.

Describe the level as a 16x16 grid, one row per line:

    .  empty        #  solid rock or ice      ^  upward spike
    s  spawn        b  strawberry             g  goal flag

Keep that grid inside the cartridge, as a comment block or as a Lua table of 16 strings; the
same grid can build your terrain at `_init`. Keep it even if you draw terrain from `__map__`,
because tile numbers alone do not say which tiles are solid. Then:

    python3 bench/route_check.py --grid level.txt                 # contract checks, instant
    python3 bench/route_check.py --from-cart mycart.p8 --solve    # adds routes, a few seconds

It reports landing surfaces and height bands, the forced gap, clear height above every
surface, spike groups, strawberries, spawn footing, goal placement, whether the gap genuinely
requires a dash, and a move list from spawn to the goal. It also echoes how it read each grid
character, so a mismatch with your own legend is visible at a glance. Pass `--spawn COL,ROW`
when the spawn lives in Lua rather than in the grid.

That move list is the answer to "how does the demo get through": each entry is one
grounded-initiated move such as `run right to the edge and jump + dash up-right`. Build the
demo phases directly from it.

Use these spacings as starting points and let the oracle confirm the exact case:

- flat jump: 2-tile gap
- rising jump: 1 tile up and 1 tile across together
- falling jump: 3-tile gap
- forced gap: 4 empty columns, crossed with run + jump + horizontal dash
- 2 tiles of clear height above every surface a jump starts from

# Output Contract

The invocation supplies a deliverable path, display name, and exact GIF filename. Use them
literally. Normal PICO-8 uppercase glyph rendering of the display name is fine; keep the name
itself intact. The harness reads the file, not chat output.

The file contains raw cartridge text and begins exactly:

    pico-8 cartridge // http://www.pico-8.com
    version 8
    __lua__

Immediately after `__lua__`, add a 4-6-line Lua comment covering the reference-based visual
traits, the supplied movement constants, the four-column dash gap and its safe landing, the
route's introduction/reversal/climax, and the demo's optional strawberry detour. Follow it
with one short controls comment, then Lua, then optional `__gfx__` or `__map__` sections.

The cartridge is self-contained: plain cartridge text, no Markdown, code fences, includes,
harness code, or debug code. When `__gfx__` is present, every row holds exactly 128
hexadecimal characters.

# Controls and Mechanics

Required controls: `btn(0/1)` move left/right, `btn(2/3)` aim the dash up/down, and
`btnp(4/5)` jump/dash. Opposite directions on one axis cancel each other.

Run `_update` at 30fps with these exact constants:

- max run speed 1 px/frame, acceleration 0.6, deceleration 0.15
- gravity 0.21 per frame, max fall speed 2, jump velocity -2
- dash speed 5 px/frame, diagonal factor 0.7071
- 2 hitstop updates followed by 4 moving dash updates; hitstop does not consume dash time

Use consistent gravity outside hitstop and dash, reliable solid collision, and a 6x6 player
hitbox. When `can_dash` is true, allow dashing on the ground or in the air. Read all four
direction buttons, support all 8 normalized directions, and default to a horizontal dash
toward the facing direction when no direction is held. During hitstop, hold everything still;
during a dash, apply only the dash velocity.

Consume the dash immediately and recharge it only on the ground, never on walls or in the air;
restore it on respawn. Show availability through the player sprite, such as hair colour, and
emit a short white trail while dashing.

Gameplay also needs spike death and respawn, infinite retries, two collectible strawberries
with a visible score, a goal flag, `CLEAR!`, and victory. After victory, freeze player physics
and hazards while drawing continues, and run a 45-update recording timer.

# Level Contract

Build an original non-scrolling level on a 16x16-tile grid. Background framing may continue
behind the top 8-pixel title zone; playable surfaces, hazards, and collectibles stay out of
it. The completable main route has three beats:

1. **Introduction:** start in the left half with one safe jump initiated while grounded.
2. **Variation:** add vertical change, a meaningful horizontal reversal, a spike-constrained
   move, a safe landing between challenges, and the optional berry detour.
3. **Climax:** cross exactly 4 empty tile columns with run + jump + horizontal dash, land on
   a safe surface at least 2 tiles wide, then approach an elevated goal in the right half.

Across the route, provide at least 4 distinct landing surfaces in 3 height bands and at least
3 deliberate jumps initiated while grounded. Include 2 separate avoidable spike groups; one
constrains a required takeoff or landing. Include at least 2 reachable but avoidable
strawberries, both away from spawn and in different situations. The detour berry is the one
the demo collects; the other stays avoidable from that route.

The forced gap's takeoff and landing edges sit at the same height with exactly 4 empty tile
columns between them.

Sketch the grid, run the oracle, adjust the grid, and repeat until every contract check
passes. Then build that grid in the cartridge and confirm in play.

Give each ledge a distinct size and purpose. Avoid flat floor routes, uniform stairs, repeated
identical ledges, unavoidable spikes, goals near spawn, and long empty walks. Moving
platforms, crumble blocks, wall jumps, and other extras come after core polish. Upward-facing
spikes are fair: they kill only while the player is falling or grounded over them (`vy >= 0`),
letting the player rise safely through their tips.

# Visual Direction

Treat the references as a production target. Before autoplay, build:

- 2 or 3 large connected rock or ice masses with most playable ledges embedded in them
- substantial dark negative space and three readable layers: distant silhouettes, playable
  foreground terrain, and sparse particles behind gameplay
- a quiet top 8-pixel title placement zone holding the supplied display name with a
  contrasting shadow; cavern framing continues behind it rather than a solid HUD bar
- dark navy/black cavern interior, gray-brown rock, pale snow caps, occasional cyan ice, and
  bright red/pink focal sprites with green stems and white highlights; target roughly 25% cyan
  sky or ice, 25% gray-brown rock, 20% black negative space, 15% pale snow, and 10% deep navy,
  with no single colour covering more than 40% of the frame
- sparse rock texture, irregular silhouette edges, and clear foreground/background contrast

Recreate recognizable 8x8 pixel-art versions of the player, strawberry, spikes, snow edge,
and one rock tile family from `assets/sprites.png`. Within its 8x8 cell the player carries
three distinct colour roles — hair, skin, and body — plus eyes, so it reads as a character
rather than a blob; the reference player is red hair over a pale face over a green torso.
Design an original readable goal flag in the same palette and treatment. Sprites may use `__gfx__` or carefully drawn pixel primitives,
with deliberate silhouettes and highlights rather than plain squares. Keep solids, hazards,
collectibles, player, and goal distinguishable at native scale, and add only a few ambient
snow or dust particles.

Capture a native 128x128 screen, compare it with both assets, and refine until the scene has
framing terrain masses, snowy edges, recognizable sprites, a clear title zone, and distinct
layer contrast. Isolated bars on a flat cyan or navy field mean the composition is not there
yet.

# Opening Demo and GIF

Start a deterministic attract-mode demo on launch. Read physical `btn(0..5)` inputs first: if
any is pressed during the demo, cancel it immediately and respawn into normal human play.
Cancellation permanently disables GIF saving for that run. Otherwise feed synthetic logical
inputs through the same `_update`, movement, collision, hazard, collection, and goal path that
human input uses.

Use a small state-based controller whose phases advance from grounded state, position,
platform identity, score, or goal state. Brief per-phase timers are fine. The oracle's move
list maps onto these phases one for one; build them from it rather than from a long
frame-by-frame input table, and set no player coordinates directly.

The demo starts at normal spawn, finishes within 2,700 updates, traverses the real route, and
makes at least 3 genuine landings. It takes the optional detour, collects exactly 1
strawberry, crosses the four-column gap with jump + horizontal dash, and reaches the real goal
through normal collision. It wins exactly as a player would: no teleporting, no altered
hazards, no moved goal, no victory assigned directly, and no artificial idle padding before
victory.

At startup, pass the exact supplied GIF filename string to `extcmd("set_filename", ...)`,
then call `extcmd("rec_frames")`. While the demo is still active and uncancelled, once normal
goal collision sets victory, keep the frozen `CLEAR!` scene and display name visible for 45
updates, then call `extcmd("video",4,1)` exactly once. A cancelled, timed-out, or failed demo
saves no GIF.

# Build Loop

Boot early and often; a cartridge that boots after every edit never accumulates a mystery
failure. Keep the player and game state (position, vy, grounded, dashing, can_dash, score,
phase, win) in top-level globals so `pico8_read` observes them directly — in PICO-8 this is
idiomatic, not debug code, so the graded file keeps it.

1. Boot-check the skeleton you wrote first, then grow its mechanics and verify them with MCP.
2. Establish and inspect the visual foundation at native resolution.
3. Bring the grid up to an oracle-approved route, one tested beat at a time.
4. Exercise death and respawn, berry collection, the gap without a dash, the gap with a dash,
   and the goal.
5. Add the state-based demo one observed checkpoint at a time.
6. Polish trail, particles, animation, and readability.
7. Run `timeout 10 pico8 -x <yourfile>.p8 2>&1`; success is `RUNNING:` with no syntax or
   runtime error, the timeout firing being expected. Then run one unattended demo
   verification.

With MCP, use `pico8_boot`, `pico8_play` or `pico8_step`, `pico8_read`, `pico8_screen`, and
`pico8_reset`; MCP works on a temp copy, so the graded file stays untouched. When a run fails,
look at the first failure only and note its phase, grounded state, position, deaths, score,
and win state; then fix that one thing and rerun. Repair the demo one predicate or one local
spacing at a time, preferring grounded and position predicates over timing tweaks. When a
spacing looks marginal, ask the oracle rather than adjusting by feel.

If MCP exits immediately after `extcmd("video",4,1)`, confirm from code and state that
victory, score 1, the 45-update delay, and the exact recorder calls are right, then treat it
as a recorder-environment quirk and rely on the benchmark capture. If MCP is unavailable, test
a copy in `/tmp` with scripted logical inputs and `printh`; the graded file stays free of
harness and debug code.

# Final Stop Gate

After the final edit, verify once that:

- the file satisfies the Output Contract, defines `_init`, `_update`, and `_draw`, and holds
  no debug, harness, or demo-shortcut code
- clean boot and the Controls, Mechanics, Level, and Visual contracts pass
- unattended autoplay wins through normal inputs with score 1, displays `CLEAR!` and the
  supplied display name for 45 updates, and saves the exact GIF once
- any physical `btn(0..5)` input cancels autoplay into normal human play

Once these pass after the final edit, stop and report what you built in a few lines.
