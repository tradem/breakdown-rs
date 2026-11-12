#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)

"""Append-latency baseline for the pinned SierraDB image (issue #901).

Measures `EMAPPEND` latency over raw RESP3 — no client library, no redis-cli
(the `tqwewe/sierradb` image ships neither, and neither is installed on the dev
host). The numbers this script prints are the baseline recorded in
`docs/architecture/adrs/ADR-016-sierradb-runtime-and-round-trip.md` §6; a change
to the SierraDB pin, to the `sync.*` config, or to the deployment runtime is
supposed to be measured against them.

Usage (throwaway store, dev data untouched):

    docker run -d --rm --name bench-sierradb -p 19090:9090 \\
        tqwewe/sierradb:0.3.1 --dir /app/data

    scripts/bench-sierradb-append.py                       # full baseline
    scripts/bench-sierradb-append.py --case single         # one case only
    scripts/bench-sierradb-append.py --url redis://host:19090

Two pitfalls this script guards against (both make a wrong measurement easy):

1. **Strict versioning is on.** Omitting `EXPECTED_VERSION` answers
   `INVALIDARG strict versioning mode rejects EXPECTED_VERSION any` — a "0.2 ms
   append" is almost always that error reply. Every reply is therefore checked
   for the RESP3 map shape of a *successful* append before a sample is counted.
2. **Group commit hides the cost under load.** An isolated p50 alone overstates
   it, the parallel case alone hides it. The baseline reports both — and the
   idle-gap case explicitly, because that is where the commit tail lives.

Exit code is 0 when every case produced valid samples, 1 otherwise.
"""

from __future__ import annotations

import argparse
import math
import socket
import statistics
import sys
import threading
import time
import typing
import uuid

# --------------------------------------------------------------------------- #
# Minimal RESP3 client (only what an append/read round trip needs)
# --------------------------------------------------------------------------- #


class RespError(Exception):
    """A RESP error reply (`-ERR ...`)."""


class RespConnection:
    """Blocking RESP3 connection over a plain TCP socket."""

    def __init__(self, host: str, port: int) -> None:
        self._sock = socket.create_connection((host, port), timeout=30.0)
        self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self._buf = b""
        # RESP3 handshake. SierraDB answers `version` 3 only after HELLO 3.
        self.call("HELLO", "3")

    # -- wire ------------------------------------------------------------- #

    def _write_command(self, *args: str | bytes) -> None:
        out = [f"*{len(args)}\r\n".encode()]
        for arg in args:
            raw = arg.encode() if isinstance(arg, str) else arg
            out.append(f"${len(raw)}\r\n".encode())
            out.append(raw)
            out.append(b"\r\n")
        self._sock.sendall(b"".join(out))

    def _read_line(self) -> bytes:
        while b"\r\n" not in self._buf:
            chunk = self._sock.recv(65536)
            if not chunk:
                raise ConnectionError("connection closed while reading a line")
            self._buf += chunk
        line, _, self._buf = self._buf.partition(b"\r\n")
        return line

    def _read_exact(self, n: int) -> bytes:
        while len(self._buf) < n:
            chunk = self._sock.recv(max(65536, n - len(self._buf)))
            if not chunk:
                raise ConnectionError("connection closed while reading a payload")
            self._buf += chunk
        data, self._buf = self._buf[:n], self._buf[n:]
        return data

    def _read_reply(self) -> typing.Any:
        line = self._read_line()
        kind, body = line[:1], line[1:]
        if kind == b"+":
            return body.decode()
        if kind == b"-":
            raise RespError(body.decode())
        if kind == b":":
            return int(body)
        if kind == b",":
            return float(body)
        if kind == b"#":
            return body == b"t"
        if kind == b"_":
            return None
        if kind == b"$":
            length = int(body)
            if length < 0:
                return None
            data = self._read_exact(length + 2)[:-2]
            return data
        if kind == b"*":
            count = int(body)
            if count < 0:
                return None
            return [self._read_reply() for _ in range(count)]
        if kind == b"%":
            count = int(body)
            return {_hashable(self._read_reply()): self._read_reply() for _ in range(count)}
        if kind == b"~":
            count = int(body)
            return [self._read_reply() for _ in range(count)]
        if kind in (b"|",):
            # Attribute: read the attribute map, then the actual reply.
            count = int(body)
            for _ in range(count * 2):
                self._read_reply()
            return self._read_reply()
        raise RespError(f"unsupported RESP3 type {kind!r}")

    # -- api -------------------------------------------------------------- #

    def call(self, *args: str | bytes) -> typing.Any:
        self._write_command(*args)
        return self._read_reply()

    def emappend(self, partition_key: str, *, version: str, stream_id: str, event: str,
                 payload: bytes, events: int = 1, timestamp_ms: int | None = None) -> typing.Any:
        """One `EMAPPEND` carrying `events` events.

        `version` is the EXPECTED_VERSION of the *first* event; subsequent
        events of the same call step the version (strict versioning).
        """
        args: list[str | bytes] = ["EMAPPEND", partition_key]
        for i in range(events):
            args += [stream_id, event]
            if events == 1:
                args += ["EXPECTED_VERSION", version]
            elif i == 0:
                args += ["EXPECTED_VERSION", version]
            elif version == "EMPTY" and i > 0:
                args += ["EXPECTED_VERSION", str(i - 1)]
            else:
                args += ["EXPECTED_VERSION", str(int(version) + i)]
            if timestamp_ms is not None:
                args += ["TIMESTAMP", str(timestamp_ms)]
            if payload:
                args += ["PAYLOAD", payload]
        return self.call(*args)

    def close(self) -> None:
        try:
            self._sock.close()
        except OSError:
            pass


