#!/usr/bin/env python3
"""Geometry oracle for the single-screen Celeste-like cartridge task.

Answers, from a 16x16 tile grid, the questions the task would otherwise force a
model to work out on paper:

  * does the layout satisfy the level contract (surfaces, height bands, forced
    gap, headroom, spike groups, berries, spawn, goal)?
  * is the goal actually reachable with the supplied movement constants, and by
    which sequence of grounded-initiated moves?
  * does the forced gap really fail without a dash?

The oracle is authoritative for spacing. The cartridge is authoritative for
gameplay. Reported margins show how much slack a move has, so a route that only
just works in the oracle can be widened before it is built.

Grid legend (aliases accepted, case-insensitive):

    .   empty / background        # = x i r   solid rock or ice
    ^   upward spike              b           strawberry
    s   spawn                     g           goal flag

Usage:

    python3 bench/route_check.py --grid level.txt
    python3 bench/route_check.py --from-cart results/mycart.p8 --solve
"""

import argparse
import heapq
import sys
from dataclasses import dataclass, replace
from pathlib import Path

GRID_W = 16
GRID_H = 16
TILE = 8

# The legend is exactly the one documented in prompts/celeste_like.md. Guessing
# extra aliases is dangerous: a cartridge using "x" for spikes would have them
# read as solid ground, and the solver would certify a route straight through
# them. An unknown character makes the block fail to parse instead, which is a
# visible error rather than a confident wrong answer.
EMPTY_CHARS = set(". -_,")
SOLID_CHARS = set("#")
SPIKE_CHARS = set("^")
BERRY_CHARS = set("bB")
GOAL_CHARS = set("gG")
SPAWN_CHARS = set("sS")

LEGEND_CHARS = (
    EMPTY_CHARS | SOLID_CHARS | SPIKE_CHARS | BERRY_CHARS | GOAL_CHARS | SPAWN_CHARS
)

# Movement constants, taken verbatim from prompts/celeste_like.md.
MAX_RUN = 1.0
ACCEL = 0.6
DECEL = 0.15
GRAVITY = 0.21
MAX_FALL = 2.0
JUMP_V = -2.0
DASH_SPEED = 5.0
DASH_DIAG = 0.7071
DASH_HITSTOP = 2
DASH_FRAMES = 4
HITBOX = 6

# Solver shape. Small on purpose: every macro is something a state-based
# controller can express with grounded and position predicates.
PRE_RUN_FRAMES = (0, 10, 24)
WALK_FRAMES = (4, 8, 12, 16, 22, 30, 40)
DASH_DELAYS = (0, 4, 8)
EDGE_RUN_CAP = 60
# Search cost is measured in updates, plus a penalty per dash so plain jumps win
# when both work. Routes then read like something a demo controller would do.
DASH_PENALTY = 25
DASH_DIRS = (
    (1, 0), (-1, 0), (0, -1), (0, 1),
    (1, -1), (-1, -1), (1, 1), (-1, 1),
)
# Airborne dashes only ever need to extend or lift a jump. A downward air dash
# shortens the arc, which plain falling already covers, so leaving those out
# halves the search without losing a way to reach any surface.
AIR_DASH_DIRS = ((1, 0), (-1, 0), (0, -1), (1, -1), (-1, -1))
SETTLE_FRAMES = 120


def approach(value, target, step):
    if value > target:
        return max(value - step, target)
    return min(value + step, target)


def clamp(value, low, high):
    return max(low, min(high, value))


class Grid:
    """A 16x16 tile grid with the entities the level contract talks about."""

    def __init__(self, rows, source=None):
        self.rows = list(rows)
        self.source = source
        self.spawns = []
        self.goals = []
        self.berries = []
        self.spikes = []
        for row, line in enumerate(self.rows):
            for col, char in enumerate(line):
                if char in SPAWN_CHARS:
                    self.spawns.append((col, row))
                elif char in GOAL_CHARS:
                    self.goals.append((col, row))
                elif char in BERRY_CHARS:
                    self.berries.append((col, row))
                elif char in SPIKE_CHARS:
                    self.spikes.append((col, row))
        # Flat lookup tables: the solver reads these millions of times, and
        # indexing a list beats re-testing characters against sets.
        self._solid = [False] * (GRID_W * GRID_H)
        self._spike = [False] * (GRID_W * GRID_H)
        for row in range(min(GRID_H, len(self.rows))):
            line = self.rows[row]
            for col in range(min(GRID_W, len(line))):
                char = line[col]
                if char in SOLID_CHARS:
                    self._solid[row * GRID_W + col] = True
                elif char in SPIKE_CHARS:
                    self._spike[row * GRID_W + col] = True
        self._berry_index = {tile: index for index, tile in enumerate(self.berries)}
        self._goal_tiles = set(self.goals)
        # One report runs several searches over overlapping states; remembering
        # macro outcomes keeps the later searches cheap.
        self._macro_cache = {}

    @property
    def width(self):
        return max((len(line) for line in self.rows), default=0)

    @property
    def height(self):
        return len(self.rows)

    def char(self, col, row):
        if 0 <= row < len(self.rows) and 0 <= col < len(self.rows[row]):
            return self.rows[row][col]
        return None

    def is_solid(self, col, row):
        """Screen sides block movement; there is no floor below the screen.

        The level does not scroll, so the left and right edges are walls at every
        height, including above the visible rows.
        """
        if col < 0 or col >= GRID_W:
            return True
        if row < 0 or row >= GRID_H:
            return False
        return self._solid[row * GRID_W + col]

    def is_spike(self, col, row):
        if col < 0 or col >= GRID_W or row < 0 or row >= GRID_H:
            return False
        return self._spike[row * GRID_W + col]

    def is_empty(self, col, row):
        return not self.is_solid(col, row) and not self.is_spike(col, row)

    def berry_index(self, col, row):
        return self._berry_index.get((col, row))

    def render(self):
        header = "    " + "".join(str(c % 10) for c in range(GRID_W))
        lines = [header]
        for row, line in enumerate(self.rows):
            lines.append(f" {row:2d} {line}")
        return "\n".join(lines)


