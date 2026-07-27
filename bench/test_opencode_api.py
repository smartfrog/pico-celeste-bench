import io
import json
import queue
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from bench.opencode_api import DeltaRenderer, RunMonitor, iter_sse_events, run_session


class SSEParserTests(unittest.TestCase):
    def test_parses_fragmented_sse_data_events_and_ignores_comments(self):
        event = {
            "type": "message.part.delta",
            "properties": {
                "sessionID": "ses_test",
                "partID": "prt_test",
                "field": "text",
                "delta": "hello",
            },
        }
        lines = [
            b": keepalive\n",
            f"data: {json.dumps(event)}\n".encode(),
            b"\n",
        ]

        self.assertEqual(list(iter_sse_events(lines)), [event])

    def test_joins_multiple_data_lines(self):
        lines = [b'data: {"type":"server.heartbeat",\n', b'data: "properties":{}}\n', b"\n"]

        self.assertEqual(
            list(iter_sse_events(lines)),
            [{"type": "server.heartbeat", "properties": {}}],
        )


class RunMonitorTests(unittest.TestCase):
    def test_heartbeat_keeps_transport_alive_without_counting_as_model_progress(self):
        monitor = RunMonitor("ses_root")

        result = monitor.handle({"type": "server.heartbeat", "properties": {}})

        self.assertTrue(result.heartbeat)
        self.assertFalse(result.progress)
        self.assertFalse(result.done)

    def test_tracks_streaming_delta_until_root_session_becomes_idle(self):
        monitor = RunMonitor("ses_root")
        busy = monitor.handle({
            "type": "session.status",
            "properties": {"sessionID": "ses_root", "status": {"type": "busy"}},
        })
        delta = monitor.handle({
            "type": "message.part.delta",
            "properties": {
                "sessionID": "ses_root",
                "partID": "prt_reasoning",
                "field": "text",
                "delta": "working",
            },
        })
        idle = monitor.handle({
            "type": "session.status",
            "properties": {"sessionID": "ses_root", "status": {"type": "idle"}},
        })

        self.assertTrue(busy.progress)
        self.assertTrue(delta.progress)
        self.assertFalse(delta.action)
        self.assertFalse(delta.done)
        self.assertTrue(idle.done)

    def test_tool_update_counts_as_a_concrete_action(self):
        monitor = RunMonitor("ses_root")

        result = monitor.handle({
            "type": "message.part.updated",
            "properties": {"part": {
                "id": "prt_tool", "sessionID": "ses_root", "type": "tool",
                "tool": "apply_patch", "state": {"status": "running"},
            }},
        })

        self.assertTrue(result.progress)
        self.assertTrue(result.action)

    def test_ignores_idle_event_until_session_has_started(self):
        monitor = RunMonitor("ses_root")

        result = monitor.handle({
            "type": "session.status",
            "properties": {"sessionID": "ses_root", "status": {"type": "idle"}},
        })

        self.assertFalse(result.done)

    def test_counts_child_session_deltas_as_progress(self):
        monitor = RunMonitor("ses_root")
        monitor.handle({
            "type": "session.created",
            "properties": {"info": {"id": "ses_child", "parentID": "ses_root"}},
        })

        result = monitor.handle({
            "type": "message.part.delta",
            "properties": {
                "sessionID": "ses_child",
                "partID": "prt_child",
                "field": "text",
                "delta": "child progress",
            },
        })

        self.assertTrue(result.progress)

    def test_surfaces_session_error(self):
        monitor = RunMonitor("ses_root")

        result = monitor.handle({
            "type": "session.error",
            "properties": {
                "sessionID": "ses_root",
                "error": {"name": "APIError", "data": {"message": "provider failed"}},
            },
        })

        self.assertEqual(result.error, "provider failed")


class DeltaRendererTests(unittest.TestCase):
    def test_renders_reasoning_deltas_as_they_arrive(self):
        output = io.StringIO()
        renderer = DeltaRenderer(output)
        renderer.handle({
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "prt_reasoning",
                    "sessionID": "ses_root",
                    "type": "reasoning",
                    "text": "",
                    "time": {"start": 1},
                }
            },
        })
        renderer.handle({
            "type": "message.part.delta",
            "properties": {
                "sessionID": "ses_root",
                "partID": "prt_reasoning",
                "field": "text",
                "delta": "I am still working",
            },
        })
        renderer.handle({
            "type": "message.part.updated",
            "properties": {
                "part": {
                    "id": "prt_reasoning",
                    "sessionID": "ses_root",
                    "type": "reasoning",
                    "text": "I am still working",
                    "time": {"start": 1, "end": 2},
                }
            },
        })

        self.assertEqual(output.getvalue(), "[thinking] I am still working\n")


