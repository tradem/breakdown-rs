#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Endpoint-ownership guards for `scripts/bench-apply-attribution.py` (issue #900 M4).
#
# The benchmark drives real `POST /v1/...` mutations, so it must never write into a
# server it did not start. Daemon-free — no docker, no Postgres, no SierraDB, no
# compiled API binary; only bash + python3 (stdlib) and a tiny `python3 -c` child
# that stands in for the API process. Pinned here:
#
#   1. an already-occupied `--api-port` is refused BEFORE the child is spawned;
#   2. ownership is LIVE: the child must hold the LISTEN socket for the port right
#      now (`/proc`), because a live process can already have released it (the
#      shutdown sequence after `axum::serve` returns) and because the bind
#      announcement is history;
#   3. the run writes on ONE keep-alive connection, opened under that ownership, so
#      a later child death cannot route a mutation to whoever binds the port next —
#      and connection loss is terminal (a reconnect would be that window);
#   4. `stop()` never waits on, or blames, a listener that cannot be the child's.
#
# Run from `backend/`: `bash scripts/tests/bench-apply-attribution-test.sh`.

set -euo pipefail

cd "$(dirname "$0")/.."   # backend/scripts

python3 - <<'PY'
import contextlib
import http.server
import importlib.util
import io
import json
import os
import queue
import socket
import subprocess
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