def parse_grid_lines(text):
    """Pull the first block of 16 consecutive 16-character legend rows.

    Works for a plain grid file, a Lua table of 16 strings, and a design-notes
    comment block, so the grid can live in the cartridge itself.
    """
    candidates = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.strip()
        while line.startswith("--"):
            line = line[2:].strip()
        line = line.strip("[]{}")
        line = line.strip().strip(",").strip()
        if len(line) >= 2 and line[0] in "\"'" and line[-1] == line[0]:
            line = line[1:-1]
        if len(line) == GRID_W and all(char in LEGEND_CHARS for char in line):
            candidates.append((number, line))
        else:
            candidates.append(None)

    run = []
    for entry in candidates + [None]:
        if entry is None:
            if len(run) == GRID_H:
                return [line for _, line in run], run[0][0]
            if len(run) > GRID_H:
                # Truncating would silently analyse a shifted grid, so refuse.
                raise ValueError(
                    f"found {len(run)} consecutive grid-shaped rows starting at line "
                    f"{run[0][0]}, expected exactly {GRID_H}; a neighbouring line "
                    f"(separator, border, or extra row) looks like grid data"
                )
            run = []
        else:
            run.append(entry)
    return None, None


def load_grid(path):
    text = Path(path).read_text(errors="replace")
    rows, first_line = parse_grid_lines(text)
    if rows is None:
        raise ValueError(
            f"{path}: no block of {GRID_H} consecutive {GRID_W}-character grid rows found"
        )
    return Grid(rows, source=f"{path} line {first_line}")


# --------------------------------------------------------------------------
# Static contract checks
# --------------------------------------------------------------------------


@dataclass
class Check:
    name: str
    ok: bool
    detail: str
    required: bool = True


def landing_surfaces(grid):
    """Maximal horizontal runs of solid tiles whose top side is standable."""
    surfaces = []
    for row in range(GRID_H):
        col = 0
        while col < GRID_W:
            if grid.is_solid(col, row) and grid.is_empty(col, row - 1):
                start = col
                while (
                    col < GRID_W
                    and grid.is_solid(col, row)
                    and grid.is_empty(col, row - 1)
                ):
                    col += 1
                surfaces.append((row, start, col - 1))
            else:
                col += 1
    return surfaces


def forced_gaps(grid):
    """Equal-height standable edges separated by exactly 4 empty columns."""
    found = []
    for row in range(GRID_H):
        for left in range(GRID_W):
            right = left + 5
            if right >= GRID_W:
                continue
            if not (grid.is_solid(left, row) and grid.is_empty(left, row - 1)):
                continue
            if not (grid.is_solid(right, row) and grid.is_empty(right, row - 1)):
                continue
            between = range(left + 1, right)
            if not all(grid.is_empty(col, row) for col in between):
                continue
            headroom = min(clear_headroom(grid, col, row - 1) for col in range(left, right + 1))
            found.append((row, left, right, headroom))
    return found


def clear_headroom(grid, col, row):
    """Number of empty tiles going up from (col, row)."""
    count = 0
    while row >= 0 and grid.is_empty(col, row):
        count += 1
        row -= 1
    return count


def surface_containing(grid, col, row):
    for surface in landing_surfaces(grid):
        if surface[0] == row and surface[1] <= col <= surface[2]:
            return surface
    return None


def surface_headroom(grid, surface):
    """Clear height above each column of a surface, in tiles.

    A jump rises about 9.5px, so a column with fewer than 2 clear tiles puts the
    player's head into the tile above. Columns are reported individually: a
    surface can be partly covered by a ledge and still be usable from its clear
    end, while a surface with no clear column cannot host a jump at all.
    """
    row, left, right = surface
    return {col: clear_headroom(grid, col, row - 1) for col in range(left, right + 1)}


def connected_groups(cells):
    """Split tiles into 4-connected groups, so a 2-tile flag counts as one."""
    remaining = set(cells)
    groups = []
    while remaining:
        seed = remaining.pop()
        group = [seed]
        queue = [seed]
        while queue:
            col, row = queue.pop()
            for offset in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                neighbour = (col + offset[0], row + offset[1])
                if neighbour in remaining:
                    remaining.remove(neighbour)
                    group.append(neighbour)
                    queue.append(neighbour)
        groups.append(sorted(group))
    return groups


