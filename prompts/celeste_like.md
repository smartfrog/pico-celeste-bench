# Goal and Priorities

Create a complete, playable PICO-8 cartridge for an original single-screen
Celeste-like platformer. The result is judged in this order:

1. Complete self-contained cartridge and clean boot.
2. Responsive mechanics, reliable collision, and a solvable level.
3. Deliberate visual composition closely following the supplied references.
4. Deterministic demo driven only through normal logical inputs, ending in a saved GIF.
5. Optional extras only after the first four priorities work.

Do not simplify the level or visuals merely to make autoplay easy. A technically valid cart
made from placeholder rectangles on a flat background is not a good result.

# Bounded Reference Pass

Before coding, review one or two web sources about Celeste Classic PICO-8, inspect
`assets/sprites.png` and `assets/screenshot.png`, and make one short route sketch covering
spawn, landing surfaces, reversal, berry detour, forced gap, and goal. Then stop researching:
the constants and spacing rules below are authoritative.

The screenshot is a 10x nearest-neighbor enlargement of a 128x128 frame. Match its palette,
contrast, snowy cavern treatment, sprite scale, and mood, but create original geometry. Use
web references for style and feel only, never source code. Do not inspect previous cartridges
in `results/`.

# Incremental Implementation

Do not solve the entire level, collision system, or demo route mentally before writing code.
Build a working foundation, then extend it through small isolated milestones. Use the todo
tool to split implementation into concrete tasks. No implementation task may combine the
complete mechanics, level, visuals, and demo. Each implementation task must produce a file
edit, and every task must have one observable completion check.

Stricty Use this progression, Step by step, one by one 

1. Create a bootable cartridge foundation with player movement, gravity, collision helpers,
   drawing, 2 plateform to jump between
2. Add and test only the introduction route beat.
3. Add and test only the variation and berry-detour beat.
4. Add and test only the forced-gap climax and goal approach.
5. Add hazards, collectibles, sprites, snow edges, and focused visual refinement.
6. Add the deterministic demo one route beat at a time.
7. Run the final integrated verification.

At the start of each task, mark exactly one task in progress. For an implementation task, make
one concrete decision and edit the cartridge immediately. For a verification task, run its
check immediately. Fix only the first observed failure and mark the task complete once its
local check passes. Do not calculate future trajectories or collision interactions while
implementing an earlier beat; use the supplied spacing rules, implement the current beat, and
validate it in the running cartridge. Once a beat passes, treat it as stable unless a later
integrated test demonstrates a concrete regression.

Incremental construction does not permit placeholder quality. The foundation must establish
the intended palette, connected terrain masses, title zone, recognizable player silhouette,
and deliberate route anchors. Later tasks refine and connect that foundation rather than
replacing temporary rectangles.

# Output Contract

The invocation supplies a deliverable path, display name, and exact GIF filename. Use them
literally. Normal PICO-8 uppercase glyph rendering of the display name is acceptable, but do
not rename, abbreviate, or truncate it. The harness reads the file, not chat output.

The file must contain raw cartridge text and begin exactly:

    pico-8 cartridge // http://www.pico-8.com
    version 8
    __lua__

Immediately after `__lua__`, add a 4-6-line Lua comment covering the reference-based visual
traits, supplied movement constants, four-column dash gap and safe landing, route
introduction/reversal/climax, and the demo's optional strawberry detour. Follow it with one
short controls comment, Lua, and optional `__gfx__` or `__map__` sections.

The cartridge must be self-contained: no Markdown, code fences, includes, harness code, or
debug code. If `__gfx__` is present, every row must contain exactly 128 hexadecimal characters.

# Controls and Mechanics

Required controls: `btn(0/1)` move left/right, `btn(2/3)` aim the dash up/down, and
`btnp(4/5)` jump/dash. Opposite directions on one axis cancel each other.

Run `_update` at 30fps with these exact constants; do not derive alternatives or tune new
reach values:

- max run speed 1 px/frame, acceleration 0.6, deceleration 0.15
- gravity 0.21 per frame, max fall speed 2, jump velocity -2
- dash speed 5 px/frame, diagonal factor 0.7071
- 2 hitstop updates followed by 4 moving dash updates; hitstop does not consume dash time

