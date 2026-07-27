"""Small stdlib-only client for OpenCode's HTTP and SSE APIs."""

import base64
import dataclasses
import json
import os
import queue
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


def iter_sse_events(lines):
    """Yield decoded JSON payloads from an iterable of SSE lines."""
    data = []
    for raw_line in lines:
        line = raw_line.decode("utf-8", errors="replace") if isinstance(raw_line, bytes) else raw_line
        line = line.rstrip("\r\n")
        if not line:
            if data:
                try:
                    event = json.loads("\n".join(data))
                except json.JSONDecodeError:
                    pass
                else:
                    if isinstance(event, dict):
                        yield event
                data.clear()
            continue
        if line.startswith(":"):
            continue
        if line.startswith("data:"):
            value = line[5:]
            data.append(value[1:] if value.startswith(" ") else value)
    if data:
        try:
            event = json.loads("\n".join(data))
        except json.JSONDecodeError:
            return
        if isinstance(event, dict):
            yield event


@dataclasses.dataclass(frozen=True)
class MonitorResult:
    progress: bool = False
    action: bool = False
    heartbeat: bool = False
    done: bool = False
    error: str | None = None


def _event_session_id(event):
    properties = event.get("properties") or {}
    if event.get("type") == "message.part.updated":
        return (properties.get("part") or {}).get("sessionID")
    if event.get("type") == "message.updated":
        return properties.get("sessionID") or (properties.get("info") or {}).get("sessionID")
    return properties.get("sessionID")


def _error_message(error):
    if not isinstance(error, dict):
        return str(error or "unknown error")
    data = error.get("data")
    if isinstance(data, dict) and data.get("message"):
        return str(data["message"])
    return str(error.get("message") or error.get("name") or "unknown error")


class RunMonitor:
    """Track progress and completion for one root session and its children."""

    def __init__(self, session_id):
        self.session_id = session_id
        self.sessions = {session_id}
        self.started = False
        self.last_finish_reason = None

    def handle(self, event):
        event_type = event.get("type")
        properties = event.get("properties") or {}
        if event_type == "server.heartbeat":
            return MonitorResult(heartbeat=True)

        if event_type == "session.created":
            info = properties.get("info") or properties
            if info.get("parentID") in self.sessions and info.get("id"):
                self.sessions.add(info["id"])
                return MonitorResult(progress=True)
            return MonitorResult()

        session_id = _event_session_id(event)
        if session_id not in self.sessions:
            return MonitorResult()

        if event_type == "session.error":
            return MonitorResult(progress=True, error=_error_message(properties.get("error")))

        if event_type == "session.status":
            status = properties.get("status") or {}
            status_type = status.get("type")
            if session_id == self.session_id and status_type == "idle":
                return MonitorResult(progress=self.started, done=self.started)
            if status_type in {"busy", "retry"}:
                self.started = True
                return MonitorResult(progress=True)
            return MonitorResult()

        if event_type == "message.part.updated":
            part = properties.get("part") or {}
            if part.get("type") == "step-start":
                self.started = True
            if part.get("type") == "step-finish":
                self.last_finish_reason = part.get("reason")
            return MonitorResult(progress=True, action=part.get("type") == "tool")

        if event_type in {
            "message.part.delta",
            "message.updated",
            "permission.asked",
            "permission.replied",
            "question.asked",
            "question.replied",
            "question.rejected",
        }:
            self.started = True
            return MonitorResult(progress=True)
        return MonitorResult()


class DeltaRenderer:
    """Render text and reasoning deltas without waiting for completed parts."""

    def __init__(self, output=None):
        self.output = output or sys.stdout
        self.part_types = {}
        self.open_part = None

    def _close_line(self):
        if self.open_part is not None:
            self.output.write("\n")
            self.output.flush()
            self.open_part = None

    def handle(self, event):
        event_type = event.get("type")
        properties = event.get("properties") or {}
        if event_type == "message.part.updated":
            part = properties.get("part") or {}
            part_id = part.get("id")
            part_type = part.get("type")
            if part_id and part_type in {"text", "reasoning"}:
                self.part_types[part_id] = part_type
                if (part.get("time") or {}).get("end") and self.open_part == part_id:
                    self._close_line()
            elif part_type == "tool":
                state = part.get("state") or {}
                if state.get("status") in {"completed", "error"}:
                    self._close_line()
                    suffix = " failed" if state.get("status") == "error" else ""
                    self.output.write(f"[tool] {part.get('tool', '?')}{suffix}\n")
                    self.output.flush()
            return

        if event_type != "message.part.delta" or properties.get("field") != "text":
            return
        part_id = properties.get("partID")
        delta = properties.get("delta")
        if not part_id or not delta:
            return
        if self.open_part != part_id:
            self._close_line()
            prefix = "[thinking] " if self.part_types.get(part_id) == "reasoning" else "[model] "
            self.output.write(prefix)
            self.open_part = part_id
        self.output.write(str(delta))
        self.output.flush()

    def close(self):
        self._close_line()