def spike_groups(grid):
    return connected_groups(grid.spikes)


def static_checks(grid):
    checks = []

    dimensions_ok = grid.height == GRID_H and all(len(r) == GRID_W for r in grid.rows)
    checks.append(Check(
        "grid shape",
        dimensions_ok,
        f"{grid.width}x{grid.height} (need {GRID_W}x{GRID_H})",
    ))

    title_offenders = [
        (col, 0) for col in range(GRID_W)
        if grid.char(col, 0) in SOLID_CHARS | SPIKE_CHARS | BERRY_CHARS | GOAL_CHARS
    ]
    checks.append(Check(
        "title zone",
        not title_offenders,
        "row 0 clear" if not title_offenders
        else f"row 0 occupied at columns {[c for c, _ in title_offenders]}",
    ))

    surfaces = landing_surfaces(grid)
    bands = sorted({row for row, _, _ in surfaces})
    checks.append(Check(
        "landing surfaces",
        len(surfaces) >= 4 and len(bands) >= 3,
        f"{len(surfaces)} surfaces in {len(bands)} height bands (rows {bands}); "
        f"need >=4 surfaces in >=3 bands",
    ))

    gaps = forced_gaps(grid)
    usable = [gap for gap in gaps if gap[3] >= 2]
    if gaps and not usable:
        detail = (
            f"{len(gaps)} candidate gap(s) found but headroom < 2 tiles: "
            + ", ".join(f"row {r} cols {a}->{b} headroom {h}" for r, a, b, h in gaps)
        )
    elif usable:
        detail = ", ".join(
            f"row {r} takeoff col {a} landing col {b} headroom {h}"
            for r, a, b, h in usable
        )
    else:
        detail = "no pair of equal-height standable edges with exactly 4 empty columns"
    checks.append(Check("forced gap", bool(usable), detail))

    unjumpable = []
    partly_covered = []
    for surface in surfaces:
        heights = surface_headroom(grid, surface)
        row, left, right = surface
        low = sorted(col for col, height in heights.items() if height < 2)
        if not low:
            continue
        if len(low) == len(heights):
            unjumpable.append(f"row {row} cols {left}-{right}")
        else:
            partly_covered.append(f"row {row} cols {low} (clear at "
                                  f"{[c for c in heights if c not in low]})")
    checks.append(Check(
        "headroom above surfaces",
        not unjumpable,
        "every surface has a column with 2+ tiles of clear height"
        if not unjumpable
        else "no jump is possible from: " + ", ".join(unjumpable),
    ))
    checks.append(Check(
        "surfaces under an overhang",
        not partly_covered,
        "none" if not partly_covered
        else "a jump from these columns hits the tile above: "
             + "; ".join(partly_covered),
        required=False,
    ))

    groups = spike_groups(grid)
    checks.append(Check(
        "spike groups",
        len(groups) >= 2,
        f"{len(groups)} separate group(s): "
        + "; ".join(str(g) for g in groups) if groups else "none",
    ))

    floating = [
        (col, row) for col, row in grid.spikes
        if not grid.is_solid(col, row + 1)
    ]
    checks.append(Check(
        "spikes rest on solids",
        not floating,
        "all grounded" if not floating else f"floating spikes at {floating}",
        required=False,
    ))

    checks.append(Check(
        "spawn",
        len(grid.spawns) == 1,
        f"{len(grid.spawns)} spawn marker(s) (need exactly 1)"
        + ("; pass --spawn COL,ROW if the cartridge sets it in Lua"
           if not grid.spawns else ""),
        required=bool(grid.spawns),
    ))
    goal_groups = connected_groups(grid.goals)
    checks.append(Check(
        "goal",
        len(goal_groups) == 1,
        f"{len(goal_groups)} goal flag(s) over {len(grid.goals)} tile(s) "
        f"(need exactly 1 flag)",
    ))
    checks.append(Check(
        "berries",
        len(grid.berries) >= 2,
        f"{len(grid.berries)} strawberr{'y' if len(grid.berries) == 1 else 'ies'} "
        f"at {grid.berries} (need >=2)",
    ))

    if grid.spawns:
        spawn = grid.spawns[0]
        floor = grid.is_solid(spawn[0], spawn[1] + 1)
        clear = grid.is_empty(spawn[0], spawn[1]) and grid.is_empty(spawn[0], spawn[1] - 1)
        checks.append(Check(
            "spawn footing",
            floor and clear,
            f"spawn {spawn}: floor below={floor}, 2 tiles clear={clear}",
        ))
        if grid.goals:
            goal = max(grid.goals, key=lambda tile: tile[1])
            distance = abs(goal[0] - spawn[0]) + abs(goal[1] - spawn[1])
            elevated = goal[1] < spawn[1]
            right_half = goal[0] >= GRID_W // 2
            checks.append(Check(
                "goal placement",
                distance >= 8 and right_half,
                f"goal {goal}: distance {distance} tiles from spawn (need >=8), "
                f"right half={right_half}, elevated={elevated}",
            ))
        far_berries = [
            berry for berry in grid.berries
            if abs(berry[0] - spawn[0]) + abs(berry[1] - spawn[1]) >= 4
        ]
        checks.append(Check(
            "berries away from spawn",
            len(far_berries) == len(grid.berries),
            f"{len(far_berries)}/{len(grid.berries)} berries at least 4 tiles from spawn",
        ))
        distinct_rows = len({berry[1] for berry in grid.berries})
        checks.append(Check(
            "berries in different situations",
            distinct_rows >= 2 or len(grid.berries) < 2,
            f"berries occupy {distinct_rows} distinct row(s)",
            required=False,
        ))

    return checks


