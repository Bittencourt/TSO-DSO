#!/usr/bin/env bash
# Subprocess driver for the POP-05 Case-A scaling measurement (Phase 40).
#
# usage:
#   scripts/run_case_a_scaling.sh                  # all legs (ladder + threads-sweep)
#   scripts/run_case_a_scaling.sh --ladder-only    # the serial ladder leg only
#   scripts/run_case_a_scaling.sh --sweep-only     # the threads-sweep legs only
#
# Runs scripts/case_a_scaling.jl as ONE `julia -t N` PROCESS PER LEG — Threads.nthreads()
# is fixed at process start, so the threads sweep cannot run in-process:
#
#   leg 1    ladder        (julia --project=. -t 1)  ~6 nested-prefix rungs (10→784 houses),
#            one row per rung → results/case_a_population/scaling_ladder.csv
#   legs 2-4 threads-sweep at -t 1 / -t 2 / -t 4 (full 784-house population per leg),
#            one row per leg → results/case_a_population/threads_sweep.csv
#
# A killed leg is a RECORDED OUTCOME (honesty policy): the rows the leg had already
# captured persist in the CSVs (upsert on provenance identity); re-run the same leg to
# replace its own rows. Nonzero exits PROPAGATE (`|| exit $?`) — there is NO silent
# fallback; in particular a threads-sweep leg whose process has fewer than 2 threads fails
# loud (the Phase-39 executor throws on parallel = true with Threads.nthreads() == 1).
#
# Budget note: each solve carries the script's default --time-limit-s 1800 wall-clock
# budget, so a stalled leg returns an honest :budget_exceeded row instead of stalling the
# host. Expected total runtime: tens of minutes (host: 4 cores / 15 GB).
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

LEGS="all"
case "${1:-}" in
  "") ;;
  --ladder-only) LEGS="ladder" ;;
  --sweep-only) LEGS="sweep" ;;
  *)
    echo "usage: $0 [--ladder-only|--sweep-only]" >&2
    exit 2
    ;;
esac

if [ "$LEGS" = "all" ] || [ "$LEGS" = "ladder" ]; then
  echo "== ladder leg (serial, -t 1) =="
  julia --project=. -t 1 scripts/case_a_scaling.jl --mode ladder || exit $?
fi

if [ "$LEGS" = "all" ] || [ "$LEGS" = "sweep" ]; then
  for t in 1 2 4; do
    echo "== threads-sweep leg (-t $t) =="
    julia --project=. -t $t scripts/case_a_scaling.jl --mode threads-sweep --threads $t || exit $?
  done
fi

echo "run_case_a_scaling: all requested legs complete"
