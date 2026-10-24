#!/usr/bin/env bash
# Measure sustained package power in smart (35 W) and performance (45 W) modes.
# Requires root, turbostat (linux-cpupower) and the installed honorfnpp CLI.
#
#   sudo ./tools/power-test.sh
#   sudo DURATION=15 THREADS=16 ./tools/power-test.sh
#
# WARNING: this intentionally loads every CPU thread and heats the machine.

set -euo pipefail

CMD="${CMD:-/usr/local/bin/honorfnpp}"
DURATION="${DURATION:-10}"
THREADS="${THREADS:-12}"
SETTLE="${SETTLE:-5}"
WARMUP="${WARMUP:-3}"
COOLDOWN="${COOLDOWN:-60}"
TURBOSTAT="${TURBOSTAT:-/usr/sbin/turbostat}"

log()  { printf '\033[1;34m[power-test]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[power-test]\033[0m %s\n' "$*" >&2; }

[[ ${EUID} -eq 0 ]] || { warn "run with sudo"; exit 1; }
[[ -x "${CMD}" ]] || { warn "${CMD} not found; install honorfnpp first"; exit 1; }
[[ -x "${TURBOSTAT}" ]] || { warn "${TURBOSTAT} not found; install linux-cpupower"; exit 1; }

cleanup() {
    local pids
    pids="$(jobs -p 2>/dev/null || true)"
    # shellcheck disable=SC2086  # intentional word splitting: one PID per word
    [[ -n "${pids}" ]] && kill ${pids} 2>/dev/null || true
}
trap cleanup EXIT

measure() {
    local label="$1"
    local pids
    for _ in $(seq "${THREADS}"); do yes > /dev/null & done
    pids="$(jobs -p)"
    sleep "${WARMUP}"
    "${TURBOSTAT}" --quiet --show PkgWatt --interval 1 \
        --num_iterations "${DURATION}" 2>/dev/null \
        | awk -v l="${label}" 'NR>1 && $1 ~ /^[0-9.]+$/ {s+=$1; n++} END {if (n) printf "%s: avg_pkg_watt=%.2f samples=%d\n", l, s/n, n}'
    # shellcheck disable=SC2086  # intentional word splitting: one PID per word
    kill ${pids} 2>/dev/null || true
    wait 2>/dev/null || true
    log "cooling ${COOLDOWN}s"
    sleep "${COOLDOWN}"
}

orig="$("${CMD}" status --json | python3 -c 'import json,sys; print(json.load(sys.stdin)["ec_tubf"])')"
log "original EC TUBF=${orig}"

"${CMD}" on
sleep "${SETTLE}"
measure performance

"${CMD}" off
sleep "${SETTLE}"
measure smart

if [[ "${orig}" == "1" ]]; then
    "${CMD}" on
else
    "${CMD}" off
fi
log "restored EC TUBF=${orig}"