class EventStream:
    def __init__(self, request):
        self.request = request
        self.events = queue.Queue()
        self.connected = threading.Event()
        self.error = None
        self.response = None
        self.thread = threading.Thread(target=self._read, daemon=True)

    def start(self, timeout=15):
        self.thread.start()
        if not self.connected.wait(timeout):
            raise TimeoutError("OpenCode event stream did not connect")
        if self.error:
            raise RuntimeError(f"OpenCode event stream failed: {self.error}")
        return self

    def _read(self):
        try:
            self.response = urllib.request.urlopen(self.request, timeout=30)
            for event in iter_sse_events(self.response):
                if event.get("type") == "server.connected":
                    self.connected.set()
                self.events.put(event)
        except Exception as exc:
            self.error = exc
        finally:
            self.connected.set()

    def close(self):
        if self.response is not None:
            self.response.close()
        self.thread.join(timeout=2)


class OpenCodeServer:
    """Own one isolated OpenCode server process for a benchmark attempt."""

    def __init__(self, directory, log_path, max_output_tokens, startup_timeout=30):
        self.directory = str(directory)
        self.log_path = Path(log_path)
        self.max_output_tokens = max_output_tokens
        self.startup_timeout = startup_timeout
        self.password = secrets.token_urlsafe(24)
        self.process = None
        self.log_file = None
        self.port = None

    @property
    def base_url(self):
        return f"http://127.0.0.1:{self.port}"

    @property
    def authorization(self):
        token = base64.b64encode(f"opencode:{self.password}".encode()).decode()
        return f"Basic {token}"

    def start(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            self.port = sock.getsockname()[1]
        env = os.environ.copy()
        env["OPENCODE_SERVER_PASSWORD"] = self.password
        env["OPENCODE_EXPERIMENTAL_OUTPUT_TOKEN_MAX"] = str(self.max_output_tokens)
        self.log_file = open(self.log_path, "w")
        self.process = subprocess.Popen(
            [
                "opencode", "serve", "--hostname", "127.0.0.1",
                "--port", str(self.port),
            ],
            cwd=self.directory,
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
        deadline = time.monotonic() + self.startup_timeout
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError(f"OpenCode server exited with {self.process.returncode}")
            try:
                self.request("GET", "/global/health", include_directory=False, timeout=1)
                return self
            except (OSError, TimeoutError):
                time.sleep(0.1)
        raise TimeoutError("OpenCode server startup timed out")

    def _request(self, method, path, body=None, include_directory=True):
        if include_directory:
            separator = "&" if "?" in path else "?"
            path += separator + urllib.parse.urlencode({"directory": self.directory})
        data = None if body is None else json.dumps(body).encode()
        headers = {"Authorization": self.authorization}
        if data is not None:
            headers["Content-Type"] = "application/json"
        return urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)

    def request(self, method, path, body=None, include_directory=True, timeout=30):
        request = self._request(method, path, body, include_directory)
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = response.read()
        except urllib.error.HTTPError as exc:
            detail = exc.read().decode(errors="replace").strip()
            raise RuntimeError(f"OpenCode API {method} {path} failed ({exc.code}): {detail}") from exc
        if not payload:
            return None
        return json.loads(payload)

    def subscribe(self):
        request = self._request("GET", "/event")
        request.add_header("Accept", "text/event-stream")
        return EventStream(request).start()

    def abort(self, session_id):
        quoted = urllib.parse.quote(session_id, safe="")
        return self.request("POST", f"/session/{quoted}/abort", timeout=10)

    def stop(self):
        if self.process is not None and self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        if self.log_file is not None:
            self.log_file.close()

    def __enter__(self):
        try:
            return self.start()
        except Exception:
            self.stop()
            raise

    def __exit__(self, exc_type, exc, traceback):
        self.stop()


@dataclasses.dataclass
class RunResult:
    session_id: str | None
    error: str | None
    wall_seconds: float
    timed_out: bool
    returncode: int


def run_session(
    *, directory, model, variant, agent, prompt, timeout_s, idle_timeout_s,
    stream_path, max_output_tokens, show_live=True, session_id=None,
    heartbeat_seconds=30, event_callback=None,
):
    """Run one prompt through an isolated OpenCode server and its SSE API."""
    start = time.monotonic()
    last_progress = start
    last_progress_type = "prompt"
    next_notice = start + heartbeat_seconds
    error = None
    timed_out = False
    renderer = DeltaRenderer() if show_live else None
    stream_path = Path(stream_path)
    stream_path.touch()
    server_log = stream_path.with_name(stream_path.name.replace(".stream.jsonl", ".server.log"))
    event_stream = None

    try:
        with OpenCodeServer(directory, server_log, max_output_tokens) as server:
            event_stream = server.subscribe()
            if session_id is None:
                created = server.request("POST", "/session", {
                    "permission": [
                        {"permission": "question", "action": "deny", "pattern": "*"},
                        {"permission": "plan_enter", "action": "deny", "pattern": "*"},
                        {"permission": "plan_exit", "action": "deny", "pattern": "*"},
                    ]
                })
                session_id = (created or {}).get("id")
                if not session_id:
                    raise RuntimeError("OpenCode did not return a session id")

            monitor = RunMonitor(session_id)
            provider_id, separator, model_id = model.partition("/")
            if not separator or not model_id:
                raise ValueError(f"invalid model name: {model}")
            quoted = urllib.parse.quote(session_id, safe="")
            payload = {
                "agent": agent,
                "model": {"providerID": provider_id, "modelID": model_id},
                "parts": [{"type": "text", "text": prompt}],
            }
            if variant:
                payload["variant"] = variant
            server.request("POST", f"/session/{quoted}/prompt_async", payload)

            with open(stream_path, "w") as stream_file:
                while True:
                    now = time.monotonic()
                    if timeout_s and now - start >= timeout_s:
                        timed_out = True
                        error = f"timeout after {timeout_s}s"
                        break
                    if idle_timeout_s and now - last_progress >= idle_timeout_s:
                        timed_out = True
                        error = f"idle timeout after {idle_timeout_s}s"
                        break
                    if event_stream.error and event_stream.events.empty():
                        error = f"event stream failed: {event_stream.error}"
                        break
                    try:
                        event = event_stream.events.get(timeout=0.25)
                    except queue.Empty:
                        if show_live and heartbeat_seconds and now >= next_notice:
                            print(
                                f"[waiting] no model progress for {int(now - last_progress)}s, "
                                f"last={last_progress_type}",
                                flush=True,
                            )
                            next_notice = now + heartbeat_seconds
                        continue

                    received = dict(event)
                    received.setdefault("timestamp", int(time.time() * 1000))
                    stream_file.write(json.dumps(received, separators=(",", ":")) + "\n")
                    stream_file.flush()
                    outcome = monitor.handle(event)
                    if event.get("type") == "permission.asked" and outcome.progress:
                        request_id = (event.get("properties") or {}).get("id")
                        if request_id:
                            permission_id = urllib.parse.quote(request_id, safe="")
                            server.request(
                                "POST",
                                f"/permission/{permission_id}/reply",
                                {"reply": "reject"},
                            )
                    if outcome.progress:
                        last_progress = time.monotonic()
                        last_progress_type = event.get("type") or "unknown"
                        next_notice = last_progress + heartbeat_seconds
                    if event_callback:
                        event_callback(session_id, event, outcome)
                    if renderer:
                        renderer.handle(event)
                    if outcome.error:
                        error = outcome.error
                        break
                    if outcome.done:
                        break

            if error:
                try:
                    server.abort(session_id)
                except Exception as exc:
                    print(f"warning: failed to abort OpenCode session: {exc}", file=sys.stderr)
            if error is None and monitor.last_finish_reason == "unknown":
                error = "empty response (reason: unknown)"
            if error is None and monitor.last_finish_reason == "length":
                error = "output length limit reached"
    except Exception as exc:
        error = str(exc)
    finally:
        if renderer:
            renderer.close()
        if event_stream:
            event_stream.close()

    return RunResult(
        session_id=session_id,
        error=error,
        wall_seconds=round(time.monotonic() - start, 2),
        timed_out=timed_out,
        returncode=0 if error is None else 1,
    )
