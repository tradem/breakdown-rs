#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
"""Measure an AI-import apply, with and without the #900 M3 pool split.

Issue #900 shipped two measurements (M1: pool wait vs. statement in the mapping
repository, M2: append and `WRONGVER` counts per run) and the lever they point at
(runbooks §17 M3: the read-model writers get their own Postgres pool). What was
missing is the *attribution itself*: one apply, measured twice on the same
machine, so the lever is chosen by data instead of taste.

Why this is a script and not a manual run: the apply is **idempotent-convergent**.
A second run over the same data settles every mapping row it already confirmed and
skips the work, so the two halves of an A/B need a **fresh event store and a fresh
Postgres** each. Doing that by hand on the dev stack means destroying dev data; this
script builds a throwaway stack from the same pinned images on spare ports instead
(`tqwewe/sierradb:0.3.1`, `postgres:16-alpine`), so the dev volumes are never touched.

The preview the apply consumes is seeded through the `test-support`-only fixture route
(`POST /v1/__fixtures/ai-import-preview`, issue #748) with the target block named as
query parameters — no LLM, no provider, no document. The plan is **synthetic** (see
`--scenes`): same shape as the 49-scene job in issue #900 (49 scenes, 23 figures,
~107 looks, ~240 garments, one shooting day marker per row), not the original
document. Compare runs of *this* script against each other, not against the issue's
hand-measured 7 minutes.

Usage (from `backend/`):

    # both halves, fresh stack each, prints the comparison table
    python3 scripts/bench-apply-attribution.py --mode both

    # one half, keep the logs for inspection
    python3 scripts/bench-apply-attribution.py --mode split --keep

What it reads (all fields already shipped by M1/M2 — `runbooks.md` §17):

* `"AI import apply row phase finished"` — the per-run summary (`rows`, `elapsed_ms`,
  `row_ms_avg`, `mapping_acquire_ms_per_row` vs `mapping_statement_ms_per_row`, the
  pool gauges, `event_appends`, `append_conflicts`);
* `"AI import mapping write"` — one line per mapping write, i.e. the per-write
  histogram the summary sums (p50/p95 of acquire vs. statement);
* `histogram.append_emappend_duration` — one line per `EMAPPEND`, from the store's own
  instrumentation (the third number the decision table can consume).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
API_BIN = BACKEND / "target" / "debug" / "api"
DEV_AI_ENV = BACKEND / ".env.dev-ai.local"

ANSI = re.compile(r"\x1b\[[0-9;]*m")
FIELD = re.compile(r"([A-Za-z_][A-Za-z0-9_.]*)=(\S+)")


# --- throwaway stack -------------------------------------------------------


@dataclass
class Stack:
    """One isolated Postgres + SierraDB pair on its own ports."""

    tag: str
    pg_port: int
    sierra_port: int
    pg_container: str = field(init=False)
    sierra_container: str = field(init=False)

    def __post_init__(self) -> None:
        self.pg_container = f"bench900-pg-{self.tag}"
        self.sierra_container = f"bench900-sierra-{self.tag}"

    def up(self) -> None:
        self.down()
        run(
            [
                "docker", "run", "-d", "--rm", "--name", self.pg_container,
                "-e", "POSTGRES_USER=postgres", "-e", "POSTGRES_PASSWORD=postgres",
                "-e", "POSTGRES_DB=breakdown", "-p", f"{self.pg_port}:5432",
                "postgres:16-alpine",
            ]
        )
        # The idle sync interval is the ADR-016 §6 knob the dev/prod compose files
        # pin; the benchmark must use the same store behaviour or it measures a
        # configuration nobody runs.
        run(
            [
                "docker", "run", "-d", "--rm", "--name", self.sierra_container,
                "-p", f"{self.sierra_port}:9090",
                "-e", "SIERRA_SYNC.IDLE_INTERVAL_MS=4",
                "tqwewe/sierradb:0.3.1", "--dir", "/app/data",
            ]
        )
        wait_for(
            lambda: docker_ok(
                ["docker", "exec", self.pg_container, "pg_isready", "-U", "postgres"]
            ),
            timeout=90,
            what=f"postgres ({self.pg_container})",
        )
        wait_for(
            lambda: sierra_ping(self.sierra_port),
            timeout=90,
            what=f"sierradb ({self.sierra_container})",
        )

    def down(self) -> None:
        for name in (self.pg_container, self.sierra_container):
            subprocess.run(
                ["docker", "rm", "-f", name], capture_output=True, check=False
            )

    @property
    def database_url(self) -> str:
        return f"postgres://postgres:postgres@127.0.0.1:{self.pg_port}/breakdown"

    @property
    def sierradb_url(self) -> str:
        return f"redis://127.0.0.1:{self.sierra_port}/?protocol=resp3"


def run(cmd: list[str], **kwargs: object) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, check=False, **kwargs)  # type: ignore[arg-type]
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(cmd)}\n{result.stderr[-2000:]}"
        )
    return result.stdout


def port_open(port: int) -> bool:
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def docker_ok(cmd: list[str]) -> bool:
    return subprocess.run(cmd, capture_output=True, check=False).returncode == 0


def sierra_ping(port: int) -> bool:
    """Raw RESP3 `PING` — the image ships no client binary (issue #156).

    SierraDB answers a properly framed RESP array, not an inline `PING` (the same
    reason `scripts/sierradb-healthcheck.sh` frames it explicitly).
    """
    import socket

    try:
        with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
            sock.sendall(b"*1\r\n$4\r\nPING\r\n")
            return b"PONG" in sock.recv(64)
    except OSError:
        return False


def wait_for(predicate, timeout: float, what: str) -> None:  # noqa: ANN001
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return
        time.sleep(1)
    raise RuntimeError(f"timed out after {timeout:.0f}s waiting for {what}")


# --- the API under test ----------------------------------------------------


class ApiProcess:
    def __init__(self, stack: Stack, mode: str, log_path: Path, base_url: str, port: int):
        self.stack = stack
        self.mode = mode
        self.log_path = log_path
        self.base_url = base_url
        self.port = port
        self.proc: subprocess.Popen[bytes] | None = None
        self.log_file = None

    def start(self) -> None:
        env = os.environ.copy()
        env.update(read_env_file(DEV_AI_ENV))
        env.update(
            {
                "DATABASE_URL": self.stack.database_url,
                "SIERRADB_URL": self.stack.sierradb_url,
                "BIND_ADDR": f"127.0.0.1:{self.port}",
                "DEV_AUTH_SUB": "bench-user-900",
                "DEV_AUTH_EMAIL": "bench@example.invalid",
                "AI_IMPORT_ENABLED": "1",
                # The A/B switch from issue #900 M3: `0` keeps the pre-M3 topology
                # (read-model writers share the app pool), a positive value gives
                # them their own pool.
                "PROJECTOR_DATABASE_MAX_CONNECTIONS": "0" if self.mode == "unsplit" else "20",
            }
        )
        # Unbuffered stdout so the log file is greppable while the run is in flight.
        self.log_file = self.log_path.open("wb")
        self.proc = subprocess.Popen(  # noqa: S603
            [str(API_BIN)],
            cwd=str(BACKEND),
            env=env,
            stdout=self.log_file,
            stderr=subprocess.STDOUT,
        )
        try:
            wait_for(self.healthy, timeout=180, what=f"the API on :{self.port}")
        except RuntimeError:
            raise RuntimeError(
                f"the API on :{self.port} did not come up; last log lines:\n{self.log_tail()}"
            ) from None

    def log_tail(self, lines: int = 25) -> str:
        if not self.log_path.exists():
            return "(no log)"
        raw = self.log_path.read_text(errors="replace").splitlines()[-lines:]
        return "\n".join(ANSI.sub("", line) for line in raw)

    def healthy(self) -> bool:
        if self.proc is not None and self.proc.poll() is not None:
            raise RuntimeError(
                f"the API exited with code {self.proc.returncode} during boot; log tail:\n"
                f"{self.log_tail()}"
            )
        try:
            with urllib.request.urlopen(f"{self.base_url}/v1/health", timeout=5) as resp:
                body = json.loads(resp.read())
        except urllib.error.HTTPError as err:
            # 503 is the normal answer while an OPTIONAL dependency is down (Vault
            # for credentials/photos, Garage for photo bytes). The body still
            # carries the per-dependency entries, which is all this needs.
            try:
                body = json.loads(err.read())
            except ValueError:
                return False
        except (urllib.error.URLError, OSError, ValueError):
            return False
        entries = body.get("entries") or {}
        # Vault is deliberately not a boot dependency (photos/credentials only),
        # Garage only matters for payload storage; the two tiers this benchmark
        # needs are Postgres and SierraDB.
        return all(
            (entries.get(name) or {}).get("status") == "Healthy"
            for name in ("postgres", "sierradb")
        )

    def stop(self) -> None:
        """Graceful stop, then hard: the API drains AI workers before it exits."""
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                # The documented shutdown budget (drain + worker joins + reclaimer)
                # is ~55 s; a benchmark must not cut into it and leave a half-torn
                # process holding the port for the next half of the A/B.
                self.proc.wait(timeout=90)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=10)
        if self.log_file:
            self.log_file.close()
        wait_for(
            lambda: not port_open(self.port),
            timeout=60,
            what=f"port {self.port} to be released",
        )

    def call(self, method: str, path: str, body=None, block: str | None = None):  # noqa: ANN001
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(self.base_url + path, data=data, method=method)
        request.add_header("content-type", "application/json")
        if block:
            request.add_header("x-active-block", block)
        try:
            with urllib.request.urlopen(request, timeout=120) as resp:
                raw = resp.read()
                return resp.status, (json.loads(raw) if raw else None)
        except urllib.error.HTTPError as err:
            raw = err.read()
            return err.code, (json.loads(raw) if raw else None)


def read_env_file(path: Path) -> dict[str, str]:
    """Read `KEY=value` lines without exporting anything into this process."""
    if not path.exists():
        return {}
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip("'\"")
    return values


# --- the synthetic 49-scene plan ------------------------------------------


def build_plan(scenes: int, figures: int = 23) -> dict:
    """A script preview with the issue's measured entity profile.

    Issue #900 counted 49 scenes, 51 scene_shoots, 23 characters, 96 outfits, 216
    pieces and 117 beats in the real dev job. The generator targets that shape
    (two looks per scene, 2-3 garments each, a day marker per row) so the row
    phase pays a comparable number of `reserve → append → confirm` chains. It is
    still a synthetic document: quote this script's own entity counts, never the
    issue's, as the plan of a run.
    """
    cast = [f"CHAR_{i:02d}" for i in range(1, figures + 1)]
    rows = []
    looks = 0
    for number in range(1, scenes + 1):
        pair = [cast[(number * 2) % figures], cast[(number * 2 + 1) % figures]]
        outfits = []
        for k in range(2 if number % 5 else 3):
            looks += 1
            garments = 4 if looks % 4 == 0 else 3
            outfits.append(
                {
                    "character_name": pair[k % len(pair)],
                    "name": f"Look-{looks}",
                    "source_quote": "Kostümbild: Sakko, dunkle Hose",
                    "origin": "explicit_quote",
                    "pieces": [
                        {"name": f"OP-{looks}-{p}", "category_hint": "Oberteil"}
                        for p in range(1, garments + 1)
                    ],
                }
            )
        day = 1 if number % 2 else 2
        rows.append(
            {
                "draft_ref": f"row-{number}",
                "scene_number": number,
                "location": f"Ort {number % 7}",
                "summary": f"Handlung der Szene {number}",
                "characters": pair,
                "outfits": outfits,
                "shooting_day": {"number": day, "label": f"Tag {day}"},
            }
        )
    return {
        "title": "Bench-Pilot (issue #900)",
        "scenes": rows,
        "uncertainties": [],
        "scenes_detected": scenes,
        "scenes_extracted": scenes,
    }


# --- one measured apply ----------------------------------------------------


@dataclass
class Measurement:
    mode: str
    summary: dict[str, str] = field(default_factory=dict)
    acquire_p50_ms: float = 0.0
    acquire_p95_ms: float = 0.0
    statement_p50_ms: float = 0.0
    statement_p95_ms: float = 0.0
    append_p50_ms: float = 0.0
    append_p95_ms: float = 0.0
    mapping_writes: int = 0
    appends_logged: int = 0
    wall_s: float = 0.0
    result: dict = field(default_factory=dict)


def percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))
    return ordered[index]


def measure(mode: str, args: argparse.Namespace) -> Measurement:
    stack = Stack(tag=mode, pg_port=args.pg_port, sierra_port=args.sierra_port)
    log_path = Path(args.log_dir) / f"bench-900-{mode}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    api = ApiProcess(
        stack=stack,
        mode=mode,
        log_path=log_path,
        base_url=f"http://127.0.0.1:{args.api_port}",
        port=args.api_port,
    )
    measurement = Measurement(mode=mode)
    print(f"\n=== {mode} (log: {log_path}) ===", flush=True)
    try:
        stack.up()
        api.start()
        print("  stack + API up", flush=True)

        project = new_uuid()
        season = expect(api.call("POST", "/v1/seasons", {"project_id": project, "number": 1}))
        block = expect(
            api.call(
                "POST",
                "/v1/blocks",
                {"season_id": season, "project_id": project, "number": 1},
            )
        )
        episode = expect(
            api.call(
                "POST",
                "/v1/episodes",
                {"block_id": block, "project_id": project, "number": 1, "name": "Folge 1"},
                block=block,
            )
        )
        print(f"  hierarchy: season {season} / block {block} / episode {episode}", flush=True)

        plan = build_plan(args.scenes)
        outfits = sum(len(row["outfits"]) for row in plan["scenes"])
        pieces = sum(len(o["pieces"]) for row in plan["scenes"] for o in row["outfits"])
        print(f"  plan: {args.scenes} scenes, {outfits} looks, {pieces} garments", flush=True)

        fixture = (
            f"/v1/__fixtures/ai-import-preview?season_id={season}&season_number=1"
            f"&block_id={block}&block_number=1"
        )
        status, seeded = api.call("POST", fixture, plan)
        if status != 201 or not seeded or not seeded.get("job_id"):
            raise RuntimeError(f"fixture seed failed: {status} {seeded}")
        job = seeded["job_id"]

        # The attach is gated by the season policy, which reads the membership the
        # season's own creation bootstraps into `projection_project_membership` via
        # the projector. On a fresh store that row lands a moment after the season
        # is created, so a 403 here means "the read model has not caught up yet",
        # not "denied" — retry the way a client would instead of racing it.
        status, body = retry_call(
            api,
            "PUT",
            f"/v1/ai-import/jobs/{job}/target",
            {"block_id": block},
            accept=(200,),
            retry_on=(403, 409, 404),
            timeout=120,
            what="the target attach (waiting for the membership projection)",
        )
        if status != 200:
            raise RuntimeError(f"target attach failed: {status} {body}")

        apply_body = {
            "episode_id": episode,
            "mappings": [
                {"draft_ref": row["draft_ref"], "decision": "Create"}
                for row in plan["scenes"]
            ],
            "accept_as_is": True,
            "edit_distance": 0,
            "episode_groups": [],
            "shooting_days": [
                {"day_ref": "day:1", "accepted": True},
                {"day_ref": "day:2", "accepted": True},
            ],
        }
        started = time.time()
        status, accepted = api.call("POST", f"/v1/ai-import/jobs/{job}/apply", apply_body)
        if status != 202:
            raise RuntimeError(f"apply dispatch failed: {status} {accepted}")
        print(f"  apply dispatched (run {accepted.get('run_id')})", flush=True)

        job_row = wait_for_apply(api, job, started, args.apply_timeout)
        measurement.wall_s = time.time() - started
        measurement.result = job_row.get("apply_result") or {}
        state = job_row.get("apply_state")
        print(f"  apply finished: state={state} wall={measurement.wall_s:.0f}s", flush=True)
        if state != "done" or "failed" in measurement.result:
            raise RuntimeError(f"apply did not succeed: {json.dumps(measurement.result)[:600]}")

        # Give the workers a moment to flush the trailing telemetry lines before
        # the log is read; the row-phase line is written before finalisation.
        time.sleep(2)
        fill_measurement(measurement, log_path)
    finally:
        api.stop()
        if args.keep:
            print(f"  kept stack: {stack.pg_container}, {stack.sierra_container}", flush=True)
        else:
            stack.down()
    return measurement


def retry_call(
    api: ApiProcess,
    method: str,
    path: str,
    body,
    accept: tuple[int, ...],
    retry_on: tuple[int, ...],
    timeout: float,
    what: str,
):  # noqa: ANN001, ANN201
    """Call until the response is acceptable; retry the listed statuses.

    A fresh store makes the API-edge gates race the projectors: the membership a
    season's creation bootstraps, the block row itself. Retrying is what a client
    does, and it keeps the benchmark from measuring the harness instead.
    """
    deadline = time.time() + timeout
    last = (0, None)
    while time.time() < deadline:
        status, payload = api.call(method, path, body)
        last = (status, payload)
        if status in accept:
            return last
        if status not in retry_on:
            return last
        time.sleep(2)
    print(f"  ! gave up waiting for {what}: {last[0]}", flush=True)
    return last


def wait_for_apply(api: ApiProcess, job: str, started: float, timeout: float) -> dict:
    while time.time() - started < timeout:
        time.sleep(5)
        status, body = api.call("GET", f"/v1/ai-import/jobs/{job}")
        if status != 200 or not body:
            continue
        row = body.get("job") or {}
        state = row.get("apply_state")
        progress = row.get("apply_progress") or {}
        print(
            f"    +{time.time() - started:5.0f}s state={state} "
            f"stage={progress.get('stage')} rows={progress.get('applied')}/{progress.get('total')}",
            flush=True,
        )
        if state in ("done", "failed") or row.get("status") in ("failed", "dead_letter"):
            return row
    raise RuntimeError(f"apply did not finish within {timeout:.0f}s")


def fill_measurement(measurement: Measurement, log_path: Path, timeout: float = 60.0) -> None:
    """Read the three log sources out of `log_path`.

    `tracing`'s text formatter writes the message first and the fields after it, so
    every field of the summary line is found in the *whole* line (`rows=49 …` comes
    after `"AI import apply row phase finished"`). The summary is written just
    before finalisation, i.e. possibly a beat after the job row says `done` — hence
    the bounded wait instead of a single read.
    """
    acquire: list[float] = []
    statement: list[float] = []
    appends: list[float] = []
    deadline = time.time() + timeout
    while True:
        acquire.clear()
        statement.clear()
        appends.clear()
        measurement.summary = {}
        for raw in log_path.read_text(errors="replace").splitlines():
            line = ANSI.sub("", raw)
            if "AI import apply row phase finished" in line:
                measurement.summary = dict(FIELD.findall(line))
            elif "AI import mapping write" in line:
                fields = dict(FIELD.findall(line))
                acquire.append(float(fields.get("histogram.mapping_acquire_duration", 0.0)) * 1000.0)
                statement.append(
                    float(fields.get("histogram.mapping_statement_duration", 0.0)) * 1000.0
                )
            elif "histogram.append_emappend_duration" in line:
                fields = dict(FIELD.findall(line))
                appends.append(float(fields.get("histogram.append_emappend_duration", 0.0)) * 1000.0)
        if measurement.summary or time.time() >= deadline:
            break
        time.sleep(1)
    measurement.mapping_writes = len(acquire)
    measurement.appends_logged = len(appends)
    measurement.acquire_p50_ms = percentile(acquire, 0.50)
    measurement.acquire_p95_ms = percentile(acquire, 0.95)
    measurement.statement_p50_ms = percentile(statement, 0.50)
    measurement.statement_p95_ms = percentile(statement, 0.95)
    measurement.append_p50_ms = percentile(appends, 0.50)
    measurement.append_p95_ms = percentile(appends, 0.95)
    if not measurement.summary:
        raise RuntimeError(f"no row-phase summary in {log_path}")


def new_uuid() -> str:
    import uuid

    return str(uuid.uuid4())


def expect(response) -> str:  # noqa: ANN001
    status, body = response
    if status not in (200, 201) or not isinstance(body, dict) or "id" not in body:
        raise RuntimeError(f"unexpected response: {status} {body}")
    return body["id"]


# --- reporting -------------------------------------------------------------


def report(measurements: list[Measurement]) -> None:
    print("\n=== attribution (issue #900) ===")
    for m in measurements:
        s = m.summary
        print(f"\n[{m.mode}]")
        print(f"  rows / wall                 {s.get('rows')} rows, {m.wall_s:.0f} s wall")
        print(f"  elapsed_ms (row phase end)  {s.get('elapsed_ms')} ms")
        print(f"  row_ms_avg / max            {s.get('row_ms_avg')} / {s.get('row_ms_max')} ms")
        print(
            f"  mapping per row             acquire {s.get('mapping_acquire_ms_per_row')} ms "
            f"vs statement {s.get('mapping_statement_ms_per_row')} ms"
        )
        print(
            f"  mapping writes (res/ins)    {s.get('mapping_reserve_ops')} / "
            f"{s.get('mapping_insert_ops')} ({m.mapping_writes} logged)"
        )
        print(
            f"  per-write acquire p50/p95   {m.acquire_p50_ms:.1f} / {m.acquire_p95_ms:.1f} ms"
        )
        print(
            f"  per-write statement p50/p95 {m.statement_p50_ms:.1f} / {m.statement_p95_ms:.1f} ms"
        )
        print(
            f"  appends / conflicts         {s.get('event_appends')} / {s.get('append_conflicts')}"
            f" ({s.get('event_appends_per_row')} per row)"
        )
        print(
            f"  append p50/p95 (store)      {m.append_p50_ms:.1f} / {m.append_p95_ms:.1f} ms"
        )
        print(
            f"  pool at last write          size {s.get('db_pool_size')}, "
            f"idle {s.get('db_pool_num_idle')}"
        )
        print(f"  apply result                {json.dumps(m.result)[:400]}")

    if len(measurements) == 2:
        unsplit, split = measurements
        print("\n=== decision table (issue #900) ===")
        print(
            "  acquire per row: "
            f"{unsplit.summary.get('mapping_acquire_ms_per_row')} ms -> "
            f"{split.summary.get('mapping_acquire_ms_per_row')} ms"
        )
        print(
            "  statement per row: "
            f"{unsplit.summary.get('mapping_statement_ms_per_row')} ms -> "
            f"{split.summary.get('mapping_statement_ms_per_row')} ms"
        )
        print(f"  wall: {unsplit.wall_s:.0f} s -> {split.wall_s:.0f} s")
        appends = split.summary.get("event_appends")
        print(
            f"  appends: {appends} (threshold in the issue: >1500 means duplicate writes), "
            f"conflicts: {split.summary.get('append_conflicts')}"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--mode", choices=["unsplit", "split", "both"], default="both")
    parser.add_argument("--scenes", type=int, default=49, help="preview rows to generate")
    parser.add_argument("--pg-port", type=int, default=15432)
    parser.add_argument("--sierra-port", type=int, default=19090)
    parser.add_argument("--api-port", type=int, default=13000)
    parser.add_argument("--apply-timeout", type=float, default=1800.0)
    parser.add_argument("--log-dir", default="/tmp/breakdown-bench-900")
    parser.add_argument("--keep", action="store_true", help="leave the throwaway stack running")
    parser.add_argument("--no-build", action="store_true", help="reuse the existing API binary")
    parser.add_argument("--json", dest="json_out", help="write the measurements as JSON")
    args = parser.parse_args()

    if not shutil.which("docker"):
        print("docker is required (throwaway stack)", file=sys.stderr)
        return 2
    if not args.no_build:
        print("building the API with the test-support fixture route…", flush=True)
        run(
            ["cargo", "build", "-p", "api", "--bin", "api", "--features", "test-support"],
            cwd=str(BACKEND),
        )
    if not API_BIN.exists():
        print(f"missing API binary at {API_BIN}", file=sys.stderr)
        return 2

    modes = ["unsplit", "split"] if args.mode == "both" else [args.mode]
    measurements = [measure(mode, args) for mode in modes]
    report(measurements)
    if args.json_out:
        Path(args.json_out).write_text(
            json.dumps(
                [
                    {
                        "mode": m.mode,
                        "summary": m.summary,
                        "result": m.result,
                        "wall_s": m.wall_s,
                        "mapping_writes": m.mapping_writes,
                        "appends_logged": m.appends_logged,
                        "acquire_p50_ms": m.acquire_p50_ms,
                        "acquire_p95_ms": m.acquire_p95_ms,
                        "statement_p50_ms": m.statement_p50_ms,
                        "statement_p95_ms": m.statement_p95_ms,
                        "append_p50_ms": m.append_p50_ms,
                        "append_p95_ms": m.append_p95_ms,
                    }
                    for m in measurements
                ],
                indent=2,
            )
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
