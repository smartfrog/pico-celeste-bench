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

## Evaluation Notes

The strongest cartridges tend to satisfy three things at once:

- they boot cleanly as raw PICO-8 cartridge files
- they are actually playable as tiny platformers
- they visually read as intentional PICO-8 games rather than rough code demos

The benchmark is deliberately small, but it is hard to fake because the final artifact can be launched and played.
