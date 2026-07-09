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
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent


def slugify(text):
    s = re.sub(r"[^a-zA-Z0-9]+", "-", text.strip().lower())
    return s.strip("-") or "model"


def load_config(config_path):
    with open(config_path) as f:
        cfg = json.load(f)
    cfg.setdefault("repetitions", 1)
    cfg.setdefault("timeout_seconds", 1200)
    cfg.setdefault("agent", "build")
    cfg.setdefault("prompt_file", "prompts/celeste_like.md")
    if not cfg.get("models"):
        raise ValueError("config must define a non-empty 'models' list")
    return cfg


def build_prompt(prompt_file_rel, cart_rel):
    """Reproduce the operator's usual invocation.

    The model reads the prompt file itself via its Read tool (faithful to the
    manual workflow) and is told exactly where to write the cartridge, plus the
    hard rule against reading other models' results.
    """
    return (
        f"Suis le prompt ici : {prompt_file_rel}. "
        f"Mets ton resultat dans {cart_rel} . "
        f"Il est strictement interdit de consulter les realisations des autres "
        f"modeles dans ./results ."
    )


def run_opencode(model, variant, agent, prompt, timeout_s, stream_path):
    """Launch `opencode run --format json` and stream stdout to a file.

    Returns (session_id, error_message, wall_seconds, timed_out, returncode).
    """
    cmd = ["opencode", "run", "--format", "json", "--model", model, "--agent", agent]
    if variant:
        cmd += ["--variant", variant]
    cmd.append(prompt)

    session_id = None
    error_message = None
    timed_out = False
    start = time.monotonic()

    with open(stream_path, "w") as stream_file:
        proc = subprocess.Popen(
            cmd,
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            bufsize=1,
        )
        try:
            for line in proc.stdout:
                stream_file.write(line)
                stream_file.flush()
                line = line.strip()
                if not line:
                    continue
                try:
                    evt = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if session_id is None and evt.get("sessionID"):
                    session_id = evt["sessionID"]
                if evt.get("type") == "error" and error_message is None:
                    err = evt.get("error", {})
                    data = err.get("data", {}) if isinstance(err, dict) else {}
                    error_message = data.get("message") or err.get("name") or "unknown error"
                if timeout_s and (time.monotonic() - start) > timeout_s:
                    timed_out = True
                    proc.kill()
                    break
            returncode = proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            returncode = proc.wait()

    wall_seconds = round(time.monotonic() - start, 2)
    if timed_out and error_message is None:
        error_message = f"timeout after {timeout_s}s"
    return session_id, error_message, wall_seconds, timed_out, returncode


def export_session(session_id, export_path):
    """Run `opencode export <id>` (JSON on stdout) and save it. Returns dict or None."""
    try:
        result = subprocess.run(
            ["opencode", "export", session_id],
            cwd=str(REPO_ROOT),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired:
        return None
    raw = result.stdout
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    with open(export_path, "w") as f:
        json.dump(data, f, indent=2)
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


def check_boot(cart_path):
    """Factual clean-boot check via `pico8 -x`. Returns True/False/None."""
    if not cart_path.exists():
        return None
    try:
        result = subprocess.run(
            ["timeout", "10", "pico8", "-x", str(cart_path)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=20,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return None
    out = result.stdout or ""
    if "syntax error" in out or "runtime error" in out:
        return False
    return "RUNNING:" in out


CSV_FIELDS = [
    "timestamp", "out", "model", "variant", "rep", "session_id",
    "cartridge_written", "booted_clean",
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
        "| Result | Model | Variant | Boot | Total tok | In | Out | Reason | "
        "Cache R | Cost $ | Wall s | Iters | Tools | Error |\n"
        "| --- | --- | --- | :---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n"
    )
    lines = [header]
    ranked = sorted(
        rows,
        key=lambda r: (r.get("error") is not None, r.get("tokens_total") or 1 << 62),
    )
    for r in ranked:
        boot = {True: "ok", False: "FAIL", None: "?"}[r.get("booted_clean")]
        err = (r.get("error") or "").replace("|", "/")[:40]
        lines.append(
            "| {out} | {model} | {variant} | {boot} | {tot} | {tin} | {tout} | "
            "{tr} | {cr} | {cost} | {wall} | {it} | {tools} | {err} |\n".format(
                out=r.get("out", ""),
                model=r.get("model", ""),
                variant=r.get("variant") or "-",
                boot=boot,
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
                "rep": rep, "out": out, "base": base,
            })

    results_dir = REPO_ROOT / "results"
    print(f"Planned {len(plan)} run(s); carts+metrics -> results/, raw artifacts -> {run_dir}")
    for p in plan:
        v = f" (variant={p['variant']})" if p["variant"] else ""
        print(f"  - {p['out']}{v} rep {p['rep']} -> results/{p['base']}.p8")
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
        # raw artifacts stay under results/runs/<ts>/ (gitignored)
        stream_path = run_dir / f"{base}.stream.jsonl"
        export_path = run_dir / f"{base}.export.json"

        print(f"\n[{idx}/{len(plan)}] {p['label']} rep {p['rep']} ({p['model']})")
        prompt = build_prompt(prompt_file_rel, cart_rel)

        session_id, error_message, wall_seconds, timed_out, returncode = run_opencode(
            p["model"], p["variant"], cfg["agent"], prompt,
            cfg["timeout_seconds"], stream_path,
        )
        print(f"    session={session_id} wall={wall_seconds}s "
              f"{'TIMEOUT ' if timed_out else ''}{'error='+error_message if error_message else 'ok'}")

        row = {
            "timestamp": ts,
            "out": p["out"],
            "model": p["model"],
            "variant": p["variant"],
            "rep": p["rep"],
            "session_id": session_id,
            "cartridge_written": cart_path.exists(),
            "booted_clean": check_boot(cart_path),
            "wall_seconds": wall_seconds,
            "error": error_message,
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

        with open(metrics_path, "w") as f:
            json.dump(row, f, indent=2)
        rows.append(row)

    write_csv(rows, REPO_ROOT / "results" / "metrics.csv")
    write_markdown(rows, REPO_ROOT / "results" / "metrics.md")
    print(f"\nWrote results/metrics.csv and results/metrics.md ({len(rows)} run(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
