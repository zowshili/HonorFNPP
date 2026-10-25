# Changelog

## 1.1.1 — 2026-10-25

- Start at `graphical.target` after `power-profiles-daemon`, fixing the
  systemd ordering cycle that skipped the service at boot.
- Installer now disables old unit symlinks before enabling the new unit.
- Add `.gitignore`.
- Restore executable bits on the CLI and install/uninstall/tool scripts.
- Documentation: full Chinese/English README with a working language switch.

## 1.1.0 — 2026-10-24

Initial public release of **HonorFNPP** (formerly `honor-fnp` / `honor-perfmode`).

- Fn+P performance mode sync for HONOR MagicBook on Linux: EC `TUBF` plus
  ACPI `platform_profile`, 35 W smart / 45 W performance.
- Verified on HONOR MagicBook X 14 Pro (`FRI-HXX`, Ryzen 7 7840HS, BIOS 1.15),
  Debian 13, kernel 7.2.6.
- GNOME, KDE Plasma 5/6 and Deepin DDE OSD support, with `notify-send`,
  `kdialog` and raw `dbus-send` fallbacks; `notify-test` command.
- Device profiles in `devices/*.json`, auto-matched by DMI, with
  `tools/validate_devices.py`, `make validate`, and CI validation.
- `DEVICE_PROFILE`, `HONORFNPP_DEVICE_PROFILE` and `HONORFNPP_DEVICES`
  overrides for testing new models.
- CLI: `status [--json]`, `check`, `on`, `off`, `toggle`, `notify-test`,
  `daemon`; systemd unit; install/uninstall scripts; power test tool.
- Contribution workflow: `CONTRIBUTING.md`, `docs/adding-device.md`,
  PR template, device-support and bug issue forms.