MARKER = "\U0001f680 Breakdown RS listening on 127.0.0.1:{port}"


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def listening_socket(port):
    """A foreign listener on `port` — the "a dev API is already there" case.

    The backlog is deliberately deep: every `port_open` probe completes a
    handshake into the accept queue and is never `accept()`ed, so a backlog of 1
    stops accepting after the first probe and the port then reads as closed.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("127.0.0.1", port))
    sock.listen(128)
    return sock


def api_process(port, log_path):
    return bench.ApiProcess(stack=StubStack(), mode="split", log_path=log_path, port=port)


# --- a real stand-in for the API child -------------------------------------
#
# A subprocess, not a stub: `/proc` ownership can only be observed on a real
# process, and the point of these tests is that the *socket* decides, not a flag.
# It serves `/v1/health` plus a JSONL sink of received requests, and takes commands
# on stdin — acknowledged on stdout, so the test never waits a fixed delay:
#
#   `release-listener` → abort the connections, drop the listener, keep running
#                        (the shutdown window in `main.rs`), answer `released`
#   `drop-connections` → abort the connections only (a keep-alive loss), answer
#                        `dropped`

CHILD_PROGRAM = r'''
import http.server, json, socket, sys, threading, time

port = int(sys.argv[1])
sink = sys.argv[2]
lock = threading.Lock()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def handle_any(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        with lock, open(sink, "a") as fh:
            fh.write(json.dumps({"method": self.command, "path": self.path,
                                 "body": body.decode("utf-8", "replace")}) + "\n")
        if self.path == "/v1/health":
            payload = json.dumps({"entries": {"postgres": {"status": "Healthy"},
                                              "sierradb": {"status": "Healthy"}}}).encode()
        else:
            payload = b"{}"
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = handle_any
    do_POST = handle_any


class Server(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def process_request(self, request, client_address):
        self.connections.append(request)
        super().process_request(request, client_address)


server = Server(("127.0.0.1", port), Handler)
server.connections = []
threading.Thread(target=server.serve_forever, daemon=True).start()
print("ready", flush=True)


def drop_connections():
    for connection in list(server.connections):
        try:
            connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            connection.close()
        except OSError:
            pass


for line in sys.stdin:
    command = line.strip()
    if command == "drop-connections":
        drop_connections()
        # Only now is the client's socket closed at the source of truth.
        print("dropped", flush=True)
    elif command == "release-listener":
        # The shutdown window: connections gone, listener dropped, process alive.
        drop_connections()
        server.server_close()
        threading.Thread(target=server.shutdown, daemon=True).start()
        print("released", flush=True)
    elif command == "quit":
        break
'''


def spawn_child(directory):
    """Start the stand-in child; returns (proc, port, sink path)."""
    port = free_port()
    sink = Path(directory) / "child-requests.jsonl"
    sink.touch()
    proc = subprocess.Popen(  # noqa: S603
        [sys.executable, "-c", CHILD_PROGRAM, str(port), str(sink)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    # A reader thread, so `await_token` never depends on how the pipe buffers
    # lines (a `select` on the fd would miss a line already read into Python's
    # buffer) and never needs a sleep.
    proc.lines = queue.Queue()
    threading.Thread(
        target=lambda: [proc.lines.put(line) for line in proc.stdout], daemon=True
    ).start()
    await_token(proc, "ready")
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and not bench.port_open(port):
        time.sleep(0.02)
    return proc, port, sink


def await_token(proc, token, timeout=20.0):
    """Block until the stand-in child prints `token` — no fixed delays anywhere."""
    while True:
        try:
            line = proc.lines.get(timeout=timeout)
        except queue.Empty:
            raise RuntimeError(f"the stand-in child never answered {token!r}") from None
        if line.strip() == token:
            return


def child_command(proc, command, acknowledgement):
    """Ask the child to do something and wait for its acknowledgement."""
    proc.stdin.write(command + "\n")
    proc.stdin.flush()
    await_token(proc, acknowledgement)


def child_requests(sink):
    if not sink.exists():
        return []
    return [json.loads(line) for line in sink.read_text().splitlines() if line.strip()]


def api_for_child(proc, port, log_path):
    api = api_process(port, log_path)
    api.proc = proc
    return api


def wait_until(predicate, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.02)
    return False


# --- a real foreign HTTP server -------------------------------------------


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
        self.connections.append(request)
        super().process_request(request, client_address)


class RecordingServer:
    """A real HTTP server standing in for a stranger that grabs the port."""

    def __init__(self, port=0):
        outer = self
        self.requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
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
        for connection in list(self.server.connections):
            for close in (lambda: connection.shutdown(socket.SHUT_RDWR), connection.close):
                try:
                    close()
                except OSError:
                    pass
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)


# --- the scripts' own stubs (for the stop() paths, which need no process) ---


class ScriptedChild:
    """A spawned child whose `poll()` answers a script (None = still alive)."""

    returncode = 1
    pid = None

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
    return ScriptedChild([1])


# --- tests ----------------------------------------------------------------


class _ForbiddingWait:
    """Stand-in for `bench.wait_for` that fails the instant it is called.

    A timestamp comparison (`elapsed < 5`) would pass or fail depending on how the
    runner schedules the process — the property under test is *"this path never
    waits"*, which is exactly what a forbidden call observes.
    """

    def __init__(self):
        self.called = False

    def __call__(self, *args, **kwargs):  # noqa: ANN002, ANN003, ANN401
        self.called = True
        raise AssertionError(f"wait_for must not be called here: args={args[1:]!r}")


def without_waiting(action):
    """Run `action` with `bench.wait_for` forbidden; restore it either way."""
    original = bench.wait_for
    stub = _ForbiddingWait()
    bench.wait_for = stub
    try:
        action()
    finally:
        bench.wait_for = original
    return stub


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
            check("no child process was spawned", api.proc is None)

            # Cleanup must not wait for the FOREIGN listener to release the port.
            stub = without_waiting(api.stop)
            check("stop() after a refused start does not wait", stub.called is False)
    finally:
        foreign.close()


def test_stop_after_a_lost_bind_race_does_not_wait():
    port = free_port()
    foreign = listening_socket(port)
    original_port_open = bench.port_open
    bench.PORT_RELEASE_GRACE_S = 0.3
    try:
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "bench.log"
            # Spawned child, but no bind announcement: it lost the race.
            log_path.write_text("ERROR breakdown_api: Address already in use" + chr(10))
            api = api_process(port, log_path)
            api.proc = dead_child()
            stub = without_waiting(api.stop)
            check("stop() after a lost bind race does not wait", stub.called is False)

            # The child DID announce the port: `stop()` gives the kernel a grace
            # instead of waiting on — or blaming — a listener that cannot be ours.
            # No wall clock: the port answers the probes from a scripted list, so
            # the sequence is the same however the runner schedules the process.
            log_path.write_text(MARKER.format(port=port) + chr(10))

            # (a) the port is gone on the second probe → return silently, and the
            #     probe count is exact, not "at least".
            answers = [True, False]
            probes = []
            bench.port_open = lambda p: (probes.append(p), answers.pop(0))[1]
            api = api_process(port, log_path)
            api.proc = dead_child()
            captured = io.StringIO()
            stub = _ForbiddingWait()
            original_wait = bench.wait_for
            bench.wait_for = stub
            try:
                with contextlib.redirect_stdout(captured):
                    api.stop()
            finally:
                bench.wait_for = original_wait
            check(
                "stop() stops probing as soon as the port is released",
                len(probes) == 2,
                f"{len(probes)} probe(s)",
            )
            check(
                "stop() does not warn when the port was released",
                "still open after the child exited" not in captured.getvalue(),
                captured.getvalue().strip(),
            )
            check("stop() does not wait in that case either", stub.called is False)

            # (b) the port stays open → exactly one warning, still no wait.
            probes = []
            bench.port_open = lambda p: (probes.append(p), True)[1]
            api = api_process(port, log_path)
            api.proc = dead_child()
            captured = io.StringIO()
            stub = _ForbiddingWait()
            bench.wait_for = stub
            try:
                with contextlib.redirect_stdout(captured):
                    api.stop()
            finally:
                bench.wait_for = original_wait
            check(
                "stop() probes the port at least once before giving up",
                len(probes) >= 1,
                f"{len(probes)} probe(s)",
            )
            check(
                "stop() reports a listener that is not the child's",
                "still open after the child exited" in captured.getvalue(),
                captured.getvalue().strip(),
            )
            check("stop() still does not wait on a foreign listener", stub.called is False)
    finally:
        bench.port_open = original_port_open
        bench.PORT_RELEASE_GRACE_S = 5
        foreign.close()


def test_ownership_is_live_not_historical():
    with tempfile.TemporaryDirectory() as tmp:
        proc, port, sink = spawn_child(tmp)
        stranger = None
        try:
            log_path = Path(tmp) / "bench.log"
            log_path.write_text(MARKER.format(port=port) + "\n")
            api = api_for_child(proc, port, log_path)

            check("the child holds the LISTEN socket", api.holds_listener() is True)
            check("readiness is gated on that ownership", api.ready() is True)

            status, _ = api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            check("the child serves the run's mutation", status == 200, str(status))
            mutations = [r for r in child_requests(sink) if r["path"] != "/v1/health"]
            check(
                "the child received exactly that one mutation",
                len(mutations) == 1 and mutations[0]["method"] == "POST",
                repr(mutations),
            )

            # The shutdown window: listener dropped, process still alive. The child
            # acknowledges, so nothing here depends on a delay.
            child_command(proc, "release-listener", "released")
            check(
                "the child released its listener",
                wait_until(lambda: not api.holds_listener()),
            )
            check(
                "the child process is still alive (liveness is not ownership)",
                proc.poll() is None,
            )
            check("the historical bind announcement still says it bound", api.owns_endpoint())
            check(
                "readiness stops being true once the listener is gone",
                api.ready() is False,
            )

            # A closed listening socket is retired by the kernel a moment later,
            # so wait for the PORT — that is what the stranger must be able to bind,
            # and asserting it keeps the "receives no mutation" check honest.
            check(
                "the port becomes bindable again",
                wait_until(lambda: not bench.port_open(port)),
            )

            # A stranger binds the released port.
            stranger = RecordingServer(port)
            check(
                "the stranger really does hold the same port",
                stranger.port == port,
                f"{stranger.port} != {port}",
            )

            raised = None
            try:
                api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            except RuntimeError as err:
                raised = str(err)
            check(
                "a call without the listener is refused",
                raised is not None and "no longer holds the listening socket" in raised,
                repr(raised),
            )
            check(
                "the foreign API receives no mutation",
                stranger.requests == [],
                repr(stranger.requests),
            )
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=10)
            if stranger is not None:
                stranger.stop()


def test_a_foreign_api_receives_no_mutation():
    with tempfile.TemporaryDirectory() as tmp:
        proc, port, sink = spawn_child(tmp)
        stranger = None
        try:
            log_path = Path(tmp) / "bench.log"
            log_path.write_text(MARKER.format(port=port) + "\n")
            api = api_for_child(proc, port, log_path)
            api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})

            # The child dies; a stranger binds the released port.
            proc.kill()
            proc.wait(timeout=10)
            stranger = RecordingServer(port)
            check(
                "the stranger really does hold the same port",
                stranger.port == port,
                f"{stranger.port} != {port}",
            )

            raised = None
            try:
                api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            except RuntimeError as err:
                raised = str(err)
            check(
                "the call aborts on the dead child",
                raised is not None and "is no longer ours" in raised,
                repr(raised),
            )
            check(
                "the foreign API receives no mutation",
                stranger.requests == [],
                repr(stranger.requests),
            )
            check(
                "the child received exactly the one mutation it served",
                len(child_requests(sink)) == 1,
                repr(child_requests(sink)),
            )
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=10)
            if stranger is not None:
                stranger.stop()


def test_connection_loss_is_terminal():
    with tempfile.TemporaryDirectory() as tmp:
        proc, port, sink = spawn_child(tmp)
        try:
            log_path = Path(tmp) / "bench.log"
            log_path.write_text(MARKER.format(port=port) + "\n")
            api = api_for_child(proc, port, log_path)
            api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            served = len([r for r in child_requests(sink) if r["path"] != "/v1/health"])

            # The child drops the connections but keeps the listener: a keep-alive
            # timeout, i.e. a lost connection WITHOUT a lost port. Acknowledged, so
            # the next request cannot race the close.
            child_command(proc, "drop-connections", "dropped")
            raised = None
            try:
                api.call("POST", "/v1/seasons", {"project_id": "x", "number": 1})
            except RuntimeError as err:
                raised = str(err)
            check(
                "a lost connection aborts the call",
                raised is not None and "refusing to reconnect" in raised,
                repr(raised),
            )
            check("the loss is recorded as terminal", isinstance(api.connection_lost, str))

            # Readiness must not paper over it by reconnecting.
            raised = None
            try:
                excluded = api.ready()
            except RuntimeError as err:
                raised = str(err)
                excluded = None
            check(
                "readiness raises instead of reconnecting",
                raised is not None and "refusing to reconnect" in raised,
                f"raised={raised!r} ready={excluded!r}",
            )
            after = [r for r in child_requests(sink) if r["path"] != "/v1/health"]
            check(
                "no further mutation reached the child",
                len(after) == served,
                repr(after),
            )
        finally:
            if proc.poll() is None:
                proc.kill()
            proc.wait(timeout=10)


print("bench-apply-attribution endpoint-ownership guards")
test_occupied_port_is_refused_before_spawn()
test_stop_after_a_lost_bind_race_does_not_wait()
test_ownership_is_live_not_historical()
test_a_foreign_api_receives_no_mutation()
test_connection_loss_is_terminal()

if FAILURES:
    print(f"\n{len(FAILURES)} check(s) failed: {', '.join(FAILURES)}")
    sys.exit(1)
print("\nall checks passed")
PY
