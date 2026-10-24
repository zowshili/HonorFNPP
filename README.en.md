# HonorFNPP

**English** | [简体中文](README.md)

HONOR MagicBook **Fn+P performance mode**, made usable on Linux: press Fn+P to
switch between Smart (lower power) and Performance (higher power), with a
desktop notification (GNOME/KDE/Deepin supported).

> Verified on **HONOR MagicBook X 14 Pro (FRI-HXX, Ryzen 7 7840HS, BIOS 1.15)**,
> Debian 13, kernel 7.2.6. On other MagicBook models, run `check` first.

## The problem

On HONOR laptops, Fn+P is handled by the EC. The EC flips the performance bit
`TUBF` (EC offset `0xDC`, bit 0) between 0 and 1, but Linux does not update the
ACPI `platform_profile` automatically.

On the MagicBook X 14 Pro, **both switches must be enabled** to get 45 W:

| EC TUBF | ACPI platform_profile | Sustained package power |
|---|---|---|
| 0 | balanced | 35 W |
| 0 | performance | 35 W |
| 1 | balanced | 35 W |
| 1 | **performance** | **45 W** |

Therefore:

- Fn+P alone: the EC switches, but the OS stays on `balanced` → 35 W; it does
  not work.
- GNOME Performance alone: the OS switches, but the EC stays at 0 → 35 W;
  still does not work.
- The common claim that "installing power-profiles-daemon is enough to switch
  performance" does not actually hold.

## What it does

A userspace daemon keeps the two switches in sync in both directions:

1. It polls EC `0xDC`; when Fn+P changes `TUBF`, it sets
   `power-profiles-daemon` to `performance` / `balanced`.
2. Reverse sync: selecting Performance in GNOME or via `powerprofilesctl`
   sets EC `TUBF` to 1 through ACPI `STUB`.

EC read/write path:

- Read: `/sys/kernel/debug/ec/ec0/io`, offset `0xDC` (one byte read).
- Write: `acpi_call` → `\_SB.WMI1.WMAA 0 1 b040f01...`
  (group `0x04`, command `0x0f`).

No DSDT changes, no BIOS flashing, no kernel changes. The only kernel-side
dependency is `acpi_call` (DKMS), used to write the EC. Even if it is
unavailable, the Fn+P EC→PPD direction still works.

## Desktop support

Mode switching is independent of the desktop environment. Notifications are
selected automatically for the current desktop, using their native/standard
interfaces:

- Supports **GNOME** / **KDE Plasma 5/6** / **Deepin DDE**.
- Test notifications:

```bash
sudo honorfnpp notify-test
```

## Install

Dependencies (Debian/Ubuntu):

```bash
sudo apt install python3 acpi-call-dkms power-profiles-daemon libnotify-bin
```

Install:

```bash
git clone <your-repo-url> HonorFNPP
cd HonorFNPP
sudo ./install.sh
# or install dependencies automatically:
sudo ./install.sh --with-deps
```

Check:

```bash
sudo honorfnpp check
sudo honorfnpp status
```

## Usage

```bash
sudo honorfnpp status      # EC / GTUB / platform_profile / PPD / AC / battery
sudo honorfnpp on          # Performance mode, 45 W
sudo honorfnpp off         # Smart mode, 35 W
sudo honorfnpp toggle
sudo honorfnpp status --json
sudo honorfnpp notify-test # test the current desktop's notification/OSD
```

- Press **Fn+P**: switches automatically and shows a notification.
- The power mode in GNOME/KDE/Deepin is also synced bidirectionally with Fn+P.
- Service: `systemctl status honorfnpp`;
  logs: `journalctl -u honorfnpp -f`.

## Uninstall

```bash
sudo ./uninstall.sh
# including /etc/honorfnpp.conf:
sudo ./uninstall.sh --purge
```

## Adding support for a new model (PRs welcome)

Hardware differences live in `devices/*.json`; adding a model does not require
changing Python code:

1. Follow [`docs/adding-device.md`](docs/adding-device.md) to collect DMI, the
   EC offset, and `WMAA`/`GTUB`/`STUB`.
2. Copy the template:
   ```bash
   cp devices/_template.json devices/<id>.json
   ```
3. Validate:
   ```bash
   python3 tools/validate_devices.py devices
   ```
4. Test on the machine:
   ```bash
   sudo HONORFNPP_DEVICE_PROFILE="$PWD/devices/<id>.json" ./bin/honorfnpp check
   ```
5. Submit using the PR template: include the `check` output, a DSDT snippet,
   and (for `verified`) measured data.

Start with status `experimental`; change it to `verified` after hardware
validation. See [`CONTRIBUTING.md`](CONTRIBUTING.md) and
[`devices/README.md`](devices/README.md).

## References

- [Wintego/Honor-PC-Helper](https://github.com/Wintego/Honor-PC-Helper)
- [aymanbagabas/Huawei-WMI](https://github.com/aymanbagabas/Huawei-WMI)
- [colorcube/Linux-on-Honor-Magicbook-14-Pro](https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro)

## License

MIT