# --------------------------------------------------------------------------
# Movement model
# --------------------------------------------------------------------------


@dataclass
class Player:
    x: float
    y: float
    vx: float = 0.0
    vy: float = 0.0
    grounded: bool = False
    can_dash: bool = True
    hitstop: int = 0
    dash_left: int = 0
    dash_vx: float = 0.0
    dash_vy: float = 0.0
    facing: int = 1
    dead: bool = False
    won: bool = False
    berries: int = 0


@dataclass
class Inputs:
    dx: int = 0
    dy: int = 0
    jump: bool = False
    dash: bool = False


def box_hits_solid(grid, x, y):
    left = int(x // TILE)
    right = int((x + HITBOX - 1) // TILE)
    if left < 0 or right >= GRID_W:
        return True
    top = int(y // TILE)
    bottom = int((y + HITBOX - 1) // TILE)
    if top < 0:
        top = 0
    if bottom > GRID_H - 1:
        bottom = GRID_H - 1
    solid = grid._solid
    row = top
    while row <= bottom:
        base = row * GRID_W
        col = left
        while col <= right:
            if solid[base + col]:
                return True
            col += 1
        row += 1
    return False


def move_axis(grid, player, dx, dy):
    """Move in <=1px steps, reporting whether the axis was blocked."""
    remaining = dx if dx else dy
    blocked = False
    while abs(remaining) > 1e-9:
        step = clamp(remaining, -1.0, 1.0)
        nx = player.x + (step if dx else 0.0)
        ny = player.y + (step if dy else 0.0)
        if box_hits_solid(grid, nx, ny):
            blocked = True
            break
        player.x, player.y = nx, ny
        remaining -= step
    return blocked


def aim(inputs, facing):
    """Dash direction, defaulting to the facing direction as the prompt requires.

    Every macro holds a direction while dashing, so the fallback never fires
    during a search; it exists so the model's required behaviour is modelled.
    """
    dx, dy = inputs.dx, inputs.dy
    if dx == 0 and dy == 0:
        return facing, 0
    return dx, dy


def touch_entities(grid, player):
    if player.y >= GRID_H * TILE:
        player.dead = True
        return
    x, y = player.x, player.y
    left = int(x // TILE)
    right = int((x + HITBOX - 1) // TILE)
    top = int(y // TILE)
    bottom = int((y + HITBOX - 1) // TILE)
    spike = grid._spike
    falling = player.vy >= 0
    berries = grid._berry_index
    goals = grid._goal_tiles
    for row in range(max(top, 0), min(bottom, GRID_H - 1) + 1):
        base = row * GRID_W
        for col in range(max(left, 0), min(right, GRID_W - 1) + 1):
            if falling and spike[base + col]:
                player.dead = True
            elif (col, row) in goals:
                player.won = True
            else:
                index = berries.get((col, row))
                if index is not None:
                    player.berries |= 1 << index


def step(grid, player, inputs):
    if player.dead or player.won:
        return

    if player.hitstop > 0:
        player.hitstop -= 1
        return

    if player.dash_left > 0:
        move_axis(grid, player, player.dash_vx, 0)
        move_axis(grid, player, 0, player.dash_vy)
        player.dash_left -= 1
        if player.dash_left == 0:
            player.vx = clamp(player.dash_vx, -MAX_RUN, MAX_RUN)
            player.vy = 0.0 if player.dash_vy <= 0 else clamp(player.dash_vy, 0, MAX_FALL)
        player.grounded = box_hits_solid(grid, player.x, player.y + 1)
        if player.grounded:
            player.can_dash = True
        touch_entities(grid, player)
        return

    if inputs.dash and player.can_dash:
        dx, dy = aim(inputs, player.facing)
        vx, vy = dx * DASH_SPEED, dy * DASH_SPEED
        if dx != 0 and dy != 0:
            vx, vy = vx * DASH_DIAG, vy * DASH_DIAG
        player.dash_vx, player.dash_vy = vx, vy
        player.can_dash = False
        # The pressing update is the first of the two hitstop updates.
        player.hitstop = DASH_HITSTOP - 1
        player.dash_left = DASH_FRAMES
        player.vx = player.vy = 0.0
        return

    if inputs.dx != 0:
        player.facing = inputs.dx
        player.vx = approach(player.vx, MAX_RUN * inputs.dx, ACCEL)
    else:
        player.vx = approach(player.vx, 0.0, DECEL)

    player.vy = approach(player.vy, MAX_FALL, GRAVITY)
    if inputs.jump and player.grounded:
        player.vy = JUMP_V

    if move_axis(grid, player, player.vx, 0):
        player.vx = 0.0
    if move_axis(grid, player, 0, player.vy):
        if player.vy > 0:
            player.grounded = True
        player.vy = 0.0

    player.grounded = box_hits_solid(grid, player.x, player.y + 1)
    if player.grounded:
        player.can_dash = True

    touch_entities(grid, player)


def spawn_player(grid):
    if not grid.spawns:
        raise ValueError("grid has no spawn marker")
    col, row = grid.spawns[0]
    player = Player(x=col * TILE + 1.0, y=row * TILE + 2.0)
    player.grounded = box_hits_solid(grid, player.x, player.y + 1)
    # Settle onto the floor so the start state matches a real _init.
    for _ in range(40):
        step(grid, player, Inputs())
        if player.grounded and abs(player.vy) < 1e-6:
            break
    return player


# --------------------------------------------------------------------------
# Macro-action solver
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Macro:
    kind: str
    direction: int = 0
    pre_run: int = 0
    frames: int = 0
    dash_delay: int = 0
    dash_dir: tuple = (0, 0)

    def describe(self):
        side = "right" if self.direction > 0 else "left"
        if self.kind == "walk":
            return f"walk {side} {self.frames}f"
        if self.kind == "walk-to-edge":
            return f"walk {side} to the surface edge"
        if self.kind == "ground-dash":
            return f"ground dash {dir_name(self.dash_dir)}"
        if self.kind == "edge-jump":
            label = f"run {side} to the edge and jump"
        else:
            label = f"run {self.pre_run}f then jump {side}"
        if self.dash_dir != (0, 0):
            label += f" + dash {dir_name(self.dash_dir)} {self.dash_delay}f after takeoff"
        return label


def dir_name(direction):
    names = {
        (1, 0): "right", (-1, 0): "left", (0, -1): "up", (0, 1): "down",
        (1, -1): "up-right", (-1, -1): "up-left",
        (1, 1): "down-right", (-1, 1): "down-left",
    }
    return names.get(direction, str(direction))


def at_surface_edge(grid, player, direction):
    """True when one more pixel in `direction` would leave solid ground."""
    return not box_hits_solid(grid, player.x + direction, player.y + 1)


def drive_macro(grid, player, macro):
    """Feed a macro's inputs frame by frame, honouring its state predicates.

    Yields after every simulated frame so the caller can stop on death or win.
    """
    direction = macro.direction

    if macro.kind == "walk":
        for _ in range(macro.frames):
            step(grid, player, Inputs(dx=direction))
            yield
        return

    if macro.kind == "walk-to-edge":
        for _ in range(EDGE_RUN_CAP):
            if player.grounded and at_surface_edge(grid, player, direction):
                return
            step(grid, player, Inputs(dx=direction))
            yield
        return

    if macro.kind == "ground-dash":
        dx, dy = macro.dash_dir
        step(grid, player, Inputs(dx=dx, dy=dy, dash=True))
        yield
        return

    if macro.kind == "edge-jump":
        took_off = False
        for _ in range(EDGE_RUN_CAP):
            if player.grounded and at_surface_edge(grid, player, direction):
                step(grid, player, Inputs(dx=direction, jump=True))
                yield
                took_off = True
                break
            step(grid, player, Inputs(dx=direction))
            yield
        if not took_off:
            return
    else:
        for _ in range(macro.pre_run):
            step(grid, player, Inputs(dx=direction))
            yield
        step(grid, player, Inputs(dx=direction, jump=True))
        yield

    if macro.dash_dir == (0, 0):
        for _ in range(40):
            step(grid, player, Inputs(dx=direction))
            yield
        return

    for _ in range(macro.dash_delay):
        step(grid, player, Inputs(dx=direction))
        yield
    dx, dy = macro.dash_dir
    step(grid, player, Inputs(dx=dx, dy=dy, dash=True))
    yield
    for _ in range(40):
        step(grid, player, Inputs(dx=dx))
        yield


def run_macro(grid, start, macro, allow_dash=True):
    """Simulate one macro from a grounded rest state to the next rest state.

    Results are memoised per grid: start states are settled rest states, so
    `node_key` describes them completely.
    """
    if not allow_dash and (macro.dash_dir != (0, 0) or macro.kind == "ground-dash"):
        return None
    cache_key = (node_key(start), macro, allow_dash)
    cached = grid._macro_cache.get(cache_key, False)
    if cached is not False:
        if cached is None:
            return None
        player, frames, won = cached
        return replace(player), frames, won
    result = simulate_macro(grid, start, macro)
    grid._macro_cache[cache_key] = result
    if result is None:
        return None
    player, frames, won = result
    return replace(player), frames, won


def simulate_macro(grid, start, macro):
    player = replace(start)
    frames = 0
    airborne = False
    for _ in drive_macro(grid, player, macro):
        frames += 1
        if player.dead or player.won:
            break
        if not player.grounded:
            airborne = True
        elif airborne and abs(player.vy) < 1e-6:
            # Landed: stop holding inputs and let the state settle below.
            break
    settled = False
    while not player.dead and not player.won and frames < SETTLE_FRAMES:
        step(grid, player, Inputs())
        frames += 1
        if player.grounded and abs(player.vy) < 1e-6 and abs(player.vx) < 1e-6:
            settled = True
            break
    if player.dead:
        return None
    if player.won:
        return player, frames, True
    if not settled:
        return None
    return player, frames, False


def node_key(player):
    return (round(player.x), round(player.y), player.berries)


@dataclass
class Search:
    steps: list = None
    expanded: int = 0
    exhausted: bool = False

    @property
    def found(self):
        return self.steps is not None


def bfs(grid, start, accept, allow_dash=True, max_nodes=20000):
    """Cheapest macro sequence from `start` to any state satisfying `accept`.

    Cost is updates plus `DASH_PENALTY` per dash, so a plain jump wins whenever
    one works. The reported update counts stay un-penalised.
    """
    macros = list(enumerate_macros())
    origin = node_key(start)
    states = {origin: start}
    best = {origin: 0}
    previous = {}
    queue = [(0, 0, origin)]
    order = 0
    expanded = 0

    if accept(start):
        return Search(steps=[], expanded=0)

    while queue:
        cost, _, key = heapq.heappop(queue)
        if cost > best.get(key, 1 << 30):
            continue
        expanded += 1
        if expanded > max_nodes:
            return Search(expanded=expanded, exhausted=True)
        current = states[key]
        for macro in macros:
            result = run_macro(grid, current, macro, allow_dash=allow_dash)
            if result is None:
                continue
            player, frames, _ = result
            uses_dash = macro.dash_dir != (0, 0) or macro.kind == "ground-dash"
            next_cost = cost + frames + (DASH_PENALTY if uses_dash else 0)
            if accept(player):
                final = ("accept", order)
                previous[final] = (key, macro, player, frames)
                return Search(
                    steps=reconstruct(previous, origin, final),
                    expanded=expanded,
                )
            next_key = node_key(player)
            if next_cost < best.get(next_key, 1 << 30):
                best[next_key] = next_cost
                states[next_key] = player
                previous[next_key] = (key, macro, player, frames)
                order += 1
                heapq.heappush(queue, (next_cost, order, next_key))
    return Search(expanded=expanded)


def reconstruct(previous, origin, final):
    steps = []
    key = final
    while key != origin and key in previous:
        parent, macro, player, frames = previous[key]
        steps.append((macro, player, frames))
        key = parent
    steps.reverse()
    return steps


def reached_goal(player):
    return player.won


def standing_on(grid, row, columns):
    """Predicate: grounded with the hitbox over the given surface tiles."""
    def predicate(player):
        if not player.grounded or player.dead:
            return False
        if int((player.y + HITBOX) // TILE) != row:
            return False
        left = int(player.x // TILE)
        right = int((player.x + HITBOX - 1) // TILE)
        return any(col in columns for col in range(left, right + 1))
    return predicate


def enumerate_macros():
    for direction in (1, -1):
        for frames in WALK_FRAMES:
            yield Macro("walk", direction=direction, frames=frames)
        yield Macro("walk-to-edge", direction=direction)
    for dash_dir in DASH_DIRS:
        yield Macro("ground-dash", dash_dir=dash_dir)
    for direction in (1, -1):
        for kind, pre_runs in (("edge-jump", (0,)), ("jump", PRE_RUN_FRAMES)):
            for pre_run in pre_runs:
                yield Macro(kind, direction=direction, pre_run=pre_run)
                for delay in DASH_DELAYS:
                    for dash_dir in AIR_DASH_DIRS:
                        yield Macro(
                            kind, direction=direction, pre_run=pre_run,
                            dash_delay=delay, dash_dir=dash_dir,
                        )


def place_on(grid, col, row):
    """A settled standing state on top of the solid tile (col, row)."""
    player = Player(x=col * TILE + 1.0, y=row * TILE - HITBOX - 1.0)
    for _ in range(30):
        step(grid, player, Inputs())
        if player.grounded and abs(player.vy) < 1e-6:
            break
    if player.dead or not player.grounded:
        return None
    return player


@dataclass
class Crossing:
    macro: Macro
    end: Player
    direction: str
    takeoff: tuple
    landing: tuple


def cross_gap(grid, gap, allow_dash):
    """Try to cross a forced gap with one macro, in either direction.

    Start states are the far end and the near edge of the takeoff surface, so a
    full run-up is available.
    """
    row, left, right = gap[0], gap[1], gap[2]
    for takeoff_col, landing_col, label in (
        (left, right, "rightward"), (right, left, "leftward"),
    ):
        takeoff = surface_containing(grid, takeoff_col, row)
        landing = surface_containing(grid, landing_col, row)
        if not takeoff or not landing:
            continue
        accept = standing_on(grid, row, set(range(landing[1], landing[2] + 1)))
        starts = []
        for col in {takeoff[1], takeoff[2], takeoff_col}:
            placed = place_on(grid, col, row)
            if placed:
                starts.append(placed)
        for start in starts:
            for macro in enumerate_macros():
                if not allow_dash and (
                    macro.dash_dir != (0, 0) or macro.kind == "ground-dash"
                ):
                    continue
                result = run_macro(grid, start, macro, allow_dash=allow_dash)
                if result is None:
                    continue
                player = result[0]
                if accept(player):
                    return Crossing(macro, player, label, takeoff, landing)
    return None


def route_crosses_gap(grid, start, steps, gap):
    """True when one move takes the player from one side of the gap to the other."""
    row, left, right = gap[0], gap[1], gap[2]
    takeoff = surface_containing(grid, left, row)
    landing = surface_containing(grid, right, row)
    if not takeoff or not landing:
        return False

    def side(player):
        col = int((player.x + HITBOX / 2) // TILE)
        if takeoff[1] <= col <= takeoff[2]:
            return "takeoff"
        if landing[1] <= col <= landing[2]:
            return "landing"
        return None

    states = [start] + [player for _, player, _ in steps]
    for before, after in zip(states, states[1:]):
        first, second = side(before), side(after)
        if first and second and first != second:
            return True
    return False


def surface_at(grid, player):
    col = int((player.x + HITBOX / 2) // TILE)
    row = int((player.y + HITBOX) // TILE)
    for surface_row, left, right in landing_surfaces(grid):
        if surface_row == row and left <= col <= right:
            return f"surface row {surface_row} cols {left}-{right}"
    return f"tile ({col},{row})"


def describe_route(grid, steps):
    lines = []
    total = 0
    for index, (macro, player, frames) in enumerate(steps, start=1):
        total += frames
        where = "goal" if player.won else surface_at(grid, player)
        berries = bin(player.berries).count("1")
        lines.append(
            f" {index:2d}. {macro.describe():<58} -> "
            f"({player.x:.1f},{player.y:.1f}) {where}  [{frames}f, berries {berries}]"
        )
    lines.append(f"     total {total} updates")
    return lines


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------


def verdict(search):
    """An exhausted search proves nothing, so it must not read as a violation."""
    return "warn" if search.exhausted else "FAIL"


def budget_note(search):
    if not search.exhausted:
        return ""
    return (f" (inconclusive: search budget of {search.expanded - 1} states ran out; "
            f"raise --max-nodes)")


def report(grid, do_solve, max_nodes, out=sys.stdout):
    print(f"GRID {grid.width}x{grid.height}"
          + (f"  (source: {grid.source})" if grid.source else ""), file=out)
    print(grid.render(), file=out)
    print(file=out)
    # Show how each character was read, so a cartridge whose legend differs from
    # the documented one is obvious rather than silently misinterpreted.
    print("LEGEND READ AS", file=out)
    for label, chars in (
        ("solid", SOLID_CHARS), ("spike", SPIKE_CHARS), ("spawn", SPAWN_CHARS),
        ("berry", BERRY_CHARS), ("goal", GOAL_CHARS), ("empty", EMPTY_CHARS),
    ):
        counts = {
            char: sum(line.count(char) for line in grid.rows)
            for char in sorted(chars)
        }
        present = {char: n for char, n in counts.items() if n}
        if present:
            print(f" {label:6} " + ", ".join(f"'{c}' x{n}" for c, n in present.items()),
                  file=out)
    print(file=out)

    checks = static_checks(grid)
    print("CONTRACT", file=out)
    failures = 0
    for check in checks:
        if check.ok:
            status = "ok  "
        elif check.required:
            status = "FAIL"
            failures += 1
        else:
            status = "warn"
        print(f" {status}  {check.name}: {check.detail}", file=out)

    if not do_solve:
        print(file=out)
        print(f"VERDICT: {failures} required check(s) failed "
              f"(add --solve to test reachability)", file=out)
        return 1 if failures else 0

    gaps = [gap for gap in forced_gaps(grid) if gap[3] >= 2]
    demo_berry_ok = False
    print(file=out)
    print("FORCED GAP", file=out)
    crossable = []
    for gap in gaps:
        row, left, right = gap[0], gap[1], gap[2]
        label = f"row {row} cols {left}<->{right}"
        with_dash = cross_gap(grid, gap, allow_dash=True)
        without_dash = cross_gap(grid, gap, allow_dash=False)
        if not with_dash:
            print(f" FAIL  {label}: cannot be crossed even with a dash", file=out)
            failures += 1
            continue
        print(f" ok    {label}: crossed {with_dash.direction} with "
              f"\"{with_dash.macro.describe()}\"", file=out)
        if without_dash:
            print(f" FAIL  {label}: also crossable without a dash "
                  f"(\"{without_dash.macro.describe()}\"), so the dash is not required",
                  file=out)
            failures += 1
        else:
            print(f" ok    {label}: impossible without a dash", file=out)
            crossable.append((gap, with_dash))

    print(file=out)
    if not grid.spawns or not grid.goals:
        print("ROUTE  skipped: grid needs exactly one spawn and one goal", file=out)
        return 1

    start = spawn_player(grid)
    print("ROUTE  fastest spawn -> goal", file=out)
    search = bfs(grid, start, reached_goal, max_nodes=max_nodes)
    if not search.found:
        print(f" {verdict(search)}  goal unreachable after {search.expanded} states"
              f"{budget_note(search)}", file=out)
        failures += 0 if search.exhausted else 1
    else:
        for line in describe_route(grid, search.steps):
            print(line, file=out)
        jumps = sum(1 for macro, _, _ in search.steps
                    if macro.kind in ("jump", "edge-jump"))
        print(f" ok    reachable in {len(search.steps)} move(s), "
              f"{jumps} grounded-initiated jump(s)", file=out)
        bypassed = [
            gap for gap, _ in crossable
            if not route_crosses_gap(grid, start, search.steps, gap)
        ]
        if crossable and len(bypassed) == len(crossable):
            print(" warn  the fastest route skips the forced gap (an upward dash "
                  "climbs past it); add a ceiling if the climax must be unavoidable",
                  file=out)

    for gap, crossing in crossable:
        print(file=out)
        print(f"INTENDED ROUTE  through the row {gap[0]} gap "
              f"({crossing.direction})", file=out)
        takeoff_columns = set(range(crossing.takeoff[1], crossing.takeoff[2] + 1))
        landing_columns = set(range(crossing.landing[1], crossing.landing[2] + 1))
        approach_leg = bfs(
            grid, start, standing_on(grid, gap[0], takeoff_columns),
            max_nodes=max_nodes,
        )
        if not approach_leg.found:
            print(f" {verdict(approach_leg)}  the takeoff surface is not reachable "
                  f"from spawn{budget_note(approach_leg)}", file=out)
            failures += 0 if approach_leg.exhausted else 1
            continue
        state = approach_leg.steps[-1][1] if approach_leg.steps else start
        crossing_leg = bfs(
            grid, state, standing_on(grid, gap[0], landing_columns), max_nodes=1,
        )
        if not crossing_leg.found:
            print(" FAIL  the gap cannot be crossed from where the approach "
                  "leaves the player", file=out)
            failures += 1
            continue
        after = crossing_leg.steps[-1][1]
        finish = bfs(grid, after, reached_goal, max_nodes=max_nodes)
        if not finish.found:
            print(f" {verdict(finish)}  the goal is not reachable after landing"
                  f"{budget_note(finish)}", file=out)
            failures += 0 if finish.exhausted else 1
            continue
        legs = approach_leg.steps + crossing_leg.steps + finish.steps
        for line in describe_route(grid, legs):
            print(line, file=out)
        jumps = sum(1 for macro, _, _ in legs if macro.kind in ("jump", "edge-jump"))
        landings = len(legs) - 1
        berries = bin(legs[-1][1].berries).count("1")
        demo_berry_ok = demo_berry_ok or berries == 1
        print(f" {'ok  ' if jumps >= 3 else 'FAIL'}  {jumps} grounded-initiated "
              f"jump(s) (need >=3), {landings} intermediate landing(s), "
              f"{berries} strawberr{'y' if berries == 1 else 'ies'}", file=out)
        if jumps < 3:
            failures += 1
        updates = sum(frames for _, _, frames in legs)
        print(f" {'ok  ' if updates <= 2700 else 'FAIL'}  {updates} updates "
              f"(demo budget 2700)", file=out)
        if updates > 2700:
            failures += 1

    if grid.berries and not demo_berry_ok:
        print(file=out)
        print("DEMO    route collecting exactly 1 strawberry", file=out)
        single = bfs(
            grid, start,
            lambda p: p.won and bin(p.berries).count("1") == 1,
            max_nodes=max_nodes,
        )
        if single.found:
            print(f" ok    exists in {len(single.steps)} move(s), "
                  f"{sum(f for _, _, f in single.steps)} updates", file=out)
        else:
            print(f" {verdict(single)}  no route wins with exactly 1 strawberry"
                  f"{budget_note(single)}", file=out)
            failures += 0 if single.exhausted else 1

    print(file=out)
    print(f"VERDICT: {failures} required check(s) failed", file=out)
    return 1 if failures else 0


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Check a 16x16 Celeste-like level grid against the level contract "
                    "and the supplied movement constants.",
    )
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--grid", help="text file holding the 16x16 grid")
    source.add_argument("--from-cart", help=".p8 cartridge holding the grid "
                                            "(comment block or Lua string table)")
    parser.add_argument("--spawn", metavar="COL,ROW",
                        help="spawn tile, when the cartridge sets it in Lua "
                             "instead of marking it in the grid")
    parser.add_argument("--solve", action="store_true",
                        help="also search for a route from spawn to goal")
    parser.add_argument("--max-nodes", type=int, default=20000,
                        help="search budget in expanded states (default 20000)")
    args = parser.parse_args(argv)

    try:
        grid = load_grid(args.grid or args.from_cart)
        if args.spawn:
            col, _, row = args.spawn.partition(",")
            grid.spawns = [(int(col), int(row))]
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return report(grid, args.solve, args.max_nodes)


if __name__ == "__main__":
    sys.exit(main())
