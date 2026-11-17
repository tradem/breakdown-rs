#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Startup-race guard for `scripts/bench-apply-attribution.py` (issue #900 M4).
#
# The benchmark drives real `POST /v1/...` mutations, so it must never talk to a
# server it did not start. Three contracts are pinned here, all daemon-free — no
# docker, no Postgres, no SierraDB, no compiled API binary, only bash + python3:
#
#   1. an already-occupied `--api-port` is refused BEFORE the child is spawned
#      (so nothing is measured against a dev API);
#   2. readiness needs endpoint OWNERSHIP, not liveness: a healthy `/v1/health`
#      answer without the child's own bind announcement is not enough;
#   3. `stop()` on a run that never started returns immediately instead of
#      waiting out the port-release timeout on the foreign listener (which would
#      mask the original error and skip the stack cleanup).
#
# Run from `backend/`: `bash scripts/tests/bench-apply-attribution-test.sh`.

set -euo pipefail

cd "$(dirname "$0")/.."   # backend/scripts

python3 - <<'PY'
import importlib.util
import socket
import sys
import tempfile
import time
from pathlib import Path

SCRIPT = Path("bench-apply-attribution.py").resolve()
spec = importlib.util.spec_from_file_location("bench_apply_attribution", SCRIPT)
bench = importlib.util.module_from_spec(spec)
# `dataclasses` resolves `cls.__module__` through `sys.modules`, so the module has
# to be registered before its body runs.
sys.modules[spec.name] = bench
spec.loader.exec_module(bench)

FAILURES = []


def check(name, condition, detail=""):
    if condition:
        print(f"  ok   {name}")
    else:
        FAILURES.append(name)
        print(f"  FAIL {name}{(': ' + detail) if detail else ''}")


class StubStack:
    """Only the two URLs `ApiProcess` reads; no containers are ever started."""

    database_url = "postgres://stub/none"
    sierradb_url = "redis://stub/none"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def listening_socket(port):
    """A foreign listener on `port` — the "a dev API is already there" case."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.listen(1)
    return sock


def api_process(port, log_path):
    return bench.ApiProcess(
        stack=StubStack(),
        mode="split",
        log_path=log_path,
        base_url=f"http://127.0.0.1:{port}",
        port=port,
    )


def test_occupied_port_is_refused_before_spawn():
    port = free_port()
    foreign = listening_socket(port)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            api = api_process(port, Path(tmp) / "bench.log")
            raised = None
            try:
                api.start()
            except RuntimeError as err:
                raised = str(err)
            check(
                "an occupied --api-port is refused",
                raised is not None and "already in use" in raised,
                repr(raised),
            )
            check(
                "no child process was spawned",
                api.proc is None,
            )
            # Contract 3: cleanup after a refused start must not wait for the
            # FOREIGN listener to release the port.
            started = time.monotonic()
            api.stop()
            elapsed = time.monotonic() - started
            check(
                "stop() after a refused start returns at once",
                elapsed < 5,
                f"{elapsed:.1f}s",
            )
    finally:
        foreign.close()


def test_readiness_requires_ownership():
    port = free_port()
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "bench.log"
        api = api_process(port, log_path)

        # A server answers /v1/health, but it is not this child: its log carries
        # no bind announcement. Liveness alone must not pass the gate.
        log_path.write_text(
            "INFO breakdown_api: booting\nANSI-stripped lines only, no listener yet\n"
        )
        api.healthy = lambda: True
        check(
            "a healthy endpoint without the child's bind line is not ready",
            api.owns_endpoint() is False and api.ready() is False,
        )

        # The child's own announcement (colour codes and all) proves ownership.
        log_path.write_text(
            "INFO breakdown_api: booting\n"
            f"\x1b[32mINFO\x1b[0m \U0001f680 Breakdown RS listening on 127.0.0.1:{port}\n"
        )
        check(
            "the child's own bind announcement proves ownership",
            api.owns_endpoint() is True and api.ready() is True,
        )

        # A bind announcement for a DIFFERENT port belongs to someone else.
        api_other = api_process(port + 1, log_path)
        api_other.healthy = lambda: True
        check(
            "another port's announcement does not prove ownership",
            api_other.owns_endpoint() is False and api_other.ready() is False,
        )

        # An unhealthy child is not ready even when it owns the socket.
        api_other = api_process(port, log_path)
        api_other.healthy = lambda: False
        check(
            "health still gates readiness",
            api_other.ready() is False,
        )


print("bench-apply-attribution startup guards")
test_occupied_port_is_refused_before_spawn()
test_readiness_requires_ownership()

if FAILURES:
    print(f"\n{len(FAILURES)} check(s) failed: {', '.join(FAILURES)}")
    sys.exit(1)
print("\nall checks passed")
PY