Use consistent gravity outside hitstop and dash, reliable solid collision, and a 6x6 player
hitbox. When `can_dash` is true, allow dashing on the ground or in the air. Read all four
direction buttons, support all 8 normalized directions, and default to a horizontal dash
toward the facing direction when no direction is held. Apply no movement or gravity during
hitstop; during dash apply only dash velocity.

Consume the dash immediately, recharge only on ground, never on walls or in air, and restore
it on respawn. Show availability through the player sprite, such as hair color, and emit a
short white trail while dashing.

Gameplay also requires spike death and respawn, infinite retries, two collectible
strawberries with visible score, a goal flag, `CLEAR!`, and victory. After victory, freeze
player physics and hazards while continuing drawing and a 45-update recording timer.

# Level Contract

Build an original non-scrolling level on a 16x16-tile grid. Background framing may continue
behind the top 8-pixel title zone, but no playable surface, hazard, or collectible may overlap
the text. The completable main route has three beats:

1. **Introduction:** start in the left half with one safe jump initiated while grounded.
2. **Variation:** add vertical change, a meaningful horizontal reversal, a spike-constrained
   move, a safe landing between challenges, and the optional berry detour.
3. **Climax:** cross exactly 4 empty tile columns with run + jump + horizontal dash, land on
   a safe surface at least 2 tiles wide, then approach an elevated goal in the right half.

Across the route, provide at least 4 distinct landing surfaces in 3 height bands and at least
3 deliberate jumps initiated while grounded. Include 2 separate avoidable spike groups; one
must constrain a required takeoff or landing. Include at least 2 reachable but avoidable
strawberries, both away from spawn and in different situations. The detour berry is the one
collected by the demo; the other must remain avoidable from that route.

The forced gap's takeoff and landing edges must be at the same height with exactly 4 empty
tile columns between them. Use these known-good edge-to-edge spacings instead of calculating
trajectories:

- flat jump: at most a 2-tile gap
- rising jump: at most 1 tile up and 1 tile across simultaneously
- falling jump: at most a 3-tile horizontal gap
- forced gap: 4 empty columns, crossed with run + jump + horizontal dash
- at least 2 tiles of clear headroom along every required jump and dash path

Construct from these rules, then run the cart. Verify once that the forced gap fails without
dash and succeeds with dash. If a move fails, make the smallest local spacing correction; do
not restart the layout, enumerate frame positions, add mechanics, or redesign for autoplay.

Avoid flat floor routes, uniform stairs, repeated identical ledges, unavoidable spikes, goals
near spawn, and long empty walks. Moving platforms, crumble blocks, wall jumps, and other
extras must not displace core polish. For fair upward-facing spikes, kill only while the
player is falling or grounded over them (`vy >= 0`), not while rising through their tips.

# Visual Direction

Treat the references as a production target, not vague inspiration. Before autoplay, build:

- 2 or 3 large connected rock or ice masses with most playable ledges embedded in them
- substantial dark negative space and three readable layers: distant silhouettes, playable
  foreground terrain, and sparse particles behind gameplay
- a quiet top 8-pixel title placement zone with the supplied display name and a contrasting
  shadow; this is not a solid HUD rectangle, and cavern framing continues behind it
- dark navy/black cavern interior, gray-brown rock, pale snow caps, occasional cyan ice, and
  bright red/pink focal sprites with green stems and white highlights
- sparse rock texture, irregular silhouette edges, and clear foreground/background contrast

Recreate recognizable 8x8 pixel-art versions of the player, strawberry, spikes, snow edge,
and one rock tile family from `assets/sprites.png`. Create an original readable goal flag in
the same palette and pixel-art treatment. Sprites may use `__gfx__` or carefully drawn pixel
primitives, but must have deliberate silhouettes and highlights, not placeholder squares.
Keep solids, hazards, collectibles, player, and goal distinguishable at native scale. Add
only a few ambient snow or dust particles.

