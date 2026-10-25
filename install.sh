#!/usr/bin/env bash
# HonorFNPP installer: daemon, CLI, systemd unit, device profiles and docs.
#
#   sudo ./install.sh
#   sudo ./install.sh --with-deps     # apt install missing runtime packages
#
# Override the install prefix with PREFIX=/usr if needed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-/usr/local}"
WITH_DEPS=0

log()  { printf '\033[1;34m[HonorFNPP]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[HonorFNPP]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[HonorFNPP]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --with-deps) WITH_DEPS=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $arg" ;;
    esac
done

[[ ${EUID} -eq 0 ]] || die "run with sudo: sudo $0"

vendor="$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || echo unknown)"
product="$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo unknown)"
bios="$(cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown)"
log "DMI: ${vendor} ${product}, BIOS ${bios}"

if [[ "${vendor^^}" != "HONOR" && "${vendor^^}" != "HUAWEI" ]]; then
    warn "this machine does not report HONOR/HUAWEI as DMI vendor; continuing anyway"
fi

if [[ ${WITH_DEPS} -eq 1 ]]; then
    command -v apt-get >/dev/null || die "--with-deps requires apt-get"
    log "installing runtime dependencies"
    apt-get update
    apt-get install -y python3 acpi-call-dkms power-profiles-daemon libnotify-bin
fi

missing=()
command -v python3 >/dev/null || missing+=(python3)
command -v powerprofilesctl >/dev/null || missing+=(power-profiles-daemon)
command -v notify-send >/dev/null || missing+=(libnotify-bin)
if ((${#missing[@]})); then
    warn "missing optional packages: ${missing[*]}"
    warn "the daemon still works through sysfs, but CLI/OSD may be limited"
    warn "re-run with --with-deps to install them"
fi

if command -v python3 >/dev/null; then
    log "validating device profiles"
    python3 "${ROOT}/tools/validate_devices.py" "${ROOT}/devices" \
        || die "device profiles failed validation"
fi

modprobe ec_sys 2>/dev/null || true
modprobe acpi_call 2>/dev/null || true

# Migrate from the pre-rename honor-perfmode package.
if [[ -f /etc/systemd/system/honor-perfmode.service && ! -L /etc/systemd/system/honor-perfmode.service ]]; then
    log "stopping old honor-perfmode.service"
    systemctl disable --now honor-perfmode.service 2>/dev/null || true
    rm -f /etc/systemd/system/honor-perfmode.service
fi
rm -rf "${PREFIX}/share/doc/honor-perfmode" "${PREFIX}/share/honor-perfmode"

log "installing ${PREFIX}/bin/honorfnpp"
install -Dm755 "${ROOT}/bin/honorfnpp" "${PREFIX}/bin/honorfnpp"
ln -sfn honorfnpp "${PREFIX}/bin/honor-perfmode"

log "installing device profiles"
install -d "${PREFIX}/share/honorfnpp/devices"
for profile in "${ROOT}"/devices/*.json; do
    if [[ "$(basename "${profile}")" == _* ]]; then
        continue
    fi
    install -m644 "${profile}" "${PREFIX}/share/honorfnpp/devices/"
done
install -Dm644 "${ROOT}/devices/README.md" \
    "${PREFIX}/share/honorfnpp/devices/README.md"

log "installing /etc/systemd/system/honorfnpp.service"
unit_tmp="$(mktemp)"
sed -e "s|/usr/local/bin/honorfnpp|${PREFIX}/bin/honorfnpp|g" \
    -e "s|/usr/local/share/doc|${PREFIX}/share/doc|g" \
    "${ROOT}/systemd/honorfnpp.service" > "${unit_tmp}"
install -Dm644 "${unit_tmp}" /etc/systemd/system/honorfnpp.service
rm -f "${unit_tmp}"

if [[ -e /etc/honorfnpp.conf ]]; then
    log "keeping existing /etc/honorfnpp.conf"
elif [[ -e /etc/honor-perfmode.conf ]]; then
    log "migrating /etc/honor-perfmode.conf -> /etc/honorfnpp.conf"
    install -Dm644 /etc/honor-perfmode.conf /etc/honorfnpp.conf
else
    log "installing default /etc/honorfnpp.conf"
    install -Dm644 "${ROOT}/config/honorfnpp.conf.example" \
        /etc/honorfnpp.conf
fi

log "installing documentation"
install -Dm644 "${ROOT}/README.md" \
    "${PREFIX}/share/doc/honorfnpp/README.md"
install -Dm644 "${ROOT}/README.en.md" \
    "${PREFIX}/share/doc/honorfnpp/README.en.md"
install -Dm644 "${ROOT}/docs/technical-notes.md" \
    "${PREFIX}/share/doc/honorfnpp/technical-notes.md"
install -Dm644 "${ROOT}/docs/compatibility.md" \
    "${PREFIX}/share/doc/honorfnpp/compatibility.md"
install -Dm644 "${ROOT}/docs/desktop-support.md" \
    "${PREFIX}/share/doc/honorfnpp/desktop-support.md"
install -Dm644 "${ROOT}/docs/adding-device.md" \
    "${PREFIX}/share/doc/honorfnpp/adding-device.md"
install -Dm644 "${ROOT}/CONTRIBUTING.md" \
    "${PREFIX}/share/doc/honorfnpp/CONTRIBUTING.md"

systemctl daemon-reload
systemctl disable honorfnpp.service 2>/dev/null || true
systemctl enable honorfnpp.service
systemctl restart honorfnpp.service
sleep 1

if systemctl is-active --quiet honorfnpp.service; then
    log "service is active"
else
    warn "service failed to start; check: journalctl -u honorfnpp -n 50"
fi

log "installed. Try:"
log "  sudo ${PREFIX}/bin/honorfnpp check"
log "  sudo ${PREFIX}/bin/honorfnpp status"
log "  sudo ${PREFIX}/bin/honorfnpp notify-test"
log "  press Fn+P"
