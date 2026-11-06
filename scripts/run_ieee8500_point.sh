#!/usr/bin/env bash
# Per-process wrapper for ONE IEEE-8500 measurement point.
#
# usage: scripts/run_ieee8500_point.sh <label> -- <benchmark args...>
#   SCRIPT=scripts/profile_ieee8500_memory.jl scripts/run_ieee8500_point.sh <label> -- <profiler args...>
#   HEAP_SIZE_HINT=8G scripts/run_ieee8500_point.sh <label> -- <args...>   # julia --heap-size-hint=8G
#
# Use a FRESH label for every launch, for example <name>-$(date +%Y%m%d-%H%M). A label that already
# has evidence (runs/<label>.time or .free_before) or a point_resources.csv row is refused with
# exit 2 before anything is written; REPLACE_LABEL=1 overrides that and overwrites the evidence.
#
# Heap-size hint (opt-in, added 2026-11-06): julia reads NO environment variable for its heap-size
# hint, so JULIA_HEAP_SIZE_HINT=... has never had any effect on a run. Only the command-line flag
# `--heap-size-hint=` sets it. When HEAP_SIZE_HINT is set, the wrapper passes
# `--heap-size-hint=$HEAP_SIZE_HINT` to julia (visible in the run's .time command line); when it is
# unset the julia command line is exactly what it was before.
#
# Records /usr/bin/time -v peak RSS, a `free -m` snapshot BEFORE the run, and OOM evidence from BOTH
# `journalctl -k` (kernel OOM killer) and `journalctl -u earlyoom` (userspace killer, which sends
# SIGTERM/SIGKILL and logs to its own unit, not the kernel log). One row is appended to
# results/ieee8500_benchmark/point_resources.csv. An OOM is a RECORDED OUTCOME: the wrapper exits 0
# even when the point is killed; it exits nonzero only for wrapper misuse.
set -u

if [ "$#" -lt 3 ] || [ "$2" != "--" ]; then
  echo "usage: $0 <label> -- <benchmark args...>" >&2
  exit 2
fi
LABEL="$1"
shift 2
case "$LABEL" in
  *[!A-Za-z0-9._-]*|"") echo "label must match [A-Za-z0-9._-]+" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${SCRIPT:-scripts/benchmark_ieee8500.jl}"
OUTDIR="${OUTDIR:-$ROOT/results/ieee8500_benchmark}"
RUNS="$OUTDIR/runs"
mkdir -p "$RUNS"
cd "$ROOT" || exit 2

# --run-label is only understood by the benchmark harness (the profiler would reject it).
# Compared by BASENAME so `./scripts/...` or an absolute path still gets the label.
LABEL_ARGS=()
if [ "$(basename "$SCRIPT")" = "benchmark_ieee8500.jl" ]; then
  LABEL_ARGS=(--run-label "$LABEL")
fi

HEAP_ARGS=()
if [ -n "${HEAP_SIZE_HINT:-}" ]; then
  if ! [[ "$HEAP_SIZE_HINT" =~ ^[0-9]+([.][0-9]+)?[KMGTkmgt%]?$ ]]; then
    echo "HEAP_SIZE_HINT must look like 8G, 8192M or 50% (got '$HEAP_SIZE_HINT')" >&2
    exit 2
  fi
  HEAP_ARGS=("--heap-size-hint=$HEAP_SIZE_HINT")
elif [ -n "${JULIA_HEAP_SIZE_HINT:-}" ]; then
  echo "run_ieee8500_point: warning: julia ignores JULIA_HEAP_SIZE_HINT; no heap-size hint is applied (set HEAP_SIZE_HINT to pass --heap-size-hint)" >&2
fi

# A label is one launch (added 2026-11-06). The evidence files below are keyed by the label alone,
# so a reused label would overwrite an earlier launch's evidence (and, for the Scenario script,
# compete for its result row). Refuse before anything is written, unless REPLACE_LABEL=1.
# point_resources.csv stays append-only either way.
CSV="$OUTDIR/point_resources.csv"
if [ "${REPLACE_LABEL:-0}" != 1 ]; then
  USED=""
  for ext in time free_before; do
    [ -e "$RUNS/$LABEL.$ext" ] && USED="runs/$LABEL.$ext"
  done
  if [ -z "$USED" ] && [ -f "$CSV" ] &&
    awk -F, -v l="$LABEL" '$1 == l { f = 1 } END { exit !f }' "$CSV"; then
    USED="a point_resources.csv row"
  fi
  if [ -n "$USED" ]; then
    echo "run_ieee8500_point: label $LABEL was already launched ($USED exists); use a fresh label, for example $LABEL-$(date +%Y%m%d-%H%M), or set REPLACE_LABEL=1 to overwrite its runs/ evidence" >&2
    exit 2
  fi
