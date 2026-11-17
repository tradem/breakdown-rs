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
import http.server
import importlib.util
import socket
import sys
import tempfile
import threading
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
    """A foreign listener on `port` — the "a dev API is already there" case.

    The backlog is deliberately deep: every `port_open` probe completes a
    handshake into the accept queue and is never `accept()`ed, so a backlog of 1
    stops accepting after the first probe and the port then reads as closed —
    which would make the wait-for-release control assertion vacuous.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.listen(128)
    return sock


def api_process(port, log_path):
    return bench.ApiProcess(stack=StubStack(), mode="split", log_path=log_path, port=port)


class ScriptedChild:
    """A spawned child whose `poll()` answers a script (None = still alive).

    One entry per call, ending in a permanent exit state — that is how the
    "died between the liveness check and the connect" window is reproduced
    deterministically.
    """

    returncode = 1

    def __init__(self, script):
        self.script = list(script)

    def poll(self):
        return self.script.pop(0) if len(self.script) > 1 else self.script[0]

    def wait(self, timeout=None):  # noqa: ARG002, ANN001
        return self.poll()

    def send_signal(self, _sig):
        pass

    def kill(self):
        pass


def dead_child():
    """A child that exited before anything was asked of it."""
    return ScriptedChild([1])


def with_child(api, child):
    """Pretend `start()` spawned `child`."""
    api.proc = child
    return api


MARKER = "\U0001f680 Breakdown RS listening on 127.0.0.1:{port}"


class _ReusableServer(http.server.ThreadingHTTPServer):
    # A released listener port has no TIME_WAIT, but allow an immediate rebind so
    # the "stranger takes the port" leg is deterministic.
    allow_reuse_address = True
    # One thread per connection (an HTTP/1.1 keep-alive connection would otherwise
    # block the single-threaded accept loop forever) and daemonic, so a stuck
    # connection cannot keep the test process alive.
    daemon_threads = True

    def __init__(self, *args, **kwargs):  # noqa: ANN002, ANN003
        self.connections = []
        super().__init__(*args, **kwargs)

    def process_request(self, request, client_address):  # noqa: ANN001
        # Remembered so `stop()` can abort them: a killed API closes its sockets,
        # and a merely *shut down* listener would keep serving the old connection.
        self.connections.append(request)
        super().process_request(request, client_address)


class RecordingServer:
    """A real HTTP server standing in for an API — ours, or a stranger.

    Real sockets, not a stub: the question the test answers is whether a mutation
    can physically reach a server that is not this run's child.
    """

    def __init__(self, port=0):
        outer = self
        self.requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            # HTTP/1.1 + keep-alive, like axum: the run's requests travel on ONE
            # connection, and an HTTP/1.0 handler would close it after every
            # response (which the connection guard would then correctly refuse).
            protocol_version = "HTTP/1.1"

            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("content-length") or 0)
                outer.requests.append((self.command, self.path, self.rfile.read(length)))
                payload = b'{"entries": {}}'
                self.send_response(200)
                self.send_header("content-type", "application/json")
                self.send_header("content-length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            do_GET = do_POST

            def log_message(self, *args):  # noqa: ANN002, ANN401
                pass

        self.server = _ReusableServer(("127.0.0.1", port), Handler)
        self.port = self.server.server_address[1]
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def stop(self):
        # Abort every accepted connection first: a closed listener alone would
        # leave an open keep-alive connection answering, which is not what "the
        # child died" looks like.
        for connection in list(self.server.connections):
            try:
                connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                connection.close()
            except OSError:
                pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


def test_a_foreign_api_receives_no_mutation():
    """The check→connect window: a stranger on the released port gets nothing."""
    child = RecordingServer()          # stands in for this run's child
    stranger = None
    try:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "bench.log"
            log_path.write_text(MARKER.format(port=child.port) + "\n")
            # The child LIES about being alive after we kill it, so `assert_alive`
            # cannot be what saves us: only the connection can.
            api = with_child(api_process(child.port, log_path), ScriptedChild([None]))
            api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            check(
                "the run's own child receives the mutation",
                len(child.requests) == 1,
                repr(child.requests),
            )

            # The child dies; a stranger binds the released port.
            child.stop()
            stranger = RecordingServer(child.port)
            check(
                "the stranger really does hold the same port",
                stranger.port == child.port,
                f"{stranger.port} != {child.port}",
            )

            raised = None
            try:
                api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            except RuntimeError as err:
                raised = str(err)
            check(
                "the call aborts instead of reconnecting",
                raised is not None
                and ("refusing to reconnect" in raised or "is gone" in raised),
                repr(raised),
            )
            check(
                "the foreign API receives no mutation",
                stranger.requests == [],
                repr(stranger.requests),
            )
            check(
                "the child received exactly the one mutation it served",
                len(child.requests) == 1,
                repr(child.requests),
            )
    finally:
        child.stop()
        if stranger is not None:
            stranger.stop()


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


def test_stop_after_a_lost_bind_race_does_not_wait():
    port = free_port()
    foreign = listening_socket(port)
    bench.PORT_RELEASE_GRACE_S = 1
    try:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "bench.log"
            # The child was spawned but never bound: no bind announcement.
            log_path.write_text("ERROR breakdown_api: Address already in use\n")
            api = with_child(api_process(port, log_path), dead_child())
            started = time.monotonic()
            api.stop()
            elapsed = time.monotonic() - started
            check(
                "stop() after a lost bind race returns at once",
                elapsed < 2,
                f"{elapsed:.1f}s",
            )

            # A child that DID announce the port gets the short kernel grace — it
            # must not return instantly — and then reports the foreign listener
            # instead of waiting on it.
            log_path.write_text(MARKER.format(port=port) + "\n")
            api = with_child(api_process(port, log_path), dead_child())
            started = time.monotonic()
            api.stop()
            elapsed = time.monotonic() - started
            check(
                "stop() gives the kernel a grace when the child owned the port",
                elapsed >= 1,
                f"{elapsed:.1f}s",
            )
            check(
                "stop() does not blame a foreign listener for the release",
                elapsed < 5,
                f"{elapsed:.1f}s",
            )
    finally:
        foreign.close()


def test_a_dead_child_blocks_further_requests():
    port = free_port()
    with tempfile.TemporaryDirectory() as tmp:
        log_path = Path(tmp) / "bench.log"
        # Ownership at boot time is not ownership now: the child exited, so the
        # port may belong to a stranger by the next request.
        log_path.write_text(
            "INFO breakdown_api: booting\n" + MARKER.format(port=port) + "\n"
        )
        api = with_child(api_process(port, log_path), dead_child())
        raised = None
        try:
            api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
        except RuntimeError as err:
            raised = str(err)
        check(
            "a request after the child exited is refused, not sent",
            raised is not None and "no longer ours" in raised,
            repr(raised),
        )




print("bench-apply-attribution startup guards")
test_occupied_port_is_refused_before_spawn()
test_readiness_requires_ownership()
test_stop_after_a_lost_bind_race_does_not_wait()
test_a_dead_child_blocks_further_requests()
test_a_foreign_api_receives_no_mutation()

if FAILURES:
    print(f"\n{len(FAILURES)} check(s) failed: {', '.join(FAILURES)}")
    sys.exit(1)
print("\nall checks passed")
PY
