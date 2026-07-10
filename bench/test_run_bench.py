import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from bench import run_bench


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


if __name__ == "__main__":
    unittest.main()
