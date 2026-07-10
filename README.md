# PICO-Celeste Bench

PICO-Celeste Bench is a coding-agent benchmark where the output is not an abstract score, but a real playable PICO-8 cartridge.

The task is to generate a complete single-screen Celeste-like platformer with dash, collisions, original level design, sprites, and a clean boot.

## Why This Benchmark Exists

This benchmark tests whether an agent can ship a small but complete interactive artifact end to end.

Plausible code is not enough. The generated `.p8` cartridge has to boot, play, look coherent, and include an original level with a dash-required obstacle.

The task is intentionally compact, but it combines many failure-prone requirements:

- strict PICO-8 cartridge file format
- responsive platformer movement
- jump and 8-direction dash mechanics
- dash recharge behavior
- solid collision handling
- spike death and respawn
- strawberry collection
- goal detection and `CLEAR!` state
- readable PICO-8 visuals based on reference assets
- original single-screen level design

## Current Results

Current ranking for the included model outputs:

| Rank | Model | Cartridge |
| ---: | --- | --- |
| 1 | Fable | `results/fable5.p8` |
| 2 | Opus 4.8 | `results/opus48.p8` |
| 3 | GLM 5.2 | `results/glm52.p8` |
| 4 | GPT-5.5 | `results/gpt55.p8` |
| 5 | Qwen 3.7 Max | `results/qwen37.p8` |
| 6 | Kimi K7 | `results/kimik7.p8` |
| 7 | MiniMax M3 | `results/minimaxm3.p8` |

GLM 5.2 was the most surprising run: despite not being a vision model, it produced one of the strongest visual results.

## Repository Layout

| Path | Purpose |
| --- | --- |
| `prompts/celeste_like.md` | Full benchmark prompt given to the agent under test. This is the source of truth. |
| `assets/sprites.png` | Reference sprite sheet the generated cartridge should resemble. |
| `assets/screenshot.png` | Reference screenshot for the target visual mood and layout. |
| `results/*.p8` | Generated cartridges from different models. |
| `carts/` | Gitignored output directory for new generated cartridges. |

## Benchmark Task

The agent must create a raw `.p8` cartridge text file. The file must start with exactly:

```text
pico-8 cartridge // http://www.pico-8.com
version 8
__lua__
```

After that, the cartridge must include a short design-notes comment, Lua code, and any required `__gfx__` or `__map__` sections.

The generated game must include:

- left/right movement
- jump
- 8-direction dash
- gravity suspended during dash
- diagonal dash normalization
- dash recharge only when grounded
- spike death and respawn
- strawberry collection and score
- visible goal flag
- `CLEAR!` message on victory
- frozen game state after victory
- at least one obstacle that requires dash
- recognizable PICO-8 Celeste-like visuals

Read `prompts/celeste_like.md` for the full specification.

## Running A Cartridge

You need PICO-8 installed and available on `PATH`.

To launch one of the included results:

```sh
pico8 results/fable5.p8
```

To check that a cartridge boots cleanly without interacting with it:

```sh
timeout 10 pico8 -x results/fable5.p8 2>&1
```

A clean boot prints `RUNNING:` with no `syntax error` or `runtime error` line. The timeout itself is expected because a successful PICO-8 cart keeps running.

Important: `pico8 -x` only checks boot, syntax, and startup runtime errors. It does not prove that the game is fun, beatable, or mechanically correct.

## Interactive Play-Testing (MCP)

Gameplay itself is play-tested with [pico8-mcp](https://github.com/smartfrog/pico8-mcp), an MCP server that runs a cart under deterministic, frame-by-frame lockstep control: the agent can hold buttons, advance N frames, read Lua globals (player position, deaths, win flag), and take pixel-perfect screenshots.

It copies the cart to a temp directory and injects its control harness there, so the graded `.p8` file is never modified. Example opencode configuration:

```json
{
  "mcp": {
    "pico8": {
      "type": "local",
      "command": ["node", "/path/to/pico8-mcp/dist/index.js"],
      "enabled": true
    }
  }
}
```

## Creating A New Result

Save generated cartridges in `carts/` while iterating:

```sh
mkdir -p carts
```

Then give the agent the prompt from:

```text
prompts/celeste_like.md
```

The final output should be a self-contained `.p8` file. Do not leave test harness code or debug-only changes in the final cartridge.

## Automated Benchmark Harness

The harness in `bench/` drives opencode headless to generate one cartridge per
model and collects quantitative metrics for each run. It does not score gameplay
quality (that stays manual); it measures the cost of producing the cartridge.

Configure the models in `bench/models.json`:

```json
{
  "repetitions": 1,
  "timeout_seconds": 1200,
  "agent": "build",
  "prompt_file": "prompts/celeste_like.md",
  "models": [
    { "model": "voban/minimax-m3", "variant": "thinking", "out": "minimaxm3" },
    { "model": "voban/glm-5.2", "variant": "max", "out": "glm52" },
    { "model": "openai/gpt-5.5", "out": "gpt55" }
  ]
}
```

- `model`: `provider/model` passed to `opencode run --model`.
- `variant` (optional): reasoning effort passed to `--variant` (e.g. `high`, `max`,
  `thinking`). Check available variants with `opencode models <provider> --verbose`.
- `out`: stable output name. Produces `results/<out>.p8` (final cartridge) and
  `results/<out>.metrics.json` (per-model metrics). It also serves as the display id.
- `label` (optional): prettier display text; defaults to `out`.

Run it:

```sh
python bench/run_bench.py                 # uses bench/models.json
python bench/run_bench.py --config path   # custom config
python bench/run_bench.py --dry-run       # print planned runs, do nothing
python bench/run_bench.py --quiet         # hide live model/tool activity
```

For each model the harness invokes `opencode run --format json`, captures the
session id from the stream, and displays the model messages and tool calls live.
Pass `--quiet` to suppress that live activity. It then reads
`opencode export <sessionID>` (the reliable source of truth) to extract metrics.
If that export fails or is invalid, the same metrics are recovered from the raw
JSONL event stream instead.
Raw artifacts (`.stream.jsonl`, `.export.json`) are written under
`results/runs/<timestamp>/` (gitignored). The final cartridge and its metrics land
in `results/` (committable), plus aggregated `results/metrics.csv` and
`results/metrics.md`.

Metrics collected per run:

| Metric | Meaning |
| --- | --- |
| `tokens_input` / `tokens_output` / `tokens_reasoning` | token usage from the session export |
| `cache_read` / `cache_write` | prompt-cache token usage |
| `tokens_total` | input + output + reasoning |
| `cost` | reported session cost in USD |
| `wall_seconds` | wall-clock time measured by the harness |
| `session_seconds` | `time.updated - time.created` from the export |
| `assistant_messages` | number of assistant turns (iterations) |
| `tool_calls_total` / `tool_calls_by_name` | tool invocations, total and per tool |
| `booted_clean` | factual `pico8 -x` clean-boot check (not a gameplay score) |
| `cartridge_written` | whether the target `.p8` file exists after the run |

Note: `pico8 -x` only proves the cart boots; it does not validate gameplay. Quality
ranking (the table above) remains a manual judgement.

## Evaluation Notes

The strongest cartridges tend to satisfy three things at once:

- they boot cleanly as raw PICO-8 cartridge files
- they are actually playable as tiny platformers
- they visually read as intentional PICO-8 games rather than rough code demos

The benchmark is deliberately small, but it is hard to fake because the final artifact can be launched and played.
