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
- `bench/route_check.py` — geometry oracle for the 16x16 level grid. Answers the layout
  questions (landing surfaces, height bands, forced gap, headroom, spike groups, berries,
  spawn footing, goal placement, dash-required crossing, and a spawn-to-goal move list) so
  they never have to be worked out on paper. `bench/test_route_check.py` covers it, including
  agreement with the prompt's spacing table.
- `bench/` — automated metrics harness. `bench/models.json` lists the models to run;
  `bench/run_bench.py` drives isolated OpenCode HTTP/SSE sessions (one run per model), reads
  `opencode export <sessionID>` for token/cost/time/tool metrics, and writes
  `results/<out>.p8` + `results/<out>.metrics.json` plus aggregated `results/metrics.csv`
  and `results/metrics.md`. Raw run artifacts go under `results/runs/<ts>/` (gitignored).
  It measures production cost, checks clean boot, and captures the cartridge's built-in
  autoplay proof as a GIF. Broader gameplay and visual quality remain manually judged.
  Runs are unattended by default and resume a stalled session automatically; `--interactive`
  restores the old prompt-per-attempt flow.

## Effort metrics (thinking versus doing)

Token totals hide the failure mode where a model reasons for half an hour and writes nothing,
so `metrics.md` carries a second table built from the raw stream: `reasoning_chars`,
`reasoning_per_tool_call`, `tool_calls_completed`, `cart_edits`, `time_to_first_tool_s`,
`time_to_first_edit_s`, and `max_no_tool_gap_s` (the longest stretch with no tool call).

Observed reference points from real runs:

| run | reasoning chars | tools | edits | longest silence |
| --- | ---: | ---: | ---: | ---: |
| clean run that shipped a cart | n/a (legacy stream) | 49 | 5 | 490s |
| reasoned 27 min, wrote no file | 135,900 | 15 | 0 | 1,611s |
| 5 attempts, re-derived the level each time | 524,294 | 34 | 8 | 2,515s |
| output capped at 24000, first file after 933s | 82,296 | 22 | 1 | 322s |

`cart_edits` near zero together with a long silence is the signature. These columns are
recorded only; nothing in the harness reacts to them mid-run.

## The task workflow (when asked to build the cartridge)

1. Write the deliverable `.p8` first: 3-line header, notes comment holding a draft 16x16 grid,
   and a bootable skeleton. A rough draft is fine; from then on there is something to run,
   measure, and improve, and a resumed attempt has real state to read.
2. Boot-check it, then review one or two web references for Celeste Classic PICO-8 and inspect
   `assets/sprites.png` and `assets/screenshot.png`.
3. Bring the grid up to contract by running the oracle until every check passes:
   `python3 bench/route_check.py --from-cart <file>.p8 --solve`
   Grid legend: `.` empty, `#` solid, `^` spike, `s` spawn, `b` berry, `g` goal. Add
   `--spawn COL,ROW` when the spawn lives in Lua. The reported move list maps one-for-one
   onto the demo controller's phases.
4. Fill in the rest of the cartridge: full mechanics, `__gfx__`/`__map__` sections, and the
   4–6 line design-notes comment in its final form.
5. Inspect a native-resolution screenshot and establish the visual composition before
   implementing the deterministic demo.
6. Verify mechanics and the unattended demo; using the `pico8` MCP tools is recommended.
   Use the bounded build loop in the prompt: `pico8_boot` the cart, drive it with
   `pico8_step`/`pico8_play`, verify state with `pico8_read`, and inspect the scene with
   `pico8_screen`. The MCP runs a temp copy; the graded file is never modified.
   (MCP server: https://github.com/smartfrog/pico8-mcp — fallback: use scripted
   `btn`/`btnp` inputs on a copy in /tmp as described in the prompt.)
7. After the final edit and demo verification, check boot with:
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
- `pico8 -x` validates boot only. For solvability, ask `bench/route_check.py`; it is
  authoritative for spacing and reach, while the running cartridge is authoritative for
  gameplay.
- A ledge stacked less than 3 rows above another kills every jump from the lower one: a 9.5px
  jump puts the head into the tile above. This is the single most common reason a hand-designed
  switchback climb turns out impossible. The oracle reports the clear height per column
  (`headroom above surfaces` fails only when a surface has no usable column; `surfaces under an
  overhang` warns about the partial case), and `--solve` is the real authority: a climb that
  cannot be jumped simply yields no route.
- Per-turn output is capped (`max_output_tokens` in `bench/models.json`, currently 48000). The
  cap counts tool-call arguments too, so a low value truncates a turn that is working: at 24000
  an observed run spent its first turn on the reference pass and ended with no file. Write the
  design into the cartridge early instead; a resumed attempt re-reads the file, never the
  previous turn's reasoning.
- The repo currently has no commits; don't assume git history for context.
