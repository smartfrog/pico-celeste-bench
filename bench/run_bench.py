#!/usr/bin/env python3
"""PICO-Celeste Bench harness.

Drives opencode headless (one run per model x repetition), points it at the
celeste_like task prompt, and collects quantitative metrics per run:
tokens, cost, wall-clock time, iterations (assistant messages), tool calls,
and a factual clean-boot check via `pico8 -x`.

Usage:
    python bench/run_bench.py                 # uses bench/models.json
    python bench/run_bench.py --config path   # custom config
    python bench/run_bench.py --dry-run       # print planned runs, do nothing

Metrics source of truth: `opencode export <sessionID>` (JSON on stdout).
No external dependencies (Python stdlib only).
"""

import argparse
import collections
import csv
import datetime
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

try:
    from bench.opencode_api import run_session
except ModuleNotFoundError:
    from opencode_api import run_session

REPO_ROOT = Path(__file__).resolve().parent.parent


def slugify(text):
    s = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower())
    return s.strip("-") or "model"


def load_config(config_path):
    with open(config_path) as f:
        cfg = json.load(f)
    cfg.setdefault("repetitions", 1)
    cfg.setdefault("max_attempts", 3)
    cfg.setdefault("timeout_seconds", 1200)
    cfg.setdefault("idle_timeout_seconds", 600)
    cfg.setdefault("demo_timeout_seconds", 100)
    cfg.setdefault("max_output_tokens", 32000)
    cfg.setdefault("agent", "build")
    cfg.setdefault("prompt_file", "prompts/celeste_like.md")
    if not cfg.get("models"):
        raise ValueError("config must define a non-empty 'models' list")
    return cfg


def build_prompt(prompt_file_rel, cart_rel, cart_name, gif_name):
    """Reproduce the operator's usual invocation.

    The model reads the prompt file itself via its Read tool (faithful to the
    manual workflow) and is told exactly where to write the cartridge, plus the
    hard rule against reading other models' results.
    """
    return (
        f"Suis le prompt ici : {prompt_file_rel}. "
        f"Mets ton resultat dans {cart_rel} . "
        f"Le nom exact de la cartouche est {json.dumps(cart_name)} et doit etre "
        f"affiche dans le jeu. Le nom exact du GIF a passer a "
        f"extcmd(\"set_filename\", ...) est {json.dumps(gif_name)} . "
        f"Il est strictement interdit de consulter les realisations des autres "
        f"modeles dans ./results ."
    )


def format_live_event(evt):
    """Return a compact, human-readable line for an opencode JSON event."""
    event_type = evt.get("type")
    part = evt.get("part", {}) or {}

    if event_type == "text":
        text = (part.get("text") or "").strip()
        return f"[model] {text}" if text else None

    if event_type == "reasoning":
        text = (part.get("text") or "").strip()
        return f"[thinking] {text}" if text else None

    if event_type == "tool_use":
        tool = part.get("tool", "?")
        state = part.get("state", {}) or {}
        tool_input = state.get("input", {}) or {}
        detail = None
        for key in ("filePath", "path", "url", "cart_path", "command", "description"):
            value = tool_input.get(key)
            if value:
                detail = str(value).replace("\n", " ")
                break
        if tool == "apply_patch" and not detail:
            patch = tool_input.get("patchText", "")
            match = re.search(r"\*\*\* (?:Add|Update|Delete) File: ([^\n]+)", patch)
            if match:
                detail = match.group(1)
        if detail and len(detail) > 180:
            detail = detail[:177] + "..."
        return f"[tool] {tool}{' ' + detail if detail else ''}"

    if event_type == "error":
        err = evt.get("error", {}) or {}
        data = err.get("data", {}) if isinstance(err, dict) else {}
        message = data.get("message") or err.get("name") or "unknown error"
        return f"[error] {message}"

    return None


