# AGENTS.md

## What this repo is

A **benchmark**, not an app. It evaluates an agent's ability to produce a complete,
playable PICO-8 cartridge for a single-screen Celeste-like platformer. There is no
build system, package manager, or test suite — the "code" produced is a `.p8`
cartridge text file.

## Layout

- `prompts/celeste_like.md` — the full task spec given to the agent under test. This is
  the source of truth for requirements (header format, controls, dash mechanics, level
  rules, final checks). Read it before doing the task.
- `assets/sprites.png`, `assets/screenshot.png` — reference visuals the cartridge must
  resemble. Open and inspect them before drawing sprites.
- `results/*.p8` — example/produced cartridges (e.g. `qwen37.p8`), kept as reference.
- `carts/` — gitignored output directory for generated cartridges.

## The task workflow (when asked to build the cartridge)

1. Web-search the original Celeste Classic PICO-8 for reference (required first step).
2. Inspect `assets/sprites.png` and `assets/screenshot.png`.
3. Write the `.p8` file with the exact 3-line header, then a 3–6 line design-notes
   comment, then Lua + `__gfx__`/`__map__`.
4. Verify boot with: `timeout 10 pico8 -x <file>.p8 2>&1`
   - `pico8` is on PATH (`~/.local/bin/pico8`).
   - It runs forever on success, so the timeout firing is expected.
   - **Read the text output, not the exit code.** Only `RUNNING:` with no
     `syntax error` / `runtime error` line means a clean boot.
   - `-x` checks boot/syntax/runtime only — it does NOT validate gameplay or level
     solvability. Those must be correct by construction.
5. (Recommended) Play-test gameplay on a temp copy with scripted inputs — see
   "Gameplay Self-Test" in the prompt: override `btn`/`btnp` in Lua, drive them
   frame-by-frame from a `script()` function, `printh` the state, and
   `extcmd("shutdown")` to end the run; read the printh lines in the captured output.

## Cartridge file format (strict — harness reads the file, not chat)

- Line 1 exactly: `pico-8 cartridge // http://www.pico-8.com`
- Line 2 exactly: `version 8`
- Line 3 exactly: `__lua__`
- Then design-notes comment, then code. **Raw cartridge text only** — no Markdown,
  no code fences, no prose, no `#include`, fully self-contained.

## Gotchas

- Only the final saved file is graded; iterate freely with tools but leave the file clean.
- Never leave harness/debug code in the graded file; do all testing on copies in /tmp.
- Level solvability cannot be tested by the runner — make the dash-required obstacle and
  the main path correct by inspecting the tile grid, not by trial.
- The repo currently has no commits; don't assume git history for context.