class RunSessionTests(unittest.TestCase):
    class FakeEventStream:
        def __init__(self, events):
            self.events = queue.Queue()
            for event in events:
                self.events.put(event)
            self.error = None
            self.closed = False

        def close(self):
            self.closed = True

    class FakeServer:
        def __init__(self, events, session_id="ses_created"):
            self.stream = RunSessionTests.FakeEventStream(events)
            self.session_id = session_id
            self.requests = []
            self.aborted = []

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, traceback):
            return None

        def subscribe(self):
            return self.stream

        def request(self, method, path, body=None, **kwargs):
            self.requests.append((method, path, body))
            if method == "POST" and path == "/session":
                return {"id": self.session_id}
            return None

        def abort(self, session_id):
            self.aborted.append(session_id)

    def test_runs_prompt_async_until_idle_and_records_native_events(self):
        events = [
            {"type": "session.status", "properties": {
                "sessionID": "ses_created", "status": {"type": "busy"},
            }},
            {"type": "message.part.delta", "properties": {
                "sessionID": "ses_created", "partID": "prt_1",
                "field": "text", "delta": "working",
            }},
            {"type": "message.part.updated", "properties": {"part": {
                "id": "prt_finish", "sessionID": "ses_created",
                "messageID": "msg_1", "type": "step-finish", "reason": "stop",
                "tokens": {}, "cost": 0,
            }}},
            {"type": "session.status", "properties": {
                "sessionID": "ses_created", "status": {"type": "idle"},
            }},
        ]
        server = self.FakeServer(events)
        callback = mock.Mock()
        with tempfile.TemporaryDirectory() as directory:
            stream_path = Path(directory) / "model.stream.jsonl"
            with mock.patch("bench.opencode_api.OpenCodeServer", return_value=server):
                result = run_session(
                    directory=directory, model="test/model", variant="high",
                    agent="build", prompt="do it", timeout_s=10,
                    idle_timeout_s=10, stream_path=stream_path,
                    max_output_tokens=1000, show_live=False,
                    event_callback=callback,
                )
            recorded = [json.loads(line) for line in stream_path.read_text().splitlines()]

        self.assertIsNone(result.error)
        self.assertEqual(result.session_id, "ses_created")
        self.assertEqual([event["type"] for event in recorded], [event["type"] for event in events])
        prompt_request = next(request for request in server.requests if "prompt_async" in request[1])
        self.assertEqual(prompt_request[2]["variant"], "high")
        self.assertEqual(prompt_request[2]["parts"], [{"type": "text", "text": "do it"}])
        self.assertTrue(callback.call_args_list[-1].args[2].done)
        self.assertTrue(server.stream.closed)

    def test_idle_timeout_aborts_remote_session(self):
        server = self.FakeServer([
            {"type": "session.status", "properties": {
                "sessionID": "ses_created", "status": {"type": "busy"},
            }},
            {"type": "server.heartbeat", "properties": {}},
        ])
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch("bench.opencode_api.OpenCodeServer", return_value=server):
                result = run_session(
                    directory=directory, model="test/model", variant=None,
                    agent="build", prompt="do it", timeout_s=0,
                    idle_timeout_s=0.01,
                    stream_path=Path(directory) / "model.stream.jsonl",
                    max_output_tokens=1000, show_live=False,
                )

        self.assertTrue(result.timed_out)
        self.assertEqual(result.error, "idle timeout after 0.01s")
        self.assertEqual(server.aborted, ["ses_created"])

    def test_resume_reuses_session_without_creating_another(self):
        server = self.FakeServer([
            {"type": "session.status", "properties": {
                "sessionID": "ses_existing", "status": {"type": "busy"},
            }},
            {"type": "session.status", "properties": {
                "sessionID": "ses_existing", "status": {"type": "idle"},
            }},
        ])
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch("bench.opencode_api.OpenCodeServer", return_value=server):
                result = run_session(
                    directory=directory, model="test/model", variant=None,
                    agent="build", prompt="continue", timeout_s=10,
                    idle_timeout_s=10,
                    stream_path=Path(directory) / "model.stream.jsonl",
                    max_output_tokens=1000, show_live=False,
                    session_id="ses_existing",
                )

        self.assertEqual(result.session_id, "ses_existing")
        self.assertFalse(any(path == "/session" for _, path, _ in server.requests))

    def test_rejects_permission_requests_so_noninteractive_runs_do_not_stall(self):
        server = self.FakeServer([
            {"type": "permission.asked", "properties": {
                "id": "per_test", "sessionID": "ses_created",
                "permission": "external_directory", "patterns": ["/tmp/*"],
            }},
            {"type": "session.status", "properties": {
                "sessionID": "ses_created", "status": {"type": "idle"},
            }},
        ])
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch("bench.opencode_api.OpenCodeServer", return_value=server):
                result = run_session(
                    directory=directory, model="test/model", variant=None,
                    agent="build", prompt="do it", timeout_s=10,
                    idle_timeout_s=10,
                    stream_path=Path(directory) / "model.stream.jsonl",
                    max_output_tokens=1000, show_live=False,
                )

        self.assertIsNone(result.error)
        self.assertIn(
            ("POST", "/permission/per_test/reply", {"reply": "reject"}),
            server.requests,
        )


if __name__ == "__main__":
    unittest.main()