def _hashable(value: typing.Any) -> typing.Any:
    return tuple(value) if isinstance(value, list) else value


def parse_url(url: str) -> tuple[str, int]:
    host, _, port = url.removeprefix("redis://").partition(":")
    return host or "127.0.0.1", int(port or "9090")


# --------------------------------------------------------------------------- #
# Measurement
# --------------------------------------------------------------------------- #


def assert_append_reply(reply: typing.Any) -> None:
    """A successful append answers a RESP3 map; anything else is a hard error.

    Guards pitfall 1: an error reply is fast and would otherwise look like a
    great latency sample. SierraDB's map carries partition/offset/version keys.
    """
    if not isinstance(reply, dict):
        raise RespError(f"append reply is not a RESP3 map: {reply!r}")
    keys = {k.decode() if isinstance(k, bytes) else k for k in reply}
    missing = {"partition_key", "partition_id", "last_partition_sequence"} - keys
    if missing:
        raise RespError(f"append reply misses keys {sorted(missing)}: {sorted(keys)}")


def payload_bytes(size: int) -> bytes:
    """A realistic event payload of `size` bytes (one JSON-ish object)."""
    unit = b'"field":"0123456789abcdef",'
    body = unit * (size // len(unit) + 1)
    return b"{" + body[: max(size - 2, 0)] + b"}"


def percentile(samples: list[float], fraction: float) -> float:
    if not samples:
        return float("nan")
    ordered = sorted(samples)
    index = min(len(ordered) - 1, max(0, int(round(fraction * (len(ordered) - 1)))))
    return ordered[index]


def summarise(name: str, samples: list[float]) -> dict[str, float | str]:
    return {
        "case": name,
        "n": len(samples),
        "min": min(samples),
        "p50": percentile(samples, 0.50),
        "p95": percentile(samples, 0.95),
        "max": max(samples),
        "mean": statistics.fmean(samples),
    }


class Bench:
    def __init__(self, url: str, payload_size: int, warmup: int) -> None:
        self.host, self.port = parse_url(url)
        self.payload = payload_bytes(payload_size)
        self.warmup = warmup
        self.results: list[dict[str, float | str]] = []
        self.acks: list[tuple[float, float]] = []  # (ack_wall_time, duration)

    def _connect(self) -> RespConnection:
        return RespConnection(self.host, self.port)

    def isolated(self, name: str, *, iterations: int, events: int, gap_ms: float = 0.0) -> None:
        """Sequential appends, one stream each, `gap_ms` idle between them.

        This is the shape a UI write path has: one command, wait, next command.
        """
        conn = self._connect()
        partition = str(uuid.uuid7() if hasattr(uuid, "uuid7") else uuid.uuid4())
        samples: list[float] = []
        try:
            for i in range(self.warmup + iterations):
                stream = f"bench-{uuid.uuid4()}"
                if gap_ms:
                    time.sleep(gap_ms / 1000.0)
                start = time.perf_counter()
                reply = conn.emappend(partition, version="EMPTY", stream_id=stream,
                                      event="BenchEvent", payload=self.payload, events=events)
                duration = (time.perf_counter() - start) * 1000.0
                assert_append_reply(reply)
                if i >= self.warmup:
                    samples.append(duration)
                    self.acks.append((time.time() * 1000.0, duration))
        finally:
            conn.close()
        self.results.append(summarise(name, samples))

    def prefill(self, megabytes: float) -> None:
        """Write ~`megabytes` of events so the store is not fresh (data-volume case)."""
        chunk = 8
        payload = payload_bytes(256 * 1024)
        target_bytes = megabytes * 1024 * 1024
        written = 0.0
        conn = self._connect()
        partition = str(uuid.uuid4())
        try:
            while written < target_bytes:
                stream = f"prefill-{uuid.uuid4()}"
                reply = conn.emappend(partition, version="EMPTY", stream_id=stream,
                                      event="BenchEvent", payload=payload, events=chunk)
                assert_append_reply(reply)
                written += chunk * len(payload)
        finally:
            conn.close()
        print(f"prefilled {written / 1024 / 1024:.0f} MB of events")

    def sweep(self, gaps_ms: list[float], *, iterations: int) -> list[tuple[float, float]]:
        """Latency per idle gap — the inline-sync vs poll-wait branch.

        `sync_if_necessary()` syncs inline once `sync.interval_ms` has passed
        since the previous sync; inside that window the append instead waits for
        the next poll. A step in this curve names the branch and its threshold;
        a sawtooth would name a pure commit tick.
        """
        rows: list[tuple[float, float]] = []
        conn = self._connect()
        partition = str(uuid.uuid4())
        try:
            for gap in gaps_ms:
                samples: list[float] = []
                for _ in range(iterations):
                    stream = f"bench-{uuid.uuid4()}"
                    time.sleep(gap / 1000.0)
                    start = time.perf_counter()
                    reply = conn.emappend(partition, version="EMPTY", stream_id=stream,
                                          event="BenchEvent", payload=self.payload)
                    samples.append((time.perf_counter() - start) * 1000.0)
                    assert_append_reply(reply)
                rows.append((gap, percentile(samples, 0.50)))
        finally:
            conn.close()
        return rows

    def sustained(self, name: str, *, workers: int, seconds: float) -> None:
        """Continuous appends on `workers` connections — sustained throughput.

        The burst case hides a config's batching efficiency; this measures
        appends/s end to end (write + data fsync + confirmation fsyncs).
        """
        counts = [0] * workers
        errors: list[BaseException] = []
        deadline = time.monotonic() + seconds
        conns = [self._connect() for _ in range(workers)]
        partition = str(uuid.uuid4())

        def worker(index: int, conn: RespConnection) -> None:
            try:
                while time.monotonic() < deadline:
                    assert_append_reply(
                        conn.emappend(partition, version="EMPTY",
                                      stream_id=f"bench-{uuid.uuid4()}",
                                      event="BenchEvent", payload=self.payload)
                    )
                    counts[index] += 1
            except BaseException as exc:  # noqa: BLE001 - reported below
                errors.append(exc)

        threads = [threading.Thread(target=worker, args=(i, c)) for i, c in enumerate(conns)]
        start = time.monotonic()
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        elapsed = time.monotonic() - start
        for conn in conns:
            conn.close()
        if errors:
            raise errors[0]
        total = sum(counts)
        self.results.append({
            "case": f"{name} ({workers} connections, {seconds:.0f}s)",
            "n": total,
            "min": 0.0,
            "p50": 0.0,
            "p95": 0.0,
            "max": 0.0,
            "mean": 0.0,
            "appends_per_s": total / elapsed,
        })

    def parallel(self, name: str, *, appends: int, rounds: int) -> None:
        """`appends` appends on separate connections, all in flight at once.

        Wall time for the whole burst is the number that matters: it shows how
        much of the per-append cost is group-commit absorbable.
        """
        walls: list[float] = []
        for _ in range(self.warmup + rounds):
            barrier = threading.Barrier(appends)
            conns = [self._connect() for _ in range(appends)]
            partition = str(uuid.uuid4())
            errors: list[BaseException] = []

            def worker(conn: RespConnection) -> None:
                try:
                    stream = f"bench-{uuid.uuid4()}"
                    barrier.wait()
                    assert_append_reply(
                        conn.emappend(partition, version="EMPTY", stream_id=stream,
                                      event="BenchEvent", payload=self.payload)
                    )
                except BaseException as exc:  # noqa: BLE001 - reported below
                    errors.append(exc)

            threads = [threading.Thread(target=worker, args=(c,)) for c in conns]
            start = time.perf_counter()
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join()
            wall = (time.perf_counter() - start) * 1000.0
            for conn in conns:
                conn.close()
            if errors:
                raise errors[0]
            walls.append(wall)
        # Report per-append-equivalent alongside the burst wall time.
        summary = summarise(f"{name} (wall of {appends} in flight)", walls)
        summary["per_append"] = float(summary["p50"]) / appends
        self.results.append(summary)


def periodicity(acks: list[tuple[float, float]]) -> None:
    """Test the commit-tick hypothesis (issue #901 question 1).

    Two independent reads, because a wall-clock phase (`ack mod 50`) alone is
    worthless: a tick anchored at process start has an arbitrary offset, so a
    uniform `mod 50` histogram proves nothing. What does prove it:

    * **Inter-ack spacing.** If every ack is emitted by the same periodic sync
      poll, consecutive acks sit one cycle apart — a hard cap of `1 / cycle`
      appends per second for a single sequential client.
    * **Circular concentration.** `ack mod cycle` has a mean resultant length
      `R` near 1 when acks sit on one grid position and near 0 when uniform —
      *whatever* the offset is. `R` is offset-free, so it is the honest form of
      the phase test.
    """
    if len(acks) < 20:
        print("\nperiodicity: too few samples")
        return
    times = [t for t, _ in acks]
    deltas = sorted(b - a for a, b in zip(times, times[1:]))
    median_gap = deltas[len(deltas) // 2]
    slow = sum(1 for _, d in acks if d >= 10.0)
    print(f"\nperiodicity ({len(acks)} sequential appends, {slow} of them >= 10 ms):")
    rate = 1000.0 / median_gap if median_gap > 0 else float("inf")
    print(f"  inter-ack spacing: median {median_gap:.2f} ms -> ~{rate:.1f} appends/s")
    for cycle in (50.0, 25.0, 100.0):
        value = _resultant_length([t % cycle / cycle * math.tau for t in times])
        verdict = "grid-locked" if value > 0.5 else "uniform (no fixed tick)"
        print(f"  cycle {cycle:5.0f} ms: circular concentration R={value:.2f}  {verdict}")


def _resultant_length(angles: list[float]) -> float:
    """Mean resultant length of a circular sample: 0 uniform, 1 perfectly on grid."""
    if not angles:
        return 0.0
    x = sum(math.cos(a) for a in angles) / len(angles)
    y = sum(math.sin(a) for a in angles) / len(angles)
    return math.hypot(x, y)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--url", default="redis://127.0.0.1:19090")
    parser.add_argument("--iterations", type=int, default=300)
    parser.add_argument("--parallel-rounds", type=int, default=20)
    parser.add_argument("--payload", type=int, default=1024, help="payload bytes per event")
    parser.add_argument("--warmup", type=int, default=20)
    parser.add_argument("--gap-ms", type=float, default=100.0,
                        help="idle gap before each isolated append (default 100 = fully idle)")
    parser.add_argument("--case", default="all",
                        choices=["all", "single", "multi", "parallel", "warm", "sweep",
                                 "sustained"])
    parser.add_argument("--sustain-seconds", type=float, default=5.0,
                        help="duration of the sustained-throughput case")
    parser.add_argument("--prefill-mb", type=float, default=0.0,
                        help="write this much event data before measuring (data-volume case)")
    parser.add_argument("--json", action="store_true", help="emit the summary as JSON")
    parser.add_argument("--label", default="", help="free-form label printed with the report")
    args = parser.parse_args(argv)

    bench = Bench(args.url, args.payload, args.warmup)
    sweep: list[tuple[float, float]] = []
    try:
        if args.prefill_mb > 0:
            bench.prefill(args.prefill_mb)
        if args.case in ("all", "sweep"):
            sweep_gaps = [0.0, 2.0, 4.0, 6.0, 8.0, 10.0, 20.0, 40.0]
            sweep_iterations = max(10, args.iterations // 10)
        if args.case in ("all", "single"):
            bench.isolated("1 event, isolated (new stream, EXPECTED_VERSION EMPTY)",
                           iterations=args.iterations, events=1, gap_ms=args.gap_ms)
        if args.case in ("all", "multi"):
            bench.isolated("5 events", iterations=args.iterations, events=5, gap_ms=args.gap_ms)
            bench.isolated("20 events", iterations=args.iterations, events=20, gap_ms=args.gap_ms)
        if args.case in ("all", "warm"):
            bench.isolated("1 event, no idle gap (warm stream of appends)",
                           iterations=args.iterations, events=1, gap_ms=0.0)
        if args.case in ("all", "parallel"):
            bench.parallel("8 appends", appends=8, rounds=args.parallel_rounds)
            bench.parallel("16 appends", appends=16, rounds=args.parallel_rounds)
        if args.case in ("all", "sustained"):
            bench.sustained("sustained", workers=8, seconds=args.sustain_seconds)
        if args.case in ("all", "sweep"):
            sweep = bench.sweep(sweep_gaps, iterations=sweep_iterations)
    except (RespError, ConnectionError, OSError) as exc:
        print(f"FATAL: {exc}", file=sys.stderr)
        return 1

    if args.json:
        import json
        print(json.dumps({"label": args.label, "results": bench.results}, indent=2))
        return 0

    header = f"SierraDB append baseline ({args.url}, payload {args.payload} B"
    header += f", {args.iterations} samples/case" if args.iterations else ""
    print()
    print(header + ")")
    print(f"{'case':60s} {'n':>5s} {'min':>7s} {'p50':>7s} {'p95':>7s} {'max':>8s}")
    for row in bench.results:
        if "appends_per_s" in row:
            print(f"{str(row['case'])[:60]:60s} {row['n']:5d} {'':7s} {'':7s} {'':7s} {'':8s}"
                  f"  {row['appends_per_s']:7.1f} appends/s")
            continue
        print(f"{str(row['case'])[:60]:60s} {row['n']:5d} "
              f"{row['min']:7.2f} {row['p50']:7.2f} {row['p95']:7.2f} {row['max']:8.2f}")
        if "per_append" in row:
            print(f"{'  -> per append in the burst':60s} {'':5s} {'':7s} "
                  f"{row['per_append']:7.2f}")
    if sweep:
        print("\nidle-gap sweep (p50 latency for a given gap before the append):")
        for gap, p50 in sweep:
            print(f"  gap {gap:5.1f} ms -> p50 {p50:7.2f} ms")
    periodicity(bench.acks)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
