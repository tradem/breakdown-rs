#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0
# Copyright (C) 2024-2026 Breakdown RS Contributors
# Co-authored-by: deepseek-v4.1-flash (opencode-go)
#
# Backend memory profiler for a low-RAM dev machine (AGENTS.md §8, issue #631).
#
# Why this exists: on the 15 GB dev box `systemd-oomd` has killed the *whole*
# terminal cgroup four times (2026-11-05 05:45, 2026-11-11 11:17 / 11:56 /
# 12:46, peaks 9.4-11.5 GB) because a foreground `cargo run --bin api` shares
# one cgroup with the shell, the build and the editor — so the terminal dies
# with the backend. `scripts/oomd` drop-in fixes the trigger; this script makes
# the cause measurable.
#
# Two things happen at once:
#   1. the API runs in its **own** systemd user scope (its death can no longer
#      take the terminal with it) with MemoryHigh/MemoryMax as a safety net;
#   2. that cgroup is sampled into CSV, so a *sporadic* 3-9 GB allocation can
#      be found even when nobody is watching the moment it happens.
#
# The single most important column is `anon` (heap: real retention) versus
# `file` (page cache: looks like GBs of "memory", is harmless and reclaimable).
# A build's leftover cache therefore cannot be mistaken for a leak. On a zram
# machine also read `anon+swap`: swapped-out pages leave `anon` (measured: a
# 300 MiB allocation showing as 77 MiB anon + 226 MiB swap).
#
# Caveat: sampling starts once the scope's cgroup exists (~0.2 s), so
# allocations from the earliest startup instant already show up in the first
# sample. `memory.peak` is kernel-counted and exact regardless.
#
# Usage
#   ./scripts/mem-watch.sh                      # build-free start (target/debug/api)
#   ./scripts/mem-watch.sh --build              # cargo build --bin api first
#   ./scripts/mem-watch.sh --release --build    # release binary
#   ./scripts/mem-watch.sh -- --features api/test-support   # args go to the API
#   ./scripts/mem-watch.sh --no-limits           # no MemoryHigh/MemoryMax
#   ./scripts/mem-watch.sh --swap-max 0          # hard net: no zram swap at all
#   ./scripts/mem-watch.sh --interval 2          # sample every 2 s (default 5)
#   ./scripts/mem-watch.sh --report              # evaluate the newest run
#   ./scripts/mem-watch.sh --report /tmp/api-mem-20261111-130000
#
# Typical session: start it, use the app against the backend, Ctrl-C, then
# evaluate later with `--report` (nothing is lost when the analysis waits).
#
# Files per run (in $outdir, default /tmp/api-mem-<timestamp>):
#   mem.csv      one row per sample: cgroup bytes + PSI pressure + event counters
#   api.log      backend stdout/stderr, every line prefixed with a timestamp
#   meta.txt     command, env (secrets redacted), binary, limits, git rev
#   summary.txt  written on exit and re-derivable via --report
#
# Requirements: bash, systemd user session (`systemd-run --user`), cgroup v2
# with the memory controller (Linux >= 5.19 for memory.peak). Optional:
# heaptrack — for the *next* step, once `anon` is confirmed as the grower:
#   heaptrack ./target/debug/api        # allocation call sites + peak
#
# The sampler is fork-free (pure bash `read` loops) so it never perturbs the
# measurement it is taking; only the timestamp uses `date`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Files the documented dev boot sequence sources (see
# .github/instructions/local-dev-runtime.instructions.md). Missing ones are
# skipped with a warning: the API falls back to its defaults.
ENV_FILES=(.env.local .env.dev-ai.local .env.dev-vault.local)
# Vars worth recording in meta.txt. Anything whose *name* looks secret is
# redacted, so a captured run can be shared without leaking credentials.
META_VARS=(
  DATABASE_URL MIGRATOR_DATABASE_URL SIERRADB_URL VAULT_ADDR VAULT_APP_TOKEN_FILE
  S3_ENDPOINT S3_BUCKET BIND_ADDR OIDC_ISS DEV_AUTH_SUB AUTHZ_ENFORCE
  AI_IMPORT_ENABLED PHOTO_GC_ENABLED REQUIRE_IN_TRANSIT_TLS RUST_LOG
)

