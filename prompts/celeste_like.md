# Preliminary Research

This is a required first step. Before writing any code, use your web tools to search the web for Celeste Classic PICO-8 (the original 2015 PICO-8 platformer by Maddy Thorson and Noel Berry) and review how it works:

- the readable 128x128 visual style
- the core movement: running, jumping, and a fast 8-direction dash, and how the dash recharges
- compact single-screen level design and pacing
- the use of spikes, strawberries, platforms, walls, and goals
- the overall feel: precise controls, short challenge, fast retry

Use what you find only as reference. Do not copy the original level or its source code; your level must be original.

## Reference Assets (on disk)

Two reference images are provided on disk, relative to the repo root. Open and inspect them with your tools before drawing anything:

- `assets/sprites.png`: a reference sprite sheet. Recreate these sprites in the cartridge so they are clearly recognizable from the reference — close in shape, color, and palette. Aim for recognizable, not pixel-perfect.
- `assets/screenshot.png`: a capture of the target look (the 128x128 layout, mood, lighting and palette). Use it as your visual target for style and palette.

Use these as concrete visual guides instead of inventing the look from scratch. Reproducing the sprites is encouraged; the level layout itself must still be your own original design (see Level Design below).

Record your design as a short "design notes" comment block of 3 to 6 lines, placed as the first lines of Lua right after `__lua__`. State briefly:

- the Celeste Classic traits you are emulating
- your chosen movement constants
- the single obstacle that will force the dash

Keep it to a few lines. Do not write an essay.

# Task

Create a complete, playable PICO-8 cartridge for a single-screen Celeste-like platformer.

The level must be designed by you. Level design is part of the evaluation.

The game must be inspired by Celeste Classic PICO-8, visually and mechanically, but it must contain your own original level.

If the repo contains previously produced cartridges (e.g. in `results/`), do not read or copy them; work only from this spec and the reference assets.

## How to work

After the research step, work in concrete, bounded iterations using your tools. Do not try to perfect the cartridge in your head before writing it.

1. Draft: write the design-notes header, choose constants, design the level, implement a complete first version, and save it to the file you were asked to create.
2. Run and fix: test the cartridge headless with `pico8 -x <yourfile>.p8 2>&1` (the `pico8` binary is in your PATH) and fix every `syntax error` or `runtime error` it prints. It reports only launch errors, not gameplay.
3. Play-test (recommended): exercise the gameplay logic headlessly with the scripted-input harness described in "Gameplay Self-Test" below, on a throwaway copy of your cart.
4. Improve: make focused improvements (movement feel, level readability, visuals), saving and re-running each time to confirm it still boots.
5. Stop when the Final Check below passes, and leave the final file in place.

The "don't over-deliberate" guidance applies to implementation and checking, not to the research step. Do not repeatedly re-derive the physics, and do not simulate the whole level in your head. Rely on the design rules and on actually running the cart.

# Output and File

Your deliverable is the file you were asked to create. The harness reads that file, not your chat messages, so iterate freely with your tools: only the final saved file is graded.

The file must contain the raw cartridge text and nothing else:

- line 1 exactly: pico-8 cartridge // http://www.pico-8.com
- line 2 exactly: version 8
- line 3 exactly: __lua__
- then your Lua code, starting with the design-notes comment, plus any __gfx__ or __map__ sections you use

No Markdown, no code fences, no prose inside the file. The cartridge must be self-contained: no includes, no external files.

Two more file rules:

- all testing happens on temp copies (e.g. in /tmp): the graded file must never contain harness or debug code
- if you include a `__gfx__` section, each line is exactly 128 hex chars; a partial section (only the first 8 or 16 lines) is fine

# Controls

Document the controls in a short code comment near the top of the cartridge.

Required controls:

- btn(0): move left
- btn(1): move right
- btn(2): aim dash up
- btn(3): aim dash down
- btnp(4): jump
- btnp(5): dash

# Movement Feel

Choose your own movement constants. The game should feel close to Celeste Classic PICO-8:

- responsive horizontal movement
- readable jump arc
- constant gravity
- limited fall speed
- short, fast, satisfying dash
- gravity suspended during dash
- diagonal dash normalized so it is not faster than a straight dash
- reliable solid collision

The game loop runs at 30fps (`_update`), the same rate as Celeste Classic, so movement constants found during your research can be reused at face value.

Do not over-engineer the physics. Prioritize a playable, responsive platformer.

# Dash Requirements

The dash works on the ground and in the air whenever can_dash is true.

When btnp(5) is pressed and can_dash is true:

- read the direction from btn(0), btn(1), btn(2), btn(3)
- if no direction is held, dash horizontally toward the facing direction
- support all 8 directions
- normalize diagonal dashes so a diagonal is not faster than a straight dash
- set the player velocity from the dash direction
- start a short dash timer
- start a very short freeze (hitstop)
- set can_dash to false

During the freeze: no movement, no gravity.

During the dash:

- the player must actually move (apply the dash velocity to x and y)
- do not apply gravity
- do not apply normal run acceleration
- emit a small white trail

Dash recharge:

- can_dash becomes true only when the player touches the ground
- do not recharge against a wall
- do not recharge in the air

On respawn: reset the player to the start and reset can_dash to true.

# Level Design

Create your own original 16x16 tile single-screen level. The whole level fits inside 128x128 pixels with no scrolling.

The level must include:

- a clear player start in the left half of the screen
- solid terrain
- at least 2 spikes, avoidable with correct play
- at least 2 strawberries, optional but reachable, not next to the start
- a clearly visible goal flag in the right half or upper-right area, not close to the start
- a completable main path from start to goal
- at least one obstacle that requires a dash, with a safe landing zone after it

The runner cannot test whether the level is beatable, so make solvability true by construction, not by trial:

- Force the dash with an obstacle your jump cannot clear but your dash can: a gap wider than your running-jump distance, or a wall taller than your jump can climb but within your dash's reach, with no foothold.
- Make the forcing numeric, not approximate: from your constants, compute the max run-jump distance (horizontal speed x total airtime) and the jump+dash reach. The forced gap must exceed the first by at least 8px and undercut the second by at least 8px, so it is impossible without the dash and comfortable with it.
- A quick visual scan of your grid is enough to confirm the intended route needs the dash and has no obvious non-dash shortcut. Do not enumerate every possible path.

Avoid: flat empty levels, impossible jumps, impossible dash gaps, unavoidable spikes, a goal next to the start.

Fairness hint: in the original, up-spikes only kill while the player moves downward (vy >= 0), and the player hitbox is smaller than 8x8 (about 6x6). Without these details, spike patches wider than one tile become unfairly lethal.

# Visual Requirements

Use a clear Celeste-like PICO-8 visual style.

Match the provided reference images: the drawn sprites should be recognizably based on `assets/sprites.png`, and the overall scene should resemble `assets/screenshot.png`. Aim for recognizable, not pixel-perfect.

Beyond matching the references, the cartridge must also include these functional visuals (which a static screenshot does not show):

- a visible dash-available indicator, such as a hair color change
- a white dash trail
- a few ambient particles such as snow or dust

# Gameplay

The game must include:

- left/right movement
- jump
- 8-direction dash
- spike death and respawn
- strawberry collection and score
- goal detection
- a CLEAR! message when the goal is reached
- a frozen game state after victory
- infinite retries

# Gameplay Self-Test (recommended)

`pico8 -x` cannot press buttons: it only proves the cart boots. A scripted-input harness lets you also exercise the gameplay logic itself, headlessly. This step is recommended, not required; it is the most reliable way to catch dead mechanics (a dash that does not move, spikes that do not kill, a goal that never triggers).

Work on a throwaway copy of your cart (e.g. `/tmp/test_play.p8`); never leave harness code in the deliverable.

How it works: PICO-8 runs Lua, so defining global `btn`/`btnp` functions in the cart shadows the built-ins; your game code then reads inputs your script controls. Paste near the top of the TEMP COPY:

    _tb={} _tp={}
    function btn(i) return _tb[i]==true end
    function btnp(i) return _tp[i]==true end
    function script()
     _tp={}                                   -- btnp lasts one frame
     if fr==5   then p.x=65 p.y=88 end        -- teleport to isolate a scenario
     if fr==10  then _tb={[1]=true} end       -- hold right from now on
     if fr==12  then _tp={[4]=true} end       -- press jump
     if fr==21  then _tp={[5]=true} end       -- press dash near the jump apex
     if fr==200 then
      printh("x="..p.x.." y="..p.y.." win="..(win and 1 or 0))
      extcmd("shutdown")
     end
    end

Adapt the variable names to your cart (player table, frame counter, flags), call `script()` at the top of your update function, and use your frame counter (`fr` above) to time the presses. `printh` writes to the console under `-x`; `extcmd("shutdown")` ends the run before the timeout, so a short timeout is fine. Read the printh lines in the captured output, not the exit code:

    timeout 20 pico8 -x /tmp/test_play.p8 2>&1

Compare the printed numbers to the values you expect from your level grid; do not eyeball. Worthwhile scenarios:

- walk into a spike: death, then respawn at the start with the dash restored
- jump+dash across the forced obstacle: lands on the far side (assert x and y)
- the same attempt without dashing: must fail
- touch a strawberry: the score increments
- reach the goal: the win flag is set and the position stays frozen afterwards

Optional visual check: in another temp copy, call `extcmd("screen")` at some frame and `extcmd("shutdown")` a few frames later, run `pico8 -home /tmp/p8home -desktop /tmp -x /tmp/test_shot.p8`, then open the saved png and compare it with `assets/screenshot.png`. If your visuals depend on rnd, call `srand(1)` in `_init` to make shots reproducible.

# Build Loop and Final Check

Converge with the `pico8` binary, not your imagination. The `pico8` executable is available in your PATH. Test the cartridge headless with the `-x` flag, capturing output, under a short timeout (a cart that boots cleanly runs forever, so it will hit the timeout):

    timeout 10 pico8 -x <yourfile>.p8 2>&1

Then read the captured output. Do not rely on the exit code; read the text:

- if it contains a line with `syntax error` or `runtime error`, fix the reported line and tab, then run again
- if it prints only `RUNNING: <yourfile>.p8` with no error line (and reaches the timeout), the cart boots cleanly

`pico8 -x` reports only boot, syntax, and runtime errors, not gameplay, so use it to guarantee a clean launch and rely on the design and visual rules above (and optionally the Gameplay Self-Test) for everything it cannot see.

Stop as soon as all of these hold. Verify them by running and by reading your file; once they hold, stop and do not keep iterating:

- `pico8 -x` prints no `syntax error` or `runtime error` for the cartridge (only `RUNNING:`)
- the file begins with the three exact header lines, then the design-notes comment
- _init(), _update(), and _draw() are defined
- the code implements: an 8-direction dash that moves the player and recharges only on the ground; jump; spike death and respawn; strawberry collection and score; goal detection that shows CLEAR! and freezes the game
- the level contains the required elements: a start, at least 2 spikes, at least 2 strawberries, a goal flag, and the dash-required obstacle
- the sprites are recognizable from `assets/sprites.png` and the overall scene resembles `assets/screenshot.png`, including the dash-available indicator, the white dash trail, and ambient particles
- the file holds only raw cartridge text

Do not describe the test or output logs. Once the cart launches cleanly and the items above hold, stop and leave the file as the final answer.