def print_live_event(evt):
    """Print an event while keeping multiline model messages readable."""
    rendered = format_live_event(evt)
    if not rendered:
        return
    lines = rendered.splitlines()
    print(lines[0], flush=True)
    for line in lines[1:]:
        print(f"        {line}", flush=True)


def build_resume_prompt(error_message, cart_exists, booted_clean, demo_gif_written):
    """Build a targeted resume message based on the failure mode."""
    if not cart_exists:
        return (
            "Continue depuis ton etat actuel. N'effectue pas la recherche a nouveau. "
            "Aucune cartouche valide n'a ete produite. Ecris le fichier .p8 demande "
            "maintenant, verifie le boot avec pico8 -x, puis termine."
        )
    if not booted_clean:
        return (
            "Continue depuis ton etat actuel. La cartouche ne demarre pas proprement. "
            "Lance pico8 -x, corrige les erreurs de syntaxe/runtime, puis termine."
        )
    if not demo_gif_written:
        return (
            "Continue depuis ton etat actuel. La cartouche demarre mais l'autoplay "
            "n'a pas cree le GIF. Corrige uniquement la demo pour qu'elle atteigne "
            "vraiment CLEAR! et sauvegarde le GIF, puis termine."
        )
    return (
        "Continue depuis ton etat actuel. N'effectue pas la recherche a nouveau. "
        "Termine la tache demandee maintenant."
    )


def is_resumable(error_message):
    """Check whether an error is worth retrying (not auth/billing/provider death)."""
    if not error_message:
        return False
    lower = error_message.lower()
    if any(k in lower for k in ("credit", "402", "401", "auth", "api key", "forbidden")):
        return False
    return True


def task_incomplete_reason(cart_exists, booted_clean, demo_gif_written):
    """Describe the first missing artifact required for a successful run."""
    if not cart_exists:
        return "no cartridge written"
    if not booted_clean:
        return "cartridge does not boot cleanly"
    if not demo_gif_written:
        return "demo GIF not written"
    return None


def write_json_atomic(path, data):
    """Write JSON without exposing a partially-written state file."""
    temp_path = path.with_suffix(path.suffix + ".tmp")
    with open(temp_path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")
    os.replace(temp_path, path)


def load_metrics(path):
    """Load persisted run metrics, including an in-progress checkpoint."""
    try:
        with open(path) as f:
            state = json.load(f)
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as exc:
        print(f"warning: invalid metrics {path}: {exc}", file=sys.stderr)
        return None
    return state if isinstance(state, dict) else None


def metrics_complete(metrics):
    return bool(
        metrics
        and metrics.get("cartridge_written")
        and metrics.get("booted_clean")
        and metrics.get("demo_gif_written")
    )


def iso_now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def run_opencode(
    model, variant, agent, prompt, timeout_s, stream_path,
    max_output_tokens=32000, show_live=True, session_id=None,
    heartbeat_seconds=30, event_callback=None, idle_timeout_s=600,
):
    """Run OpenCode through an isolated HTTP server and native SSE stream.

    Returns (session_id, error_message, wall_seconds, timed_out, returncode).
    """
    result = run_session(
        directory=REPO_ROOT,
        model=model,
        variant=variant,
        agent=agent,
        prompt=prompt,
        timeout_s=timeout_s,
        idle_timeout_s=idle_timeout_s,
        stream_path=stream_path,
        max_output_tokens=max_output_tokens,
        show_live=show_live,
        session_id=session_id,
        heartbeat_seconds=heartbeat_seconds,
        event_callback=event_callback,
    )
    return (
        result.session_id,
        result.error,
        result.wall_seconds,
        result.timed_out,
        result.returncode,
    )


def export_session(session_id, export_path):
    """Run `opencode export <id>` (JSON on stdout) and save it. Returns dict or None."""
    try:
        # Bun can truncate large stdout writes when they are captured through a
        # pipe. A regular file descriptor lets opencode flush the full export.
        with open(export_path, "w") as export_file:
            result = subprocess.run(
                ["opencode", "export", session_id],
                cwd=str(REPO_ROOT),
                stdout=export_file,
                stderr=subprocess.PIPE,
                text=True,
                timeout=120,
            )
    except subprocess.TimeoutExpired:
        print(f"warning: session export timed out: {session_id}", file=sys.stderr)
        return None
    if result.returncode != 0:
        detail = (result.stderr or "").strip()
        print(f"warning: session export failed: {detail or result.returncode}", file=sys.stderr)
        return None
    try:
        with open(export_path) as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"warning: invalid session export for {session_id}: {exc}", file=sys.stderr)
        return None
    return data