interval=5
# NO MemoryHigh by default - measured 2026-11-11: the API's boot footprint is
# ~6.8 GB even on a 14 MB dev database (peak at ~20 s, then it settles around
# 6.3 GB and serves; /v1/health returns 200). A soft limit *below* that does
# not slow the boot down, it livelocks it: the cgroup sits above memory.high
# with only unreclaimable anon memory left, so the kernel parks the task in
# mem_cgroup_handle_over_high forever - PSI full ~50 %, zero user CPU, log
# frozen, HTTP port never opened. Reproduced with the previous default
# --mem-high 6G. Pass --mem-high explicitly if you want a throttle band, and
# keep it comfortably above the observed boot peak.
mem_high=""
mem_max=12G
# On this machine swap is zram = compressed RAM (see the oomd drop-in in
# /etc/systemd/oomd.conf.d/). A MemoryMax alone therefore does NOT kill a
# runaway cleanly: the cgroup is throttled and its pages are pushed into zram,
# which consumes the very RAM the limit was meant to protect (measured: a
# 300 MiB allocation stayed alive with MemoryMax=100M as 77 MiB anon + 226 MiB
# swap, high-throttled 1763x). Capping the cgroup's swap closes that hole.
mem_swap_max=2G
use_limits=1
release=0
do_build=0
load_env=1
outdir=""
unit=""
mode=watch
report_dir=""
api_args=()