Before autoplay, capture a native 128x128 screen and compare it with both assets. Make at
most two focused composition or sprite passes, stopping once the scene has framing terrain
masses, snowy edges, recognizable sprites, a clear title zone, and distinct layer contrast.
Do not accept isolated bars on a flat cyan or navy field.

# Opening Demo and GIF

Start a deterministic attract-mode demo on launch. Read physical `btn(0..5)` inputs first;
if any are pressed during the demo, cancel it immediately and respawn into normal human play.
Cancellation permanently disables GIF saving for that run. Otherwise feed synthetic logical
inputs through the same `_update`, movement, collision, hazard, collection, and goal path used
by human input.

Use a small state-based controller whose phases advance from grounded state, position,
platform identity, score, or goal state. Brief per-phase timers are fine. Do not build a long
frame-by-frame input table or assign player coordinates directly.

The demo must start at normal spawn, finish within 2,700 updates, traverse the real route,
and make at least 3 genuine landings. It must take the optional detour, collect exactly 1
strawberry, cross the four-column gap with jump + horizontal dash, and reach the real goal
through normal collision. Never teleport, alter hazards, move the goal, assign victory
directly, or add artificial idle segments before victory.

At startup, pass the exact supplied GIF filename string to `extcmd("set_filename", ...)`,
then call `extcmd("rec_frames")`. Only while the demo remains active and uncancelled, once
normal goal collision sets victory, keep the frozen `CLEAR!` scene and display name visible
for 45 updates, then call `extcmd("video",4,1)` exactly once. Never save a GIF if the demo is
cancelled, times out, or fails before victory.

# Bounded Build Loop

Boot-check after a milestone or final edit, not after every small change. Do not repeat a
passed check unless relevant code changed.

1. Create the mechanical test room and verify its systems with MCP.
2. Establish and inspect the visual foundation at native resolution.
3. Replace the test room with the final route one tested beat at a time.
4. Test death/respawn, berry collection, no-dash failure, dash success, and goal once each.
5. Add and test the state-based demo one observed checkpoint at a time.
6. Make at most one final pass for trail, particles, animation, or readability.
7. Run `timeout 10 pico8 -x <yourfile>.p8 2>&1`; success is `RUNNING:` with no syntax or
   runtime error regardless of the expected timeout status, then run one unattended demo
   verification and stop.

The mechanics and unattended demo checks are required; using MCP is recommended. With MCP,
use `pico8_boot`, `pico8_play` or `pico8_step`, `pico8_read`, `pico8_screen`, and
`pico8_reset`. Keep the player and game state (position, vy, grounded, dashing, can_dash,
score, phase, win) in top-level globals so `pico8_read` observes them directly; in PICO-8 this
is idiomatic, not debug or harness code. Never create an instrumented copy just to expose
state. On a failed run, inspect only the first failure and record its phase, grounded
state, position, deaths, score, and win state. Do not enumerate per-frame positions or pixel
overlap arithmetic.

Allow at most three focused demo-repair cycles. Change one state predicate or one local
spacing per cycle, retest from launch, and replace timing-sensitive logic with grounded or
position predicates instead of adding frame tuning.

If MCP exits immediately after `extcmd("video",4,1)`, first verify from code and state that
victory, score 1, the 45-update delay, and exact recorder calls are correct. Then treat it as
a recorder-environment failure and rely on the benchmark capture; do not investigate PICO-8
internals. If MCP is unavailable, test on a copy in `/tmp` with scripted logical inputs and
`printh`. Never leave harness or debug code in the graded file.

# Final Stop Gate

After the final edit, verify once that:

- the file satisfies the Output Contract, defines `_init`, `_update`, and `_draw`, and has no
  debug, harness, or direct-demo-cheat code
- clean boot and the Controls, Mechanics, Level, and Visual contracts pass
- unattended autoplay wins through normal inputs with score 1, displays `CLEAR!` and the
  supplied display name for 45 updates, and saves the exact GIF once
- any physical `btn(0..5)` input cancels autoplay into normal human play

Once all checks above pass after the final edit, stop immediately. Do not rerun seeds, repeat
passed tests, redesign the level, or produce a testing essay.
