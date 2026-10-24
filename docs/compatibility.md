# Compatibility and porting

## Tested

| Model | DMI product | CPU | BIOS | Distro / kernel | Result |
|---|---|---|---|---|---|
| HONOR MagicBook X 14 Pro | `FRI-HXX` | Ryzen 7 7840HS | 1.15 | Debian 13 / 7.2.6 | Fn+P + 35/45 W verified |

The project is intentionally conservative: it polls the EC and does not patch
the kernel. That makes it easy to test on other MagicBook models.

## Recommended: add a device profile

Put the values in `devices/<id>.json`; see
[`docs/adding-device.md`](adding-device.md). The rest of this document
explains how to find those values. The `EC_OFFSET`/`WMAA_*` keys in
`/etc/honorfnpp.conf` remain available as advanced overrides.

## Requirements

A machine needs:

1. `ec_sys` debugfs (`/sys/kernel/debug/ec/ec0/io`).
2. An EC `TUBF` bit whose value selects smart/performance.
3. A HONOR WMI method (`WMAA` or equivalent) with `GTUB`/`STUB` to read/write
   that bit.
4. ACPI `platform_profile` support (AMD PMF) for the 45 W side.

Run:

```bash
sudo honorfnpp check
```

Expected output on a supported machine:

```
DMI vendor       : HONOR
DMI product      : FRI-HXX
EC TUBF          : 0 (smart)
acpi_call        : yes
ACPI GTUB        : 0
platform_profile : balanced
profile choices  : low-power balanced performance
notify-send      : yes
powerprofilesctl : yes
```

If `ACPI GTUB` fails, the WMAA path or group/command may differ.

## Finding the EC offset

Dump and disassemble ACPI:

```bash
mkdir -p /tmp/acpi && cd /tmp/acpi
sudo acpidump -b
for f in *.dat; do iasl -d "$f"; done
grep -n 'TUBF\|Method (GTUB\|Method (STUB' dsdt.dsl ssdt*.dsl
```

Look for a field like:

```asl
OperationRegion (ERM2, EmbeddedControl, Zero, 0xFF)
Field (ERM2, ByteAcc, Lock, Preserve)
{
    Offset (0xDC),
    TUBF,   1
}
```

Put `0xDC` (or the value you find) into the profile's `ec.offset` (or set
`EC_OFFSET` as an advanced override in `/etc/honorfnpp.conf`), then
restart the service.

Do **not** write the EC byte directly. Use the ACPI `STUB` method so the
firmware performs its own read-modify-write and any side effects.

## Finding the WMAA path

Find the `PNP0C14` device that owns the `WMAA` method and its `_UID`:

```bash
grep -n 'Device (WMI1\|Name (_UID\|Method (WMAA' ssdt*.dsl
```

On FRI-HXX:

```asl
Device (WMI1)
{
    Name (_HID, EisaId ("PNP0C14"))
    Name (_UID, "HWMI")
    Method (WMAA, 3, Serialized) { ... }
}
```

The ACPI path is `\_SB.WMI1.WMAA`. Set `acpi.wmaa_path` in the profile (or
`WMAA_PATH` as an advanced override).

## Finding group/command

`WMAA` dispatches on the first two bytes of the input buffer. On FRI-HXX:

| Operation | Group | Command | Value |
|---|---|---|---|
| `GTUB` (get) | `0x04` | `0x0e` | `0x00` |
| `STUB` (set) | `0x04` | `0x0f` | `0x00` / `0x01` |

Find the `Switch (MFID)` → `Case (0x04)` → `Switch (SFID)` block in `WMAA`
and locate the `GTUB` / `STUB` calls. If another model uses different numbers,
the current script needs a model profile (the group/command are constants).

## Event codes

Fn+P events seen on HONOR models:

- `0x02a0` — smart / off
- `0x02a1` — performance / on
- `0x02a6` — toggle (some models)

The daemon does not depend on these codes because it reads the EC bit. They
matter only if you add a `huawei-wmi` keymap patch for instant input events.

## Reporting a new model

Please include:

- DMI: `sys_vendor`, `product_name`, `bios_version`
- Distro and kernel
- `sudo honorfnpp check`
- `sudo honorfnpp status --json`
- DSDT snippet with `TUBF`, `GTUB`, `STUB`, `WMAA`
- Power measurements (smart vs performance) if available

## Safety

- No DSDT override, no BIOS flash, no direct EC RAM writes.
- EC writes go through the firmware's `STUB` method (group `0x04`, command
  `0x0f`), which validates the value and performs the EC write.
- The daemon only needs read access for the EC→PPD direction; `acpi_call` is
  needed for CLI and PPD→EC.