usage() {
  sed -n '/^# Usage$/,/^# Requirements/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() { printf 'mem-watch: %b\n' "$*" >&2; exit 1; }   # %b: message may carry \n
warn() { printf 'mem-watch: %s\n' "$*" >&2; }
log() { printf '%s\n' "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval) [[ $# -ge 2 ]] || die "--interval needs a value"; interval="$2"; shift 2 ;;
    --mem-high) [[ $# -ge 2 ]] || die "--mem-high needs a value"; mem_high="$2"; shift 2 ;;
    --mem-max) [[ $# -ge 2 ]] || die "--mem-max needs a value"; mem_max="$2"; shift 2 ;;
    --swap-max) [[ $# -ge 2 ]] || die "--swap-max needs a value"; mem_swap_max="$2"; shift 2 ;;
    --out) [[ $# -ge 2 ]] || die "--out needs a directory"; outdir="$2"; shift 2 ;;
    --unit) [[ $# -ge 2 ]] || die "--unit needs a name"; unit="$2"; shift 2 ;;
    --bin) [[ $# -ge 2 ]] || die "--bin needs a path"; binary="$2"; shift 2 ;;
    --report)
        mode=report
        # Optional directory argument (not another flag, not `--`).
        if [[ $# -ge 2 && "$2" != -* ]]; then report_dir="$2"; shift 2; else shift; fi ;;
    --release) release=1; shift ;;
    --build) do_build=1; shift ;;
    --no-limits) use_limits=0; shift ;;
    --no-env) load_env=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; api_args=("$@"); break ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

[[ "$interval" =~ ^[1-9][0-9]*$ ]] || die "--interval must be a positive integer"
[[ -n "${binary:-}" ]] || binary="${BACKEND_DIR}/target/$([[ $release -eq 1 ]] && echo release || echo debug)/api"

# ── report mode: evaluate a finished (or still growing) run ─────────────────

summarize() {
  local dir="$1" csv="$1/mem.csv"
  [[ -f "$csv" ]] || die "no mem.csv in ${dir}"

  printf '\n=== memory profile: %s ===\n' "$dir"
  # Column layout of mem.csv (see write_header):
  #   1 ts  2 elapsed  3 current  4 peak  5 anon  6 file  7 kernel  8 slab
  #   9 sock  10 swap  11 psi_some  12 psi_full  13 ev_high  14 ev_max  15 ev_oom
  gawk -F, -v api_bin="$binary" '
    NR == 1 { next }                       # header row
    {
      n++; ts[n] = $1; el[n] = $2 + 0
      cur[n] = $3 + 0; pk[n]  = $4 + 0; anon[n] = $5 + 0
      file[n] = $6 + 0; swap[n] = $10 + 0; psi[n] = $12 + 0
      evhigh = $13 + 0; evmax = $14 + 0; evoom = $15 + 0

      if (cur[n] > mcur)            { mcur = cur[n];  mcur_ts = ts[n] }
      if (anon[n] > manon)          { manon = anon[n]; manon_ts = ts[n] }
      if (file[n] > mfile)          mfile = file[n]
      if (swap[n] > mswap)          { mswap = swap[n]; mswap_ts = ts[n] }
      if (psi[n] > mpsi)            { mpsi = psi[n]; mpsi_ts = ts[n] }
      if (pk[n] > mpk)              mpk = pk[n]

      # Swapped-out pages leave `anon` but reappear here: on a zram machine the
      # real footprint is anon + swap (measured: a 300 MiB allocation showed up
      # as 77 MiB anon and 226 MiB swap). Judging `anon` alone would miss it.
      foot[n] = anon[n] + swap[n]
      if (foot[n] > mfoot)          { mfoot = foot[n]; mfoot_ts = ts[n] }

      # Rank the steepest row-to-row growth: this is what "sporadic" looks like.
      if (n > 1) {
        dcur = cur[n] - cur[n-1]; danon = anon[n] - anon[n-1]
        if (dcur < 0) dcur = 0            # only growth is interesting
        for (i = 1; i <= 5 && dcur > 0; i++) {
          if (dcur > d[i]) {
            for (j = 5; j > i; j--) { d[j] = d[j-1]; dts[j] = dts[j-1]; dan[j] = dan[j-1] }
            d[i] = dcur; dts[i] = ts[n]; dan[i] = danon
            break
          }
        }
      }
    }
    function mib(b) { return sprintf("%9.1f MiB", b / 1048576) }
    END {
      if (n == 0) { print "  (no samples recorded)"; exit 0 }
      printf "  %-22s %d over %.1f min (%s .. %s)\n", "samples", n, el[n] / 60, ts[1], ts[n]
      printf "  %-22s %s  at %s\n", "peak current", mib(mcur), mcur_ts
      printf "  %-22s %s  at %s\n", "peak anon (heap)", mib(manon), manon_ts
      printf "  %-22s %s  at %s   <-- real footprint\n", "peak anon+swap", mib(mfoot), mfoot_ts
      printf "  %-22s %s   (page cache: reclaimable)\n", "peak file", mib(mfile)
      printf "  %-22s %s%s\n", "peak swap", mib(mswap), (mswap_ts == "" ? "" : "  at " mswap_ts)
      printf "  %-22s %s   (kernel-counted)\n", "memory.peak", mib(mpk)
      printf "  %-22s %s -> %s  (%+.1f MiB)\n", "anon start -> end", \
        mib(anon[1]), mib(anon[n]), (anon[n] - anon[1]) / 1048576
      printf "  %-22s %.2f%%%s\n", "max PSI full", mpsi, (mpsi_ts == "" ? "" : "  at " mpsi_ts)
      printf "  %-22s high=%d max=%d oom=%d\n", "cgroup events", evhigh, evmax, evoom

      printf "\n  steepest jumps (per sample):\n"
      if (d[1] <= 0) print "    (none - the footprint never grew between two samples)"
      for (i = 1; i <= 5 && d[i] > 0; i++)
        printf "    +%s  at %s  (anon %+.1f MiB)\n", mib(d[i]), dts[i], dan[i] / 1048576

      # Verdict heuristics - deliberately blunt, the human decides.
      printf "\n  reading:\n"
      if (evoom > 0 || evmax > 0)
        printf "    ! the cgroup was OOM-killed (MemoryMax) - the spike above is your culprit\n"
      if (mpsi > 50)
        printf "    ! PSI full peaked at %.0f%% - the cgroup was mostly stalled (throttle/reclaim), like the\n      real oomd kills; on zram a MemoryMax without MemorySwapMax degrades into thrashing\n", mpsi
      if (foot[n] - foot[1] > 134217728 || mfoot > 2147483648)
        printf "    ! footprint (anon+swap) grew %+.1f MiB, peaked %s - real retention;\n      for call sites run: heaptrack %s\n", (foot[n] - foot[1]) / 1048576, mib(mfoot), api_bin
      else if (mfile > mfoot * 4)
        printf "    = file (page cache) dominates; nothing leaks, the cgroup is just caching\n"
      else if (mfoot < 268435456)
        printf "    = no leak visible: footprint (anon+swap) stayed below 256 MiB\n"
      else
        printf "    = footprint is large but stable (no growth) - steady-state caches, not a leak\n"
    }
  ' "$csv"

  # Backend log: how much happened, and where it starts/ends, for correlation.
  if [[ -s "$dir/api.log" ]]; then
    printf '\n  backend log: %s lines (%s .. %s)\n  -> %s\n' \
      "$(wc -l < "$dir/api.log")" \
      "$(head -1 "$dir/api.log" | cut -f1)" \
      "$(tail -1 "$dir/api.log" | cut -f1)" \
      "$dir/api.log"
  fi
  printf '\n  raw data: %s\n' "$csv"
}

if [[ "$mode" == report ]]; then
  if [[ -z "$report_dir" ]]; then
    # shellcheck disable=SC2012  # newest run dir, names are timestamp-sortable
    report_dir="$(ls -1dt /tmp/api-mem-* 2>/dev/null | head -1 || true)"
    [[ -n "$report_dir" ]] || die "no /tmp/api-mem-* run found - pass a directory"
  fi
  summarize "$report_dir"
  exit 0
fi

# ── watch mode: run the API in its own scope and sample it ──────────────────

command -v systemd-run >/dev/null || die "systemd-run not found (needs a systemd user session)"
command -v systemctl  >/dev/null || die "systemctl not found"
[[ -d /sys/fs/cgroup ]] || die "cgroup v2 required"

if [[ $do_build -eq 1 ]]; then
  log "==> cargo build --bin api ($([[ $release -eq 1 ]] && echo release || echo debug))"
  ( cd "$BACKEND_DIR" && cargo build --bin api $([[ $release -eq 1 ]] && echo --release) )
fi
[[ -x "$binary" ]] || die "not executable: ${binary}\n  build it first: ./scripts/mem-watch.sh --build"

if [[ $load_env -eq 1 ]]; then
  cd "$BACKEND_DIR"
  for f in "${ENV_FILES[@]}"; do
    if [[ -f "$f" ]]; then
      set -a
      # shellcheck disable=SC1090  # git-ignored dev env files, sourced by design
      . "./$f"
      set +a
      log "==> env: + ${f}"
    else
      warn "env file missing, skipping: ${f} (API falls back to its defaults)"
    fi
  done
else
  warn "--no-env: expecting the environment to be exported by the caller"
fi

stamp="$(date +%Y%m%d-%H%M%S)"
[[ -n "$outdir" ]] || outdir="/tmp/api-mem-${stamp}"
mkdir -p "$outdir"
outdir="$(cd "$outdir" && pwd)"   # absolute: the sampler runs after a possible cd
[[ -n "$unit" ]] || unit="api-mem-${stamp}"
unit="${unit%.scope}"
csv="${outdir}/mem.csv"
apilog="${outdir}/api.log"

# ── meta.txt ────────────────────────────────────────────────────────────────
{
  printf 'run dir      %s\n' "$outdir"
  printf 'started      %s\n' "$(date +%FT%T%:z)"
  printf 'binary       %s\n' "$binary"
  printf 'binary mtime %s\n' "$(stat -c '%y (%s bytes)' "$binary" 2>/dev/null || echo '?')"
  printf 'unit         %s.scope\n' "$unit"
  printf 'interval     %ss\n' "$interval"
  if [[ $use_limits -eq 1 ]]; then
    printf 'limits       MemoryHigh=%s MemoryMax=%s MemorySwapMax=%s\n' \
      "${mem_high:-<none>}" "$mem_max" "$mem_swap_max"
  else
    printf 'limits       none (--no-limits)\n'
  fi
  printf 'kernel       %s / systemd %s\n' "$(uname -r)" "$(systemctl --version | head -1 | cut -d' ' -f2)"
  printf 'cmd          %s %s\n' "$binary" "${api_args[*]:-}"
  printf 'git          %s%s\n' \
    "$(cd "$BACKEND_DIR" && git rev-parse --short HEAD 2>/dev/null || echo '?')" \
    "$(cd "$BACKEND_DIR" && git diff --quiet 2>/dev/null || echo ' (dirty tree)')"
  printf 'swap device  %s\n' "$(swapon --show=NAME,TYPE,SIZE --noheadings 2>/dev/null | tr '\n' ' ' || echo '?')"
  printf '\nrelevant env (secrets redacted):\n'
  for v in "${META_VARS[@]}"; do
    [[ -n "${!v:-}" ]] || continue
    if [[ "$v" =~ (TOKEN|SECRET|KEY|PASSWORD) ]]; then
      printf '  %s=<redacted>\n' "$v"
    elif [[ "${!v}" == *"://"* ]]; then
      # Connection strings carry credentials in the userinfo part; a captured
      # run must stay safe to paste into an issue.
      printf '  %s=%s\n' "$v" "$(sed -E 's#(://[^:/@]*:)[^@]*@#\1***@#' <<< "${!v}")"
    else
      printf '  %s=%s\n' "$v" "${!v}"
    fi
  done
} > "${outdir}/meta.txt" 2>&1

# ── sampler: pure-bash, fork-free except the timestamp ─────────────────────
cgdir=""
sampler_pid=""
runner_pid=""
finished=0

write_header() {
  printf 'ts,elapsed_s,current,peak,anon,file,kernel,slab,sock,swap,psi_some10,psi_full10,ev_high,ev_max,ev_oom\n' > "$csv"
}

sample_once() {
  local elapsed now anon=0 file=0 kernel=0 slab=0 sock=0
  local cur='' peak='' swap=0 psi_some=0 psi_full=0
  local ev_high=0 ev_max=0 ev_oom=0 k v rest a b c
  local d="$1"

  now="$(date +%FT%T)"
  elapsed=$(( $(date +%s) - start_epoch ))

  while read -r k v; do
    # memory.stat: anon = heap, file = page cache, kernel/slab = kernel side
    case "$k" in
      anon|file|kernel|slab) printf -v "$k" '%s' "$v" ;;
      sock) sock="$v" ;;
    esac
  done < "$d/memory.stat" || true

  [[ -r "$d/memory.current" ]] && cur="$(< "$d/memory.current")"
  [[ -r "$d/memory.peak" ]] && peak="$(< "$d/memory.peak")"
  [[ -r "$d/memory.swap.current" ]] && swap="$(< "$d/memory.swap.current")"

  if [[ -r "$d/memory.pressure" ]]; then
    while read -r k rest; do
      case "$k" in
        some) a="${rest#*avg10=}"; psi_some="${a%% *}" ;;
        full) b="${rest#*avg10=}"; psi_full="${b%% *}" ;;
      esac
    done < "$d/memory.pressure" || true
  fi

  if [[ -r "$d/memory.events" ]]; then
    while read -r k v; do
      case "$k" in
        high) ev_high="$v" ;;
        max) ev_max="$v" ;;
        oom) ev_oom="$v" ;;
      esac
    done < "$d/memory.events" || true
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$now" "$elapsed" "${cur:-0}" "${peak:-0}" "$anon" "$file" "$kernel" "$slab" \
    "$sock" "$swap" "$psi_some" "$psi_full" "$ev_high" "$ev_max" "$ev_oom" >> "$csv"
  return 0
}