fi

START="$(date '+%Y-%m-%d %H:%M:%S')"
free -m > "$RUNS/$LABEL.free_before"
MEM_AVAIL="$(awk '/^Mem:/{print $7}' "$RUNS/$LABEL.free_before")"
SWAP_USED="$(awk '/^Swap:/{print $3}' "$RUNS/$LABEL.free_before")"
OTHER_JULIA="$(pgrep -c -x julia 2>/dev/null || true)"
OTHER_JULIA="${OTHER_JULIA:-0}"

# The child records its OWN pid and then `exec`s julia (same pid), so OOM log lines can be matched
# to THIS point's process rather than to any process killed on the host meanwhile.
PIDFILE="$RUNS/$LABEL.pid"
rm -f "$PIDFILE"
/usr/bin/time -v -o "$RUNS/$LABEL.time" bash -c 'echo $$ > "$0"; exec "$@"' "$PIDFILE" \
  julia "${HEAP_ARGS[@]}" --project=. "$SCRIPT" "$@" "${LABEL_ARGS[@]}"
RC=$?
CHILD_PID="$(cat "$PIDFILE" 2>/dev/null || true)"

PEAK_KB="$(awk -F': ' '/Maximum resident set size/{print $2}' "$RUNS/$LABEL.time" 2>/dev/null)"
PEAK_KB="${PEAK_KB:-NaN}"
KERN="$(journalctl -k --since "$START" --no-pager 2>/dev/null | grep -iE "out of memory|oom-kill|Killed process" || true)"
EARLY="$(journalctl -u earlyoom --since "$START" --no-pager 2>/dev/null | grep -iE "sending|killing|SIGTERM|SIGKILL" || true)"
printf '%s\n' "$KERN" > "$RUNS/$LABEL.oom_kernel"
printf '%s\n' "$EARLY" > "$RUNS/$LABEL.oom_earlyoom"

# The journals above are host-wide (other julia processes are expected here, see
# other_julia_procs), so the full logs are kept as evidence but an OOM is ATTRIBUTED to this point
# only when (a) the point actually failed (RC != 0) AND (b) a log line names THIS point's pid.
#   oom_source = kernel | earlyoom      — RC != 0 and that killer's log names CHILD_PID
#              = signal_unattributed    — RC 137/143 (SIGKILL/SIGTERM) but no log line names CHILD_PID
#              = none                   — otherwise (including RC = 0, whatever else was killed)
OOM_SOURCE=none
if [ "$RC" -ne 0 ]; then
  KERN_MINE=""
  EARLY_MINE=""
  if [ -n "$CHILD_PID" ]; then
    PID_RE="(process |pid[= ])${CHILD_PID}([^0-9]|\$)"
    KERN_MINE="$(printf '%s\n' "$KERN" | grep -E "$PID_RE" || true)"
    EARLY_MINE="$(printf '%s\n' "$EARLY" | grep -E "$PID_RE" || true)"
  fi
  if [ -n "$KERN_MINE" ]; then
    OOM_SOURCE=kernel
  elif [ -n "$EARLY_MINE" ]; then
    OOM_SOURCE=earlyoom
  elif [ "$RC" -eq 137 ] || [ "$RC" -eq 143 ]; then
    OOM_SOURCE=signal_unattributed
  fi
fi

if [ ! -f "$CSV" ]; then
  echo "run_label,rc,peak_rss_kb,oom_source,mem_avail_before_mb,swap_used_before_mb,other_julia_procs,started_at,args" > "$CSV"
fi
ARGS_STR="$(printf '%s ' "$@")"
ARGS_STR="${ARGS_STR//\"/}"
printf '%s,%s,%s,%s,%s,%s,%s,%s,"%s"\n' \
  "$LABEL" "$RC" "$PEAK_KB" "$OOM_SOURCE" "$MEM_AVAIL" "$SWAP_USED" "$OTHER_JULIA" "$START" "${ARGS_STR% }" >> "$CSV"
echo "run_ieee8500_point: label=$LABEL rc=$RC peak_rss_kb=$PEAK_KB oom_source=$OOM_SOURCE"
exit 0
