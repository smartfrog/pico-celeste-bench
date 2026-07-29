import io
import tempfile
import unittest
from pathlib import Path

from bench import route_check as rc


def build(**rows):
    """Build a 16x16 grid from `r13="####..."` style keyword arguments."""
    lines = ["." * rc.GRID_W for _ in range(rc.GRID_H)]
    for name, value in rows.items():
        index = int(name[1:])
        lines[index] = value.ljust(rc.GRID_W, ".")[:rc.GRID_W]
    return rc.Grid(lines)


def check(grid, name):
    for entry in rc.static_checks(grid):
        if entry.name == name:
            return entry
    raise AssertionError(f"no check named {name}")


def crossable(gap_columns, drop=0, up=0, allow_dash=False):
    """Can the player get from a left platform to a right one across a gap?"""
    left_row = 13
    right_row = 13 - up + drop
    lines = ["." * rc.GRID_W for _ in range(rc.GRID_H)]

    def paint(row, columns, char):
        line = list(lines[row])
        for col in columns:
            if col < rc.GRID_W:
                line[col] = char
        lines[row] = "".join(line)

    first_right = 4 + gap_columns
    paint(left_row, range(0, 4), "#")
    paint(right_row, range(first_right, first_right + 5), "#")
    paint(left_row - 1, [0], "s")
    grid = rc.Grid(lines)
    start = rc.spawn_player(grid)
    first_right = 4 + gap_columns
    for macro in rc.enumerate_macros():
        uses_dash = macro.dash_dir != (0, 0) or macro.kind == "ground-dash"
        if uses_dash and not allow_dash:
            continue
        result = rc.run_macro(grid, start, macro, allow_dash=allow_dash)
        if result is None:
            continue
        player = result[0]
        on_right = player.x + rc.HITBOX - 1 >= first_right * rc.TILE
        landed = int((player.y + rc.HITBOX) // rc.TILE) == right_row
        if player.grounded and on_right and landed:
            return macro
    return None


class GridParsingTests(unittest.TestCase):
    def test_reads_a_plain_grid_file(self):
        text = "\n".join(["." * 16] * 16)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "grid.txt"
            path.write_text(text)

            grid = rc.load_grid(path)

        self.assertEqual(grid.height, 16)
        self.assertEqual(grid.width, 16)

    def test_reads_a_grid_from_a_lua_string_table(self):
        rows = ["." * 16] * 15 + ["s..............g"]
        cart = "map_src={\n" + "".join(f' "{row}",\n' for row in rows) + "}\n"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cart.p8"
            path.write_text("pico-8 cartridge\nversion 8\n__lua__\n" + cart)

            grid = rc.load_grid(path)

        self.assertEqual(grid.spawns, [(0, 15)])
        self.assertEqual(grid.goals, [(15, 15)])

    def test_reads_a_grid_from_a_comment_block(self):
        rows = ["." * 16] * 15 + ["s..............g"]
        cart = "".join(f"-- {row}\n" for row in rows)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cart.p8"
            path.write_text(cart)

            grid = rc.load_grid(path)

        self.assertEqual(grid.spawns, [(0, 15)])

    def test_rejects_a_seventeen_row_block_instead_of_guessing(self):
        rows = ["#" * 16] + ["." * 16] * 15 + ["s..............g"]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cart.p8"
            path.write_text("".join(f"-- {row}\n" for row in rows))

            with self.assertRaises(ValueError) as caught:
                rc.load_grid(path)

        self.assertIn("17 consecutive", str(caught.exception))

    def test_rejects_a_file_without_a_grid(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "cart.p8"
            path.write_text("function _update() end\n")

            with self.assertRaises(ValueError):
                rc.load_grid(path)


class StaticCheckTests(unittest.TestCase):
    def test_flags_a_short_row(self):
        grid = rc.Grid(["." * 16] * 15 + ["." * 10])

        self.assertFalse(check(grid, "grid shape").ok)

    def test_flags_terrain_in_the_title_zone(self):
        grid = build(r0="....##..........")

        self.assertFalse(check(grid, "title zone").ok)

    def test_accepts_background_in_the_title_zone(self):
        grid = build(r0="....--..........")

        self.assertTrue(check(grid, "title zone").ok)

    def test_counts_surfaces_and_height_bands(self):
        grid = build(r13="####...#####....", r11="......####",
                     r9="............####")

        entry = check(grid, "landing surfaces")

        self.assertTrue(entry.ok)
        self.assertIn("3 height bands", entry.detail)

    def test_requires_four_surfaces_in_three_bands(self):
        grid = build(r13="####", r11="......####")

        self.assertFalse(check(grid, "landing surfaces").ok)

    def test_finds_a_gap_of_exactly_four_columns(self):
        grid = build(r13="####....########")

        entry = check(grid, "forced gap")

        self.assertTrue(entry.ok)
        self.assertIn("takeoff col 3", entry.detail)

    def test_rejects_a_gap_of_three_columns(self):
        grid = build(r13="####...#########")

        self.assertFalse(check(grid, "forced gap").ok)

    def test_rejects_a_gap_of_five_columns(self):
        grid = build(r13="####.....#######")

        self.assertFalse(check(grid, "forced gap").ok)

    def test_rejects_a_gap_between_different_heights(self):
        grid = build(r13="####", r12="........########")

        self.assertFalse(check(grid, "forced gap").ok)

    def test_rejects_a_gap_without_headroom(self):
        grid = build(r13="####....########", r12="###############.",
                     r11="################")

        self.assertFalse(check(grid, "forced gap").ok)

    def test_flags_a_surface_that_cannot_be_jumped_from(self):
        grid = build(r11="####", r13="####")

        entry = check(grid, "headroom above surfaces")

        self.assertFalse(entry.ok)
        self.assertIn("row 13", entry.detail)

    def test_a_partly_covered_surface_still_allows_a_jump(self):
        grid = build(r11="######..........", r13="########........")

        headroom = check(grid, "headroom above surfaces")
        overhang = check(grid, "surfaces under an overhang")

        self.assertTrue(headroom.ok)
        self.assertFalse(overhang.ok)
        self.assertFalse(overhang.required)
        self.assertIn("[0, 1, 2, 3, 4, 5]", overhang.detail)

    def test_an_open_surface_reports_no_overhang(self):
        grid = build(r13="########........")

        self.assertTrue(check(grid, "surfaces under an overhang").ok)

    def test_counts_separate_spike_groups(self):
        grid = build(r12="..^....^........", r13="################")

        entry = check(grid, "spike groups")

        self.assertTrue(entry.ok)
        self.assertIn("2 separate", entry.detail)

    def test_requires_two_spike_groups(self):
        grid = build(r12="..^^............", r13="################")

        self.assertFalse(check(grid, "spike groups").ok)

    def test_warns_about_floating_spikes(self):
        grid = build(r12="..^.............")

        entry = check(grid, "spikes rest on solids")

        self.assertFalse(entry.ok)
        self.assertFalse(entry.required)

    def test_counts_a_two_tile_flag_as_one_goal(self):
        grid = build(r11="..............g.", r12="..............g.",
                     r13="##############.#")

        self.assertTrue(check(grid, "goal").ok)

    def test_flags_two_separate_goals(self):
        grid = build(r12="..g........g....", r13="################")

        self.assertFalse(check(grid, "goal").ok)

    def test_missing_spawn_is_a_warning_not_a_failure(self):
        grid = build(r13="################")

        entry = check(grid, "spawn")

        self.assertFalse(entry.ok)
        self.assertFalse(entry.required)

    def test_flags_a_spawn_without_headroom(self):
        grid = build(r11="################", r12="s...............",
                     r13="################")

        self.assertFalse(check(grid, "spawn footing").ok)

    def test_flags_a_goal_close_to_spawn(self):
        grid = build(r12="s..g............", r13="################")

        self.assertFalse(check(grid, "goal placement").ok)

    def test_flags_a_berry_next_to_spawn(self):
        grid = build(r12="sb.............g", r13="################")

        self.assertFalse(check(grid, "berries away from spawn").ok)


class SpacingTests(unittest.TestCase):
    """The oracle must agree with the spacing table it is meant to replace."""

    def test_flat_jump_clears_two_columns(self):
        self.assertIsNotNone(crossable(2))

    def test_flat_jump_fails_at_four_columns(self):
        self.assertIsNone(crossable(4))

    def test_reach_exceeds_the_documented_table(self):
        # The prompt promises a 2-tile flat jump; the oracle allows 3, so every
        # spacing the table promises is safe.
        self.assertIsNotNone(crossable(3))

    def test_rising_jump_clears_one_up_one_across(self):
        self.assertIsNotNone(crossable(1, up=1))

    def test_rising_jump_fails_at_one_up_three_across(self):
        self.assertIsNone(crossable(3, up=1))

    def test_falling_jump_clears_three_columns(self):
        self.assertIsNotNone(crossable(3, drop=1))

    def test_falling_jump_fails_at_four_columns(self):
        self.assertIsNone(crossable(4, drop=1))

    def test_forced_gap_needs_a_dash(self):
        self.assertIsNone(crossable(4))
        self.assertIsNotNone(crossable(4, allow_dash=True))

    def test_six_columns_is_too_far_even_with_a_dash(self):
        self.assertIsNone(crossable(6, allow_dash=True))

    def test_reach_grows_monotonically_with_gap_size(self):
        reachable = [crossable(gap) is not None for gap in range(1, 5)]

        self.assertEqual(reachable, sorted(reachable, reverse=True))


class MovementTests(unittest.TestCase):
    def test_spawn_settles_on_the_floor(self):
        grid = build(r12="s...............", r13="################")

        player = rc.spawn_player(grid)

        self.assertTrue(player.grounded)
        self.assertTrue(player.can_dash)
        self.assertEqual(int((player.y + rc.HITBOX) // rc.TILE), 13)

    def test_falling_onto_spikes_kills(self):
        grid = build(r12="s.^.............", r13="################")
        player = rc.spawn_player(grid)

        result = rc.run_macro(grid, player, rc.Macro("walk", direction=1, frames=30))

        self.assertIsNone(result)

    def test_rising_through_spike_tips_does_not_kill(self):
        grid = build(r11="^...............", r12="s...............",
                     r13="################")
        player = rc.spawn_player(grid)
        player.y = 90.0
        player.vy = -2.0

        rc.step(grid, player, rc.Inputs())

        # The hitbox overlaps the spike tile while moving up.
        self.assertEqual(int(player.y // rc.TILE), 11)
        self.assertLess(player.vy, 0)
        self.assertFalse(player.dead)

    def test_falling_onto_the_same_spike_tips_kills(self):
        grid = build(r11="^...............", r12="s...............",
                     r13="################")
        player = rc.spawn_player(grid)
        player.y = 90.0
        player.vy = 1.0

        rc.step(grid, player, rc.Inputs())

        self.assertEqual(int(player.y // rc.TILE), 11)
        self.assertTrue(player.dead)

    def test_walking_over_a_berry_collects_it(self):
        grid = build(r12="sb..............", r13="################")
        player = rc.spawn_player(grid)

        result = rc.run_macro(grid, player, rc.Macro("walk", direction=1, frames=12))

        self.assertEqual(bin(result[0].berries).count("1"), 1)

    def test_touching_the_goal_wins(self):
        grid = build(r12="s..g............", r13="################")
        player = rc.spawn_player(grid)

        result = rc.run_macro(grid, player, rc.Macro("walk", direction=1, frames=30))

        self.assertTrue(result[2])

    def test_dash_recharges_only_on_the_ground(self):
        grid = build(r12="s...............", r13="################")
        player = rc.spawn_player(grid)

        rc.step(grid, player, rc.Inputs(dx=1, dash=True))

        self.assertFalse(player.can_dash)

    def test_falling_off_the_screen_kills(self):
        grid = build(r12="s...............", r13="#...............")
        player = rc.spawn_player(grid)

        result = rc.run_macro(grid, player, rc.Macro("walk", direction=1, frames=40))

        self.assertIsNone(result)

    def test_the_player_cannot_leave_the_screen_sideways(self):
        grid = build(r12="s...............", r13="################")
        player = rc.spawn_player(grid)

        result = rc.run_macro(grid, player, rc.Macro("walk", direction=-1, frames=20))

        self.assertGreaterEqual(result[0].x, 0)


class SolverTests(unittest.TestCase):
    def setUp(self):
        # Two equal-height ledges four columns apart: the minimal forced gap.
        self.grid = build(
            r12="s........g......",
            r13="####....########",
        )

    def test_the_gap_needs_a_dash(self):
        self.assertIsNone(rc.cross_gap(self.grid, (13, 3, 8, 9), allow_dash=False))
        self.assertIsNotNone(rc.cross_gap(self.grid, (13, 3, 8, 9), allow_dash=True))

    def test_the_crossing_reports_both_surfaces(self):
        crossing = rc.cross_gap(self.grid, (13, 3, 8, 9), allow_dash=True)

        self.assertEqual(crossing.direction, "rightward")
        self.assertEqual(crossing.takeoff, (13, 0, 3))
        self.assertEqual(crossing.landing, (13, 8, 15))

    def test_the_goal_is_reachable(self):
        search = rc.bfs(self.grid, rc.spawn_player(self.grid), rc.reached_goal)

        self.assertTrue(search.found)

    def test_the_goal_is_unreachable_without_a_dash(self):
        search = rc.bfs(
            self.grid, rc.spawn_player(self.grid), rc.reached_goal, allow_dash=False,
        )

        self.assertFalse(search.found)

    def test_the_route_is_reported_as_crossing_the_gap(self):
        start = rc.spawn_player(self.grid)
        search = rc.bfs(self.grid, start, rc.reached_goal)

        self.assertTrue(
            rc.route_crosses_gap(self.grid, start, search.steps, (13, 3, 8, 9))
        )

    def test_a_route_that_stays_on_one_side_does_not_cross(self):
        start = rc.spawn_player(self.grid)
        search = rc.bfs(self.grid, start, rc.standing_on(self.grid, 13, {0, 1, 2, 3}))

        self.assertFalse(
            rc.route_crosses_gap(self.grid, start, search.steps, (13, 3, 8, 9))
        )

    def test_the_search_budget_is_honoured(self):
        search = rc.bfs(
            self.grid, rc.spawn_player(self.grid),
            lambda player: False, max_nodes=3,
        )

        self.assertTrue(search.exhausted)
        self.assertFalse(search.found)


class ReportTests(unittest.TestCase):
    def test_a_failing_grid_returns_nonzero(self):
        grid = build(r0="####", r13="####")
        out = io.StringIO()

        code = rc.report(grid, do_solve=False, max_nodes=100, out=out)

        self.assertEqual(code, 1)
        self.assertIn("FAIL", out.getvalue())

    def test_the_report_shows_the_grid_and_a_verdict(self):
        grid = build(r13="####....########", r12="s........g......")
        out = io.StringIO()

        rc.report(grid, do_solve=False, max_nodes=100, out=out)
        text = out.getvalue()

        self.assertIn("CONTRACT", text)
        self.assertIn("VERDICT", text)
        self.assertIn("s........g......", text)

    def test_solving_reports_the_forced_gap_and_a_route(self):
        grid = build(r13="####....########", r12="s........g......")
        out = io.StringIO()

        rc.report(grid, do_solve=True, max_nodes=400, out=out)
        text = out.getvalue()

        self.assertIn("FORCED GAP", text)
        self.assertIn("impossible without a dash", text)
        self.assertIn("ROUTE", text)


if __name__ == "__main__":
    unittest.main()