sampler_loop() {
  local d="$1"
  while :; do
    sample_once "$d"
    sleep "$interval"
  done
}

cleanup() {
  [[ $finished -eq 1 ]] && return 0
  finished=1
  # Stop the sampler first so no row races the summary.
  if [[ -n "$sampler_pid" ]]; then kill "$sampler_pid" 2>/dev/null || true; fi
  # Stop the scope if it outlived the runner (e.g. the terminal was closed).
  if systemctl --user is-active --quiet "${unit}.scope" 2>/dev/null; then
    systemctl --user stop "${unit}.scope" 2>/dev/null || true
    warn "stopped ${unit}.scope"
  fi
  if [[ -n "$runner_pid" ]]; then wait "$runner_pid" 2>/dev/null || true; fi
  {
    printf '\nfinished     %s\n' "$(date +%FT%T%:z)"
    printf 'exit status  %s\n' "${run_status:-?}"
  } >> "${outdir}/meta.txt"
  summarize "$outdir" | tee "${outdir}/summary.txt"
  log ""
  log "==> evaluate again later:  ./scripts/mem-watch.sh --report ${outdir}"
}
trap cleanup EXIT
trap 'warn "interrupted - stopping ${unit}.scope"; exit 130' INT TERM

write_header
start_epoch="$(date +%s)"