def extract_metrics(export_data):
    """Pull token/cost/iteration/tool metrics from an export JSON."""
    info = export_data.get("info", {})
    tokens = info.get("tokens", {}) or {}
    cache = tokens.get("cache", {}) or {}
    t_in = tokens.get("input", 0) or 0
    t_out = tokens.get("output", 0) or 0
    t_reason = tokens.get("reasoning", 0) or 0
    c_read = cache.get("read", 0) or 0
    c_write = cache.get("write", 0) or 0

    time_info = info.get("time", {}) or {}
    created = time_info.get("created")
    updated = time_info.get("updated")
    session_seconds = None
    if created and updated:
        session_seconds = round((updated - created) / 1000, 2)

    messages = export_data.get("messages", [])
    assistant_messages = sum(
        1 for m in messages if m.get("info", {}).get("role") == "assistant"
    )
    tool_calls = collections.Counter()
    for m in messages:
        for p in m.get("parts", []):
            if p.get("type") == "tool":
                tool_calls[p.get("tool", "?")] += 1

    return {
        "tokens_input": t_in,
        "tokens_output": t_out,
        "tokens_reasoning": t_reason,
        "cache_read": c_read,
        "cache_write": c_write,
        "tokens_total": t_in + t_out + t_reason,
        "cost": info.get("cost", 0) or 0,
        "session_seconds": session_seconds,
        "assistant_messages": assistant_messages,
        "tool_calls_total": sum(tool_calls.values()),
        "tool_calls_by_name": dict(tool_calls),
    }


def extract_stream_metrics(stream_path):
    """Recover metrics from an opencode JSONL stream when export is unavailable."""
    totals = collections.Counter()
    tool_calls = collections.Counter()
    assistant_messages = 0
    cost = 0
    first_timestamp = None
    last_timestamp = None
    seen_tools = set()

    with open(stream_path) as f:
        for line in f:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue

            timestamp = event.get("timestamp")
            if isinstance(timestamp, (int, float)):
                if first_timestamp is None:
                    first_timestamp = timestamp
                last_timestamp = timestamp

            event_type = event.get("type")
            part = event.get("part", {}) or {}
            if event_type == "message.part.updated":
                part = (event.get("properties") or {}).get("part") or {}
                if part.get("type") == "tool":
                    state = part.get("state") or {}
                    part_id = part.get("id")
                    if (
                        part_id not in seen_tools
                        and state.get("status") in ("completed", "error")
                    ):
                        seen_tools.add(part_id)
                        tool_calls[part.get("tool", "?")] += 1
                if part.get("type") == "step-finish":
                    event_type = "step_finish"
            if event_type == "tool_use":
                tool_calls[part.get("tool", "?")] += 1
            elif event_type == "step_finish":
                assistant_messages += 1
                tokens = part.get("tokens", {}) or {}
                cache = tokens.get("cache", {}) or {}
                totals["input"] += tokens.get("input", 0) or 0
                totals["output"] += tokens.get("output", 0) or 0
                totals["reasoning"] += tokens.get("reasoning", 0) or 0
                totals["cache_read"] += cache.get("read", 0) or 0
                totals["cache_write"] += cache.get("write", 0) or 0
                cost += part.get("cost", 0) or 0

    session_seconds = None
    if first_timestamp is not None and last_timestamp is not None:
        session_seconds = round((last_timestamp - first_timestamp) / 1000, 2)

    return {
        "tokens_input": totals["input"],
        "tokens_output": totals["output"],
        "tokens_reasoning": totals["reasoning"],
        "cache_read": totals["cache_read"],
        "cache_write": totals["cache_write"],
        "tokens_total": totals["input"] + totals["output"] + totals["reasoning"],
        "cost": cost,
        "session_seconds": session_seconds,
        "assistant_messages": assistant_messages,
        "tool_calls_total": sum(tool_calls.values()),
        "tool_calls_by_name": dict(tool_calls),
    }


