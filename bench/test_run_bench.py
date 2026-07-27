import json
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from bench import run_bench


class ConfigTests(unittest.TestCase):
    def test_defaults_max_attempts_to_three(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "models.json"
            config_path.write_text(json.dumps({"models": [{"model": "test/model"}]}))

            config = run_bench.load_config(config_path)

        self.assertEqual(config["max_attempts"], 3)

    def test_reads_configured_max_attempts(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "models.json"
            config_path.write_text(json.dumps({
                "max_attempts": 10,
                "models": [{"model": "test/model"}],
            }))

            config = run_bench.load_config(config_path)

        self.assertEqual(config["max_attempts"], 10)

    def test_defaults_idle_timeout_to_ten_minutes(self):
        with tempfile.TemporaryDirectory() as directory:
            config_path = Path(directory) / "models.json"
            config_path.write_text(json.dumps({"models": [{"model": "test/model"}]}))

            config = run_bench.load_config(config_path)

        self.assertEqual(config["idle_timeout_seconds"], 600)


class PromptTests(unittest.TestCase):
    def test_includes_cart_name_and_exact_gif_name(self):
        prompt = run_bench.build_prompt(
            "prompts/celeste_like.md",
            "results/test.p8",
            "Test Cart",
            "test.gif",
        )

        self.assertIn('nom exact de la cartouche est "Test Cart"', prompt)
        self.assertIn('est "test.gif"', prompt)


class OpenCodeLaunchTests(unittest.TestCase):
    def test_passes_api_transport_configuration(self):
        result = SimpleNamespace(
            session_id="ses_test", error=None, wall_seconds=1.5,
            timed_out=False, returncode=0,
        )
        with tempfile.TemporaryDirectory() as directory:
            stream_path = Path(directory) / "stream.jsonl"
            with mock.patch.object(run_bench, "run_session", return_value=result) as run_session:
                actual = run_bench.run_opencode(
                    "test/model", None, "build", "prompt", 10,
                    stream_path, max_output_tokens=64000, show_live=False,
                    idle_timeout_s=45, session_id="ses_existing",
                )

        self.assertEqual(actual, ("ses_test", None, 1.5, False, 0))
        self.assertEqual(run_session.call_args.kwargs["directory"], run_bench.REPO_ROOT)
        self.assertEqual(run_session.call_args.kwargs["max_output_tokens"], 64000)
        self.assertEqual(run_session.call_args.kwargs["idle_timeout_s"], 45)
        self.assertEqual(run_session.call_args.kwargs["session_id"], "ses_existing")

    def test_main_uses_per_model_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bench").mkdir()
            (root / "prompts").mkdir()
            (root / "results").mkdir()
            (root / "prompts" / "task.md").write_text("task")
            config_path = root / "bench" / "models.json"
            config_path.write_text(json.dumps({
                "prompt_file": "prompts/task.md",
                "models": [{
                    "model": "test/model",
                    "out": "test",
                    "max_output_tokens": 1234,
                }],
            }))
            argv = ["run_bench.py", "--config", str(config_path), "--quiet"]

            with mock.patch.object(run_bench, "REPO_ROOT", root):
                with mock.patch.object(sys, "argv", argv):
                    with mock.patch.object(
                        run_bench,
                        "run_opencode",
                        return_value=(None, "provider failed", 1.0, False, 1),
                    ) as launch:
                        result = run_bench.main()

        self.assertEqual(result, 0)
        self.assertEqual(launch.call_args.kwargs["max_output_tokens"], 1234)


class LiveEventTests(unittest.TestCase):
    def test_formats_reasoning_event(self):
        rendered = run_bench.format_live_event({
            "type": "reasoning",
            "part": {"text": "I should build the level now."},
        })
        self.assertEqual(rendered, "[thinking] I should build the level now.")


class ExistingResultTests(unittest.TestCase):
    def test_main_skips_existing_cart_and_reuses_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bench").mkdir()
            (root / "prompts").mkdir()
            (root / "results").mkdir()
            (root / "prompts" / "task.md").write_text("task")
            config_path = root / "bench" / "models.json"
            config_path.write_text(json.dumps({
                "prompt_file": "prompts/task.md",
                "models": [{"model": "test/model", "out": "existing"}],
            }))
            cart_path = root / "results" / "existing.p8"
            cart_path.write_text("preserve me")
            metrics = {
                "out": "existing",
                "model": "test/model",
                "variant": None,
                "booted_clean": True,
                "demo_gif_written": True,
            }
            (root / "results" / "existing.metrics.json").write_text(json.dumps(metrics))

            argv = ["run_bench.py", "--config", str(config_path), "--quiet"]
            with mock.patch.object(run_bench, "REPO_ROOT", root):
                with mock.patch.object(sys, "argv", argv):
                    with mock.patch.object(run_bench, "run_opencode") as run_opencode:
                        result = run_bench.main()

            self.assertEqual(result, 0)
            run_opencode.assert_not_called()
            self.assertEqual(cart_path.read_text(), "preserve me")
            metrics_csv = (root / "results" / "metrics.csv").read_text()
            self.assertIn("existing", metrics_csv)


class ResumeTests(unittest.TestCase):
    def test_partial_metrics_round_trip_is_atomic(self):
        with tempfile.TemporaryDirectory() as directory:
            metrics_path = Path(directory) / "model.metrics.json"
            metrics = {"status": "running", "session_id": "ses_test"}

            run_bench.write_json_atomic(metrics_path, metrics)

            self.assertEqual(run_bench.load_metrics(metrics_path), metrics)
            self.assertFalse((Path(directory) / "model.metrics.json.tmp").exists())

    def test_metrics_complete_requires_all_artifacts(self):
        self.assertFalse(run_bench.metrics_complete({
            "cartridge_written": True,
            "booted_clean": True,
            "demo_gif_written": False,
        }))
        self.assertTrue(run_bench.metrics_complete({
            "cartridge_written": True,
            "booted_clean": True,
            "demo_gif_written": True,
        }))

    def test_main_resumes_session_from_partial_metrics(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bench").mkdir()
            (root / "prompts").mkdir()
            (root / "results").mkdir()
            (root / "prompts" / "task.md").write_text("task")
            config_path = root / "bench" / "models.json"
            config_path.write_text(json.dumps({
                "prompt_file": "prompts/task.md",
                "models": [{"model": "test/model", "out": "partial"}],
            }))
            metrics_path = root / "results" / "partial.metrics.json"
            metrics_path.write_text(json.dumps({
                "status": "running",
                "session_id": "ses_existing",
                "attempt": 1,
                "wall_seconds": 5.0,
                "cartridge_written": False,
                "booted_clean": False,
                "demo_gif_written": False,
            }))

            argv = ["run_bench.py", "--config", str(config_path), "--quiet"]

            def fake_launch(*args, **kwargs):
                Path(args[5]).write_text("")
                return "ses_existing", None, 1.0, False, 0

            with mock.patch.object(run_bench, "REPO_ROOT", root):
                with mock.patch.object(sys, "argv", argv):
                    with mock.patch.object(sys.stdin, "isatty", return_value=True):
                        with mock.patch("builtins.input", side_effect=["r", "s"]):
                            with mock.patch.object(
                                run_bench, "run_opencode",
                                side_effect=fake_launch,
                            ) as launch:
                                with mock.patch.object(run_bench, "export_session", return_value=None):
                                    result = run_bench.main()

            self.assertEqual(result, 0)
            self.assertEqual(launch.call_args.kwargs["session_id"], "ses_existing")
            saved = json.loads(metrics_path.read_text())
            self.assertEqual(saved["status"], "incomplete")
            self.assertEqual(saved["wall_seconds"], 6.0)

    def test_new_session_choice_replaces_a_partial_cart(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bench").mkdir()
            (root / "prompts").mkdir()
            (root / "results").mkdir()
            (root / "prompts" / "task.md").write_text("task")
            config_path = root / "bench" / "models.json"
            config_path.write_text(json.dumps({
                "prompt_file": "prompts/task.md",
                "models": [{"model": "test/model", "out": "partial"}],
            }))
            cart_path = root / "results" / "partial.p8"
            cart_path.write_text("stale partial cart")
            (root / "results" / "partial.metrics.json").write_text(json.dumps({
                "status": "running",
                "session_id": "ses_old",
                "attempt": 1,
                "cartridge_written": True,
                "booted_clean": False,
                "demo_gif_written": False,
            }))

            def fake_launch(*args, **kwargs):
                self.assertFalse(cart_path.exists())
                Path(args[5]).write_text("")
                return "ses_new", "provider failed", 1.0, False, 1

            argv = ["run_bench.py", "--config", str(config_path), "--quiet"]
            with mock.patch.object(run_bench, "REPO_ROOT", root):
                with mock.patch.object(sys, "argv", argv):
                    with mock.patch.object(sys.stdin, "isatty", return_value=True):
                        with mock.patch("builtins.input", side_effect=["n", "s"]):
                            with mock.patch.object(run_bench, "run_opencode", side_effect=fake_launch) as launch:
                                with mock.patch.object(run_bench, "export_session", return_value=None):
                                    result = run_bench.main()

            self.assertEqual(result, 0)
            launch.assert_called_once()
            self.assertIsNone(launch.call_args.kwargs["session_id"])

    def test_task_incomplete_reason(self):
        self.assertEqual(
            run_bench.task_incomplete_reason(False, False, False),
            "no cartridge written",
        )
        self.assertEqual(
            run_bench.task_incomplete_reason(True, False, False),
            "cartridge does not boot cleanly",
        )
        self.assertEqual(
            run_bench.task_incomplete_reason(True, True, False),
            "demo GIF not written",
        )
        self.assertIsNone(run_bench.task_incomplete_reason(True, True, True))

    def test_resume_prompt_for_no_cart(self):
        msg = run_bench.build_resume_prompt("error", False, None, False)
        self.assertIn("Aucune cartouche", msg)

    def test_resume_prompt_for_bad_boot(self):
        msg = run_bench.build_resume_prompt("error", True, False, False)
        self.assertIn("demarre pas", msg)

    def test_resume_prompt_for_no_gif(self):
        msg = run_bench.build_resume_prompt("error", True, True, False)
        self.assertIn("autoplay", msg)

    def test_is_resumable_rejects_billing_errors(self):
        self.assertFalse(run_bench.is_resumable("prepaid_credit_exhausted"))
        self.assertFalse(run_bench.is_resumable("401 Unauthorized"))
        self.assertFalse(run_bench.is_resumable("API key invalid"))

    def test_is_resumable_accepts_unknown_and_length(self):
        self.assertTrue(run_bench.is_resumable("empty response (reason: unknown)"))
        self.assertTrue(run_bench.is_resumable("output length limit reached"))
        self.assertTrue(run_bench.is_resumable("timeout after 3600s"))

class DemoCaptureTests(unittest.TestCase):
    def test_accepts_fresh_nonempty_gif_and_stops_pico8(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cart_path = root / "test.p8"
            gif_path = root / "test.gif"
            cart_path.write_text("cart")
            gif_path.write_text("stale")

            class FakeProcess:
                def __init__(self, command):
                    self.terminated = False
                    home = Path(command[command.index("-home") + 1])
                    self.recorded_gif = home / "carts" / gif_path.name

                def poll(self):
                    if not self.recorded_gif.exists():
                        self.recorded_gif.parent.mkdir(parents=True)
                        self.recorded_gif.write_bytes(b"GIF89a")
                    return None

                def terminate(self):
                    self.terminated = True

                def wait(self, timeout=None):
                    return 0

            processes = []

            def fake_popen(command, **kwargs):
                process = FakeProcess(command)
                processes.append(process)
                return process

            with mock.patch.object(run_bench.subprocess, "Popen", side_effect=fake_popen):
                with mock.patch.object(run_bench.time, "sleep"):
                    result = run_bench.capture_demo(cart_path, gif_path, timeout_s=1)

            self.assertTrue(result)
            self.assertEqual(gif_path.read_bytes(), b"GIF89a")
            self.assertTrue(processes[0].terminated)

    def test_returns_false_when_pico8_cannot_start(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cart_path = root / "test.p8"
            gif_path = root / "test.gif"
            cart_path.write_text("cart")

            with mock.patch.object(
                run_bench.subprocess,
                "Popen",
                side_effect=PermissionError("not executable"),
            ):
                result = run_bench.capture_demo(cart_path, gif_path, timeout_s=1)

            self.assertFalse(result)
            self.assertFalse(gif_path.exists())


class ExportSessionTests(unittest.TestCase):
    def test_writes_export_directly_to_file(self):
        export_data = {"info": {"tokens": {"input": 12}}, "messages": []}

        def fake_run(command, **kwargs):
            self.assertNotEqual(kwargs["stdout"], subprocess.PIPE)
            json.dump(export_data, kwargs["stdout"])
            kwargs["stdout"].flush()
            return SimpleNamespace(returncode=0, stderr="")

        with tempfile.TemporaryDirectory() as directory:
            export_path = Path(directory) / "session.export.json"
            with mock.patch.object(run_bench.subprocess, "run", side_effect=fake_run):
                result = run_bench.export_session("ses_test", export_path)

            self.assertEqual(result, export_data)
            self.assertEqual(json.loads(export_path.read_text()), export_data)


class StreamMetricsTests(unittest.TestCase):
    def test_extracts_complete_metrics_from_jsonl_events(self):
        events = [
            {"type": "step_start", "timestamp": 1_000},
            {
                "type": "tool_use",
                "timestamp": 1_100,
                "part": {"tool": "read"},
            },
            {
                "type": "step_finish",
                "timestamp": 2_000,
                "part": {
                    "tokens": {
                        "input": 10,
                        "output": 4,
                        "reasoning": 2,
                        "cache": {"read": 8, "write": 1},
                    },
                    "cost": 0.25,
                },
            },
            {
                "type": "tool_use",
                "timestamp": 2_100,
                "part": {"tool": "read"},
            },
            {
                "type": "tool_use",
                "timestamp": 2_200,
                "part": {"tool": "bash"},
            },
            {
                "type": "step_finish",
                "timestamp": 4_000,
                "part": {
                    "tokens": {
                        "input": 7,
                        "output": 3,
                        "reasoning": 1,
                        "cache": {"read": 6, "write": 0},
                    },
                    "cost": 0.5,
                },
            },
        ]

        with tempfile.TemporaryDirectory() as directory:
            stream_path = Path(directory) / "session.stream.jsonl"
            stream_path.write_text("\n".join(json.dumps(event) for event in events))
            metrics = run_bench.extract_stream_metrics(stream_path)

        self.assertEqual(metrics, {
            "tokens_input": 17,
            "tokens_output": 7,
            "tokens_reasoning": 3,
            "cache_read": 14,
            "cache_write": 1,
            "tokens_total": 27,
            "cost": 0.75,
            "session_seconds": 3.0,
            "assistant_messages": 2,
            "tool_calls_total": 3,
            "tool_calls_by_name": {"read": 2, "bash": 1},
        })

    def test_extracts_metrics_from_native_sse_events_without_double_counting_tools(self):
        tool = {
            "id": "prt_tool",
            "type": "tool",
            "tool": "read",
            "state": {"status": "completed"},
        }
        events = [
            {"type": "message.part.updated", "timestamp": 1_000,
             "properties": {"part": tool}},
            {"type": "message.part.updated", "timestamp": 1_100,
             "properties": {"part": tool}},
            {
                "type": "message.part.updated",
                "timestamp": 2_000,
                "properties": {"part": {
                    "id": "prt_finish",
                    "type": "step-finish",
                    "tokens": {
                        "input": 12,
                        "output": 5,
                        "reasoning": 3,
                        "cache": {"read": 7, "write": 2},
                    },
                    "cost": 0.4,
                }},
            },
        ]

        with tempfile.TemporaryDirectory() as directory:
            stream_path = Path(directory) / "session.stream.jsonl"
            stream_path.write_text("\n".join(json.dumps(event) for event in events))
            metrics = run_bench.extract_stream_metrics(stream_path)

        self.assertEqual(metrics["tokens_total"], 20)
        self.assertEqual(metrics["cache_read"], 7)
        self.assertEqual(metrics["cost"], 0.4)
        self.assertEqual(metrics["assistant_messages"], 1)
        self.assertEqual(metrics["tool_calls_total"], 1)
        self.assertEqual(metrics["tool_calls_by_name"], {"read": 1})

    def test_combines_fallback_metrics_from_all_resume_attempts(self):
        def attempt(tokens, tool):
            return [
                {"type": "tool_use", "timestamp": 1_000,
                 "part": {"tool": tool}},
                {"type": "step_finish", "timestamp": 2_000, "part": {
                    "tokens": {"input": tokens, "output": 1, "reasoning": 0,
                               "cache": {"read": 0, "write": 0}},
                    "cost": 0.1,
                }},
            ]

        with tempfile.TemporaryDirectory() as directory:
            paths = [Path(directory) / "attempt-1.jsonl", Path(directory) / "attempt-2.jsonl"]
            paths[0].write_text("\n".join(json.dumps(event) for event in attempt(3, "read")))
            paths[1].write_text("\n".join(json.dumps(event) for event in attempt(5, "bash")))

            metrics = run_bench.extract_stream_metrics_many(paths)

        self.assertEqual(metrics["tokens_input"], 8)
        self.assertEqual(metrics["tokens_total"], 10)
        self.assertEqual(metrics["cost"], 0.2)
        self.assertEqual(metrics["assistant_messages"], 2)
        self.assertEqual(metrics["tool_calls_by_name"], {"read": 1, "bash": 1})


if __name__ == "__main__":
    unittest.main()