# Timestamp every backend log line. gawk is present on the dev machines; the
# fallback keeps working (uncorrelated timestamps) where it is not.
stamp_stream() {
  if command -v gawk >/dev/null; then
    exec gawk '{ printf "%s\t%s\n", strftime("%Y-%m-%dT%H:%M:%S"), $0; fflush() }'
  fi
  exec cat
}

scope_props=(-p MemoryAccounting=yes)
if [[ $use_limits -eq 1 ]]; then
  # MemoryHigh only on request: a band narrower than the boot peak livelocks
  # the process instead of pacing it (see the defaults block).
  [[ -n "$mem_high" ]] && scope_props+=(-p "MemoryHigh=${mem_high}")
  scope_props+=(-p "MemoryMax=${mem_max}" -p "MemorySwapMax=${mem_swap_max}")
fi

log "==> starting ${binary} in scope ${unit}.scope"
if [[ $use_limits -eq 1 ]]; then
  log "    limits: MemoryHigh=${mem_high:-<none>} MemoryMax=${mem_max} MemorySwapMax=${mem_swap_max} (its own scope: a runaway dies there, never your terminal)"
fi
log "    sampling every ${interval}s -> ${csv}"
log "    Ctrl-C when done. Then use the app; evaluation can wait."

# Background the run so the sampler can find and follow its cgroup. stdin is
# /dev/null (a background job must not read the tty); stopping happens through
# systemctl on the scope, which is also what Ctrl-C triggers via the trap.
(
  exec systemd-run --user --scope --quiet --collect --unit="$unit" \
    "${scope_props[@]}" -- "$binary" "${api_args[@]}" < /dev/null 2>&1
) | stamp_stream | tee "$apilog" &
runner_pid=$!

# The scope appears asynchronously: poll for its cgroup before sampling.
for _ in $(seq 1 50); do
  cgpath="$(systemctl --user show -p ControlGroup --value "${unit}.scope" 2>/dev/null || true)"
  if [[ -n "$cgpath" && -d "/sys/fs/cgroup${cgpath}" ]]; then
    cgdir="/sys/fs/cgroup${cgpath}"
    break
  fi
  sleep 0.1
done

if [[ -z "$cgdir" ]]; then
  warn "could not resolve the cgroup of ${unit}.scope - no samples will be taken"
  warn "(the API keeps running; check 'systemd-run --user --scope' support)"
else
  log "    cgroup: ${cgdir#/sys/fs/cgroup}"
  sampler_loop "$cgdir" &
  sampler_pid=$!
fi

# Wait for the backend to exit (or for the trap to stop the scope).
set +e
wait "$runner_pid"
run_status=$?
set -e
exit 0
