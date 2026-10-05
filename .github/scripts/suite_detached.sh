#!/usr/bin/env bash
# Launch a long command (full suite / docs build) detached from the tool call.
# Usage: suite_detached.sh LABEL [CMD...]
#   writes .planning/tmp/36/LABEL.{log,start,done}; DONE holds the command's exit status.
# Default CMD: julia --project=. -e 'import Pkg; Pkg.test()'
set -u
LABEL="${1:?usage: suite_detached.sh LABEL [CMD...]}"; shift
ROOT="$(git rev-parse --show-toplevel)"; cd "$ROOT"
mkdir -p .planning/tmp/36
export LOG=".planning/tmp/36/${LABEL}.log" DONE=".planning/tmp/36/${LABEL}.done"
rm -f "$DONE"
date +%s > ".planning/tmp/36/${LABEL}.start"
if [ "$#" -eq 0 ]; then
  set -- julia --project=. -e 'import Pkg; Pkg.test()'
fi
# Inner script is SINGLE-quoted: $? is expanded by the inner shell after CMD finishes.
nohup setsid bash -c '"$@" > "$LOG" 2>&1; echo $? > "$DONE"' _ "$@" </dev/null >/dev/null 2>&1 &
echo "launched $LABEL (log $LOG, marker $DONE)"
