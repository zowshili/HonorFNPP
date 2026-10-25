#!/usr/bin/env bash
# Remove HonorFNPP. Keeps the config unless --purge is used.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
PURGE=0

log()  { printf '\033[1;34m[HonorFNPP]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[HonorFNPP]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[HonorFNPP]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

[[ ${EUID} -eq 0 ]] || die "run with sudo: sudo $0"

if [[ -x "${PREFIX}/bin/honorfnpp" ]]; then
    log "restoring smart mode"
    "${PREFIX}/bin/honorfnpp" off || warn "could not restore EC mode"
elif [[ -x "${PREFIX}/bin/honor-perfmode" ]]; then
    log "restoring smart mode (legacy)"
    "${PREFIX}/bin/honor-perfmode" off || warn "could not restore EC mode"
fi

log "stopping and disabling services"
systemctl disable --now honorfnpp.service 2>/dev/null || true
systemctl disable --now honor-perfmode.service 2>/dev/null || true

log "removing installed files"
rm -f "${PREFIX}/bin/honorfnpp"
rm -f "${PREFIX}/bin/honor-perfmode"
rm -f /etc/systemd/system/honorfnpp.service
rm -f /etc/systemd/system/honor-perfmode.service
rm -rf "${PREFIX}/share/doc/honorfnpp"
rm -rf "${PREFIX}/share/honorfnpp"
rm -rf "${PREFIX}/share/doc/honor-perfmode"
rm -rf "${PREFIX}/share/honor-perfmode"
rm -rf "${ROOT}/bin/__pycache__" "${ROOT}/tools/__pycache__" "${ROOT}/__pycache__"

if [[ ${PURGE} -eq 1 ]]; then
    log "removing /etc/honorfnpp.conf and legacy config"
    rm -f /etc/honorfnpp.conf /etc/honor-perfmode.conf
else
    log "keeping /etc/honorfnpp.conf (use --purge to remove it)"
fi

systemctl daemon-reload
log "removed"
log "optional: sudo apt remove acpi-call-dkms   # if nothing else needs it"