def extract_stream_metrics_many(stream_paths):
    """Combine fallback metrics from every attempt in a resumed session."""
    combined = collections.Counter()
    tool_calls = collections.Counter()
    for stream_path in stream_paths:
        metrics = extract_stream_metrics(stream_path)
        for field in (
            "tokens_input", "tokens_output", "tokens_reasoning",
            "cache_read", "cache_write", "tokens_total", "cost",
            "session_seconds", "assistant_messages", "tool_calls_total",
        ):
            combined[field] += metrics.get(field) or 0
        tool_calls.update(metrics.get("tool_calls_by_name") or {})
    return {
        **combined,
        "tool_calls_by_name": dict(tool_calls),
    }


def check_boot(cart_path):
    """Factual clean-boot check via `pico8 -x`. Returns True/False/None."""
    if not cart_path.exists():
        return None
    with tempfile.TemporaryDirectory(prefix="pico-celeste-boot-") as home:
        try:
            result = subprocess.run(
                ["timeout", "10", "pico8", "-x", str(cart_path), "-home", home],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
            )
        except (subprocess.TimeoutExpired, OSError):
            return None
    out = result.stdout or ""
    if "syntax error" in out or "runtime error" in out:
        return False
    return "RUNNING:" in out


def capture_demo(cart_path, gif_path, timeout_s=100):
    """Run the final cart's autoplay and accept only a freshly written GIF."""
    if not cart_path.exists():
        return False
    gif_path.unlink(missing_ok=True)
    with tempfile.TemporaryDirectory(prefix="pico-celeste-demo-") as home:
        recorded_gif = Path(home) / "carts" / gif_path.name
        try:
            proc = subprocess.Popen(
                [
                    "pico8", "-x", str(cart_path),
                    "-home", home, "-gif_len", "120", "-gif_scale", "4",
                ],
                cwd=str(gif_path.parent),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError as exc:
            print(f"warning: demo capture failed to start: {exc}", file=sys.stderr)
            return False

        deadline = time.monotonic() + timeout_s
        try:
            while time.monotonic() < deadline:
                if recorded_gif.is_file() and recorded_gif.stat().st_size > 0:
                    # EXTCMD("video") writes synchronously; allow filesystem
                    # metadata to settle before copying and stopping the cart.
                    time.sleep(0.5)
                    shutil.copy2(recorded_gif, gif_path)
                    return gif_path.stat().st_size > 0
                if proc.poll() is not None:
                    break
                time.sleep(0.1)
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
    return False


CSV_FIELDS = [
    "timestamp", "out", "model", "variant", "rep", "session_id",
    "cartridge_written", "booted_clean", "demo_gif_written",
    "last_progress_at", "last_progress_type", "last_heartbeat_at",
    "last_action_at", "last_action_type", "idle_timeout_seconds",
    "tokens_input", "tokens_output", "tokens_reasoning",
    "cache_read", "cache_write", "tokens_total",
    "cost", "wall_seconds", "session_seconds",
    "assistant_messages", "tool_calls_total", "tool_calls_by_name",
    "error",
]


def write_csv(rows, csv_path):
    with open(csv_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS, extrasaction="ignore")
        writer.writeheader()
        for r in rows:
            row = dict(r)
            if isinstance(row.get("tool_calls_by_name"), dict):
                row["tool_calls_by_name"] = json.dumps(row["tool_calls_by_name"])
            writer.writerow(row)


def write_markdown(rows, md_path):
    header = (
        "| Result | Model | Variant | Boot | Demo GIF | Total tok | In | Out | Reason | "
        "Cache R | Cost $ | Wall s | Iters | Tools | Error |\n"
        "| --- | --- | --- | :---: | :---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n"
    )
    lines = [header]
    ranked = sorted(
        rows,
        key=lambda r: (r.get("error") is not None, r.get("tokens_total") or 1 << 62),
    )
    for r in ranked:
        boot = {True: "ok", False: "FAIL", None: "?"}[r.get("booted_clean")]
        demo = "ok" if r.get("demo_gif_written") else "FAIL"
        err = (r.get("error") or "").replace("|", "/")[:40]
        lines.append(
            "| {out} | {model} | {variant} | {boot} | {demo} | {tot} | {tin} | {tout} | "
            "{tr} | {cr} | {cost} | {wall} | {it} | {tools} | {err} |\n".format(
                out=r.get("out", ""),
                model=r.get("model", ""),
                variant=r.get("variant") or "-",
                boot=boot,
                demo=demo,
                tot=r.get("tokens_total", ""),
                tin=r.get("tokens_input", ""),
                tout=r.get("tokens_output", ""),
                tr=r.get("tokens_reasoning", ""),
                cr=r.get("cache_read", ""),
                cost=r.get("cost", ""),
                wall=r.get("wall_seconds", ""),
                it=r.get("assistant_messages", ""),
                tools=r.get("tool_calls_total", ""),
                err=err,
            )
        )
    with open(md_path, "w") as f:
        f.write("# Benchmark Metrics\n\n")
        f.write("".join(lines))


def main():
    parser = argparse.ArgumentParser(description="PICO-Celeste Bench harness")
    parser.add_argument("--config", default=str(REPO_ROOT / "bench" / "models.json"))
    parser.add_argument("--dry-run", action="store_true", help="print planned runs, do nothing")
    parser.add_argument("--quiet", action="store_true", help="hide live model and tool activity")
    args = parser.parse_args()

    cfg = load_config(args.config)
    prompt_file_rel = cfg["prompt_file"]
    if not (REPO_ROOT / prompt_file_rel).exists():
        print(f"error: prompt file not found: {prompt_file_rel}", file=sys.stderr)
        return 1

    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = REPO_ROOT / "results" / "runs" / ts
    reps = cfg["repetitions"]

    plan = []
    for m in cfg["models"]:
        model = m["model"]
        variant = m.get("variant")
        # 'out' is the stable file name (required); it doubles as the display id.
        # 'label' is optional prettier text; defaults to 'out'.
        out = m.get("out") or slugify(m.get("label") or model)
        label = m.get("label", out)
        for rep in range(1, reps + 1):
            # stable per-model name; only suffix reps when there is more than one
            base = out if reps == 1 else f"{out}-r{rep}"
            plan.append({
                "model": model, "variant": variant, "label": label,
                "cart_name": m.get("cart_name", label),
                "max_output_tokens": m.get("max_output_tokens", cfg["max_output_tokens"]),
                "rep": rep, "out": out, "base": base,
            })

    results_dir = REPO_ROOT / "results"
    print(f"Planned {len(plan)} run(s); carts+metrics -> results/, raw artifacts -> {run_dir}")
    for p in plan:
        v = f" (variant={p['variant']})" if p["variant"] else ""
        target = f"results/{p['base']}.p8"
        existing = " [skip existing]" if (results_dir / f"{p['base']}.p8").exists() else ""
        print(f"  - {p['out']}{v} rep {p['rep']} -> {target}{existing}")
    if args.dry_run:
        return 0

    run_dir.mkdir(parents=True, exist_ok=True)
    rows = []

    for idx, p in enumerate(plan, 1):
        base = p["base"]
        # final cartridge + per-model metrics live in results/ (committable)
        cart_rel = f"results/{base}.p8"
        cart_path = results_dir / f"{base}.p8"
        metrics_path = results_dir / f"{base}.metrics.json"
        gif_path = results_dir / f"{base}.gif"
        # raw artifacts stay under results/runs/<ts>/ (gitignored)
        stream_path = run_dir / f"{base}.stream.jsonl"
        export_path = run_dir / f"{base}.export.json"

        print(f"\n[{idx}/{len(plan)}] {p['label']} rep {p['rep']} ({p['model']})")
        saved_metrics = load_metrics(metrics_path)
        resume_session_id = None
        start_new_session = False
        attempt = 1
        if saved_metrics and not metrics_complete(saved_metrics) and saved_metrics.get("session_id"):
            print(f"    Incomplete session found: {saved_metrics['session_id']}")
            print(f"    status={saved_metrics.get('status', 'unknown')} "
                  f"last_event={saved_metrics.get('last_event_at', 'unknown')}")
            if not sys.stdin.isatty():
                print("    SKIP incomplete run (confirmation requires a TTY)")
                continue
            try:
                choice = input("    [r]esume / [n]ew session / [s]kip: ").strip().lower()
            except EOFError:
                choice = "s"
            if choice == "r":
                resume_session_id = saved_metrics["session_id"]
                attempt = int(saved_metrics.get("attempt") or 1) + 1
                stream_path = run_dir / f"{base}.attempt-{attempt}.stream.jsonl"
            elif choice == "n":
                metrics_path.unlink(missing_ok=True)
                saved_metrics = None
                start_new_session = True
            else:
                print("    SKIP incomplete session")
                continue

        if cart_path.exists() and not resume_session_id and not start_new_session:
            print(f"    SKIP existing: {cart_rel}")
            try:
                with open(metrics_path) as f:
                    rows.append(json.load(f))
            except (OSError, json.JSONDecodeError) as exc:
                print(f"warning: existing metrics unavailable for {base}: {exc}", file=sys.stderr)
            continue

        if not resume_session_id:
            # Only artifacts created by this run may count toward its result.
            for artifact_path in (cart_path, gif_path, metrics_path):
                artifact_path.unlink(missing_ok=True)
        prompt = (
            build_resume_prompt(
                None,
                cart_path.exists(),
                bool((saved_metrics or {}).get("booted_clean")),
                gif_path.exists(),
            )
            if resume_session_id else
            build_prompt(prompt_file_rel, cart_rel, p["cart_name"], f"{base}.gif")
        )

        stream_paths = []
        if resume_session_id:
            stream_paths.extend((saved_metrics or {}).get("stream_paths") or [])
            saved_stream = (saved_metrics or {}).get("stream_path")
            if saved_stream and saved_stream not in stream_paths:
                stream_paths.append(saved_stream)
        current_stream = str(stream_path.relative_to(REPO_ROOT))
        stream_paths.append(current_stream)
        prior_wall_seconds = (
            float((saved_metrics or {}).get("wall_seconds") or 0)
            if resume_session_id else 0
        )

        run_metrics = {
            "timestamp": ts,
            "out": p["out"],
            "model": p["model"],
            "variant": p["variant"],
            "rep": p["rep"],
            "status": "starting",
            "session_id": resume_session_id,
            "attempt": attempt,
            "stream_path": current_stream,
            "stream_paths": stream_paths,
            "started_at": (saved_metrics or {}).get("started_at") or iso_now(),
            "last_event_at": (saved_metrics or {}).get("last_event_at"),
            "last_event_type": (saved_metrics or {}).get("last_event_type"),
            "last_progress_at": (saved_metrics or {}).get("last_progress_at"),
            "last_progress_type": (saved_metrics or {}).get("last_progress_type"),
            "last_heartbeat_at": (saved_metrics or {}).get("last_heartbeat_at"),
            "last_action_at": iso_now(),
            "last_action_type": "prompt",
            "idle_timeout_seconds": cfg["idle_timeout_seconds"],
            "cartridge_written": cart_path.exists(),
            "booted_clean": False,
            "demo_gif_written": False,
            "wall_seconds": (saved_metrics or {}).get("wall_seconds"),
            "error": None,
        }
        write_json_atomic(metrics_path, run_metrics)

        def persist_event(active_session_id, event, outcome):
            run_metrics["status"] = "running"
            if active_session_id:
                run_metrics["session_id"] = active_session_id
            run_metrics["last_event_at"] = iso_now()
            run_metrics["last_event_type"] = event.get("type") or "unknown"
            if outcome.progress:
                run_metrics["last_progress_at"] = run_metrics["last_event_at"]
                run_metrics["last_progress_type"] = run_metrics["last_event_type"]
            if outcome.heartbeat:
                run_metrics["last_heartbeat_at"] = run_metrics["last_event_at"]
            if outcome.action:
                part = (event.get("properties") or {}).get("part") or {}
                run_metrics["last_action_at"] = run_metrics["last_event_at"]
                run_metrics["last_action_type"] = part.get("tool") or run_metrics["last_event_type"]
            write_json_atomic(metrics_path, run_metrics)

        session_id, error_message, attempt_wall, timed_out, returncode = run_opencode(
            p["model"], p["variant"], cfg["agent"], prompt,
            cfg["timeout_seconds"], stream_path,
            max_output_tokens=p["max_output_tokens"], show_live=not args.quiet,
            session_id=resume_session_id, event_callback=persist_event,
            idle_timeout_s=cfg["idle_timeout_seconds"],
        )
        run_metrics["session_id"] = session_id
        run_metrics["status"] = "evaluating"
        run_metrics["provider_error"] = error_message
        wall_seconds = prior_wall_seconds + attempt_wall
        run_metrics["wall_seconds"] = wall_seconds
        write_json_atomic(metrics_path, run_metrics)
        provider_status = (
            "timeout" if timed_out else
            f"error: {error_message}" if error_message else
            "ok"
        )
        print(f"    session={session_id} wall={attempt_wall}s provider={provider_status}")

        booted_clean = check_boot(cart_path)
        demo_gif_written = (
            capture_demo(cart_path, gif_path, cfg["demo_timeout_seconds"])
            if booted_clean else False
        )
        print(f"    boot={'ok' if booted_clean else 'FAIL'} "
              f"demo_gif={'ok' if demo_gif_written else 'FAIL'}")
        incomplete_reason = task_incomplete_reason(
            cart_path.exists(), booted_clean, demo_gif_written,
        )
        print(f"    task={'INCOMPLETE: ' + incomplete_reason if incomplete_reason else 'COMPLETE'}")
        if incomplete_reason and not error_message:
            error_message = incomplete_reason

        # Interactive resume on failure (TTY only).
        while (
            sys.stdin.isatty()
            and session_id
            and not (cart_path.exists() and booted_clean and demo_gif_written)
            and is_resumable(error_message)
            and attempt < cfg["max_attempts"]
        ):
            print(f"\n    TASK INCOMPLETE: {error_message}")
            print(f"    cartridge={'written' if cart_path.exists() else 'missing'} "
                  f"boot={'ok' if booted_clean else 'FAIL'} "
                  f"gif={'ok' if demo_gif_written else 'missing'}")
            print(f"    session={session_id}")
            try:
                choice = input("    Resume? [r]esume / [s]kip / [a]bort: ").strip().lower()
            except EOFError:
                break
            if choice == "a":
                print("    Aborting benchmark.")
                break
            if choice != "r":
                break

            attempt += 1
            attempt_stream = run_dir / f"{base}.attempt-{attempt}.stream.jsonl"
            resume_prompt = build_resume_prompt(
                error_message, cart_path.exists(), booted_clean, demo_gif_written,
            )
            print(f"    Resuming session {session_id} (attempt {attempt})...")
            run_metrics.update({
                "status": "starting",
                "attempt": attempt,
                "stream_path": str(attempt_stream.relative_to(REPO_ROOT)),
                "provider_error": None,
                "last_action_at": iso_now(),
                "last_action_type": "prompt",
            })
            run_metrics["stream_paths"].append(run_metrics["stream_path"])
            write_json_atomic(metrics_path, run_metrics)
            _, error_message, resume_wall, _, _ = run_opencode(
                p["model"], p["variant"], cfg["agent"], resume_prompt,
                cfg["timeout_seconds"], attempt_stream,
                max_output_tokens=p["max_output_tokens"], show_live=not args.quiet,
                session_id=session_id, event_callback=persist_event,
                idle_timeout_s=cfg["idle_timeout_seconds"],
            )
            wall_seconds += resume_wall
            run_metrics["status"] = "evaluating"
            run_metrics["provider_error"] = error_message
            run_metrics["wall_seconds"] = wall_seconds
            write_json_atomic(metrics_path, run_metrics)
            resume_provider_status = f"error: {error_message}" if error_message else "ok"
            print(f"    resume wall={resume_wall}s provider={resume_provider_status}")

            booted_clean = check_boot(cart_path)
            demo_gif_written = (
                capture_demo(cart_path, gif_path, cfg["demo_timeout_seconds"])
                if booted_clean else False
            )
            print(f"    boot={'ok' if booted_clean else 'FAIL'} "
                  f"demo_gif={'ok' if demo_gif_written else 'FAIL'}")
            incomplete_reason = task_incomplete_reason(
                cart_path.exists(), booted_clean, demo_gif_written,
            )
            print(f"    task={'INCOMPLETE: ' + incomplete_reason if incomplete_reason else 'COMPLETE'}")
            if incomplete_reason and not error_message:
                error_message = incomplete_reason
        if attempt >= cfg["max_attempts"]:
            print("    Max resume attempts reached.")

        row = {
            "timestamp": ts,
            "out": p["out"],
            "model": p["model"],
            "variant": p["variant"],
            "rep": p["rep"],
            "session_id": session_id,
            "cartridge_written": cart_path.exists(),
            "booted_clean": booted_clean,
            "demo_gif_written": demo_gif_written,
            "wall_seconds": wall_seconds,
            "error": error_message,
            "status": (
                "complete" if cart_path.exists() and booted_clean and demo_gif_written
                else "incomplete"
            ),
            "attempt": attempt,
            "stream_path": run_metrics.get("stream_path"),
            "stream_paths": run_metrics.get("stream_paths"),
            "started_at": run_metrics.get("started_at"),
            "last_event_at": run_metrics.get("last_event_at"),
            "last_event_type": run_metrics.get("last_event_type"),
            "last_progress_at": run_metrics.get("last_progress_at"),
            "last_progress_type": run_metrics.get("last_progress_type"),
            "last_heartbeat_at": run_metrics.get("last_heartbeat_at"),
            "last_action_at": run_metrics.get("last_action_at"),
            "last_action_type": run_metrics.get("last_action_type"),
            "idle_timeout_seconds": cfg["idle_timeout_seconds"],
            "tokens_input": None, "tokens_output": None, "tokens_reasoning": None,
            "cache_read": None, "cache_write": None, "tokens_total": None,
            "cost": None, "session_seconds": None,
            "assistant_messages": None, "tool_calls_total": None,
            "tool_calls_by_name": None,
        }

        if session_id:
            export_data = export_session(session_id, export_path)
            if export_data:
                row.update(extract_metrics(export_data))
            else:
                print("    using JSONL stream fallback for metrics")
                attempt_streams = [
                    REPO_ROOT / path for path in run_metrics["stream_paths"]
                    if (REPO_ROOT / path).exists()
                ]
                row.update(extract_stream_metrics_many(attempt_streams))

        write_json_atomic(metrics_path, row)
        rows.append(row)

    write_csv(rows, REPO_ROOT / "results" / "metrics.csv")
    write_markdown(rows, REPO_ROOT / "results" / "metrics.md")
    print(f"\nWrote results/metrics.csv and results/metrics.md ({len(rows)} run(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
