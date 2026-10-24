# Adding support for a new device

This project keeps hardware differences in JSON profiles under `devices/`.
Adding a model should not require changing Python code: find the EC/WMI
values, describe them in a profile, test, and open a PR.

If you do not have the values yet, open a **Device support request** issue
first; the template asks for the same data.

## 1. Collect the basics

```bash
cat /sys/class/dmi/id/sys_vendor
cat /sys/class/dmi/id/product_name
cat /sys/class/dmi/id/board_name
cat /sys/class/dmi/id/bios_version
sudo ./bin/honorfnpp check
```

Use `product_name` for `match.dmi_product`. Most HONOR laptops report
`sys_vendor = HONOR`.

## 2. Find the EC performance bit

Dump and disassemble the ACPI tables:

```bash
mkdir -p /tmp/acpi && cd /tmp/acpi
sudo acpidump -b
for f in *.dat; do iasl -d "$f"; done
grep -n 'TUBF\|Method (GTUB\|Method (STUB' dsdt.dsl ssdt*.dsl
```

Look for:

```asl
OperationRegion (ERM2, EmbeddedControl, Zero, 0xFF)
Field (ERM2, ByteAcc, Lock, Preserve)
{
    Offset (0xDC),
    TUBF,   1
}
```

`0xDC` is `ec.offset`. The bit is usually bit 0 (0 = smart, 1 = performance).

Confirm with the running EC:

```bash
sudo xxd -p -s 0xDC -l 1 /sys/kernel/debug/ec/ec0/io
```

## 3. Find the WMI method and commands

```bash
grep -n 'Device (WMI\|Method (WMAA\|Name (_UID' ssdt*.dsl
grep -n 'Method (GTUB\|Method (STUB' dsdt.dsl
```

- `acpi.wmaa_path`: the device path plus `.WMAA`, e.g. `\_SB.WMI1.WMAA`.
- `acpi.group`: the `MFID` case that handles `GTUB`/`STUB` (usually `0x04`).
- `acpi.get_command`: the `SFID` for `GTUB` (usually `0x0E`).
- `acpi.set_command`: the `SFID` for `STUB` (usually `0x0F`).

If the DSDT shows different values, use those in the profile.

## 4. Create the profile

Copy the template:

```bash
cp devices/_template.json devices/<product-name-lowercase>.json
```

Example (this is the tested FRI-HXX profile):

```json
{
  "id": "fri-hxx",
  "name": "HONOR MagicBook X 14 Pro (2024, Ryzen 7 7840HS)",
  "status": "experimental",
  "match": {
    "dmi_vendor": "HONOR",
    "dmi_product": "FRI-HXX"
  },
  "ec": {
    "device": "/sys/kernel/debug/ec/ec0/io",
    "offset": "0xDC"
  },
  "acpi": {
    "wmaa_path": "\\_SB.WMI1.WMAA",
    "group": "0x04",
    "get_command": "0x0E",
    "set_command": "0x0F"
  },
  "defaults": {
    "poll_interval": 0.5,
    "notify_app": "HONOR"
  },
  "tested": {
    "bios": "1.15",
    "distro": "Debian 13",
    "kernel": "7.2.6",
    "balanced_w": 35,
    "performance_w": 45,
    "desktop": ["GNOME"]
  },
  "notes": "EC TUBF bit at 0xDC.0."
}
```

- The `id` must match the filename.
- Start with `"status": "experimental"`.
- After testing, change to `"verified"` and fill `tested` with real numbers.
- See [`devices/README.md`](../devices/README.md) for every field.

## 5. Validate

```bash
python3 tools/validate_devices.py devices
```

This checks required fields, hex ranges, duplicate IDs, and that `verified`
profiles carry BIOS/distro/kernel and measured 35/45 W values.

## 6. Test on the machine

Stop the daemon so it does not fight your test:

```bash
sudo systemctl stop honorfnpp
sudo HONORFNPP_DEVICE_PROFILE="$PWD/devices/<file>.json" ./bin/honorfnpp check
sudo HONORFNPP_DEVICE_PROFILE="$PWD/devices/<file>.json" ./bin/honorfnpp on
sudo HONORFNPP_DEVICE_PROFILE="$PWD/devices/<file>.json" ./bin/honorfnpp status
```

Confirm:

- `EC TUBF` changes 0 → 1 and back.
- `platform_profile` changes balanced → performance and back.
- `ACPI GTUB` returns the same value as the EC bit.
- Fn+P still toggles the EC bit (the daemon is stopped, so only the EC changes).

Then start the service again:

```bash
sudo systemctl start honorfnpp
```

### Power test

```bash
sudo env CMD="$PWD/bin/honorfnpp" \
     HONORFNPP_DEVICE_PROFILE="$PWD/devices/<file>.json" \
     ./tools/power-test.sh
```

Record the sustained `PkgWatt` for balanced and performance. These are the
numbers for `tested.balanced_w` / `tested.performance_w`. Thermal limits can
make the numbers lower than the firmware target; note that in `notes`.

## 7. Open the PR

```bash
git checkout -b device/<id>
git add devices/<id>.json
python3 tools/validate_devices.py devices
git commit -m "devices: add <model>"
git push -u origin device/<id>
```

Open the PR with the repository's PR template. Include:

- `sudo ./bin/honorfnpp check` output.
- The DSDT snippet with `TUBF`, `GTUB`, `STUB`, `WMAA`.
- Power numbers for balanced and performance.
- Desktop(s) tested (GNOME/KDE/Deepin).
- Anything that did not work.

A profile is usually accepted as `experimental` if the DSDT evidence is
consistent but the hardware test is incomplete, and as `verified` once the
power numbers and Fn+P behavior are confirmed.

## Safety

- Do not flash the BIOS or patch DSDT just to add a profile.
- Do not write EC RAM directly; use the firmware's `STUB` method.
- Keep the test changes reversible: the daemon can always be stopped, and the
  EC mode can be set back to smart.
