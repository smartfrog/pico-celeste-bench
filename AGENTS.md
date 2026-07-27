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
- `results/*.metrics.json` — per-model run metrics produced by the harness (same base
  name as the cartridge, e.g. `glm52.metrics.json` next to `glm52.p8`).
- `carts/` — gitignored output directory for generated cartridges.
- `bench/` — automated metrics harness. `bench/models.json` lists the models to run;
  `bench/run_bench.py` drives isolated OpenCode HTTP/SSE sessions (one run per model), reads
  `opencode export <sessionID>` for token/cost/time/tool metrics, and writes
  `results/<out>.p8` + `results/<out>.metrics.json` plus aggregated `results/metrics.csv`
  and `results/metrics.md`. Raw run artifacts go under `results/runs/<ts>/` (gitignored).
  It measures production cost, checks clean boot, and captures the cartridge's built-in
  autoplay proof as a GIF. Broader gameplay and visual quality remain manually judged.

## The task workflow (when asked to build the cartridge)

1. Review one or two web references for Celeste Classic PICO-8 (required first step).
2. Inspect `assets/sprites.png` and `assets/screenshot.png`, then make one short route sketch.
3. Write the `.p8` file with the exact 3-line header, then a 4–6 line design-notes
   comment, Lua, and any `__gfx__`/`__map__` sections.
4. Boot-check the complete draft, inspect a native-resolution screenshot, and establish the
   visual composition before implementing the deterministic demo.
5. Verify mechanics and the unattended demo; using the `pico8` MCP tools is recommended.
   Use the bounded build loop in the prompt: `pico8_boot` the cart, drive it with
   `pico8_step`/`pico8_play`, verify state with `pico8_read`, and inspect the scene with
   `pico8_screen`. The MCP runs a temp copy; the graded file is never modified.
   (MCP server: https://github.com/smartfrog/pico8-mcp — fallback: use scripted
   `btn`/`btnp` inputs on a copy in /tmp as described in the prompt.)
6. After the final edit and demo verification, check boot with:
   `timeout 10 pico8 -x <file>.p8 2>&1`
   - `pico8` is on PATH (`~/.local/bin/pico8`).
   - It runs forever on success, so the timeout firing is expected.
   - **Read the text output, not the exit code.** Only `RUNNING:` with no
     `syntax error` / `runtime error` line means a clean boot.
   - `-x` checks boot/syntax/runtime only — it does NOT validate gameplay or level
     solvability. Those must be correct by construction.

## Cartridge file format (strict — harness reads the file, not chat)

- Line 1 exactly: `pico-8 cartridge // http://www.pico-8.com`
- Line 2 exactly: `version 8`
- Line 3 exactly: `__lua__`
- Then design-notes comment, then code. **Raw cartridge text only** — no Markdown,
  no code fences, no prose, no `#include`, fully self-contained.

## Gotchas

- Only the final saved file is graded; iterate freely with tools but leave the file clean.
- Never leave harness/debug code in the graded file; do all testing on copies in /tmp.
- Level solvability cannot be discovered by the runner: construct the route from the prompt's
  known-good spacing rules, then verify it interactively and make only local corrections.
- The repo currently has no commits; don't assume git history for context.
