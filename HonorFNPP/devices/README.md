# Device profiles

Each JSON file in this directory describes one HONOR MagicBook model: where
its EC performance bit lives, which ACPI WMI method controls it, and what the
project has verified.

The daemon loads every `*.json` here and picks the profile whose `match`
block matches the running machine's DMI. If nothing matches, it falls back to
the legacy defaults (`EC 0xDC`, `\_SB.WMI1.WMAA`, group `0x04`, commands
`0x0e`/`0x0f`) and prints a warning.

## Adding a model

1. Run `sudo honorfnpp check` on the machine.
2. Follow [`docs/adding-device.md`](../docs/adding-device.md) to find the EC
   offset and the WMAA/GTUB/STUB values.
3. Copy `_template.json` to `<dmi-product-lowercase>.json`, fill it in, and
   validate:

   ```bash
   python3 tools/validate_devices.py devices
   ```

4. Test it locally:

   ```bash
   sudo HONORFNPP_DEVICE_PROFILE=devices/<file>.json ./bin/honorfnpp check
   ```

5. Open a PR using the device template. See [`CONTRIBUTING.md`](../CONTRIBUTING.md).

`_template.json` is skipped by the validator; do not use it as a real profile.

## Status

| Status | Meaning |
|---|---|
| `verified` | Tested on hardware; power numbers and `check` output are in the PR |
| `experimental` | Profile matches the DSDT but has not been fully tested |
| `unknown` | Placeholder or incomplete; do not ship as verified |

## Fields

| Field | Required | Description |
|---|---|---|
| `id` | yes | Lowercase slug; must match the filename |
| `name` | yes | Human-readable model name |
| `status` | yes | `verified`, `experimental` or `unknown` |
| `match.dmi_vendor` | yes | Usually `HONOR` |
| `match.dmi_product` | yes | `/sys/class/dmi/id/product_name` |
| `match.dmi_board` | no | `/sys/class/dmi/id/board_name` |
| `match.dmi_bios` | no | String or list of BIOS versions |
| `ec.device` | yes | EC debugfs file, usually `/sys/kernel/debug/ec/ec0/io` |
| `ec.offset` | yes | Byte offset of `TUBF` (hex string) |
| `acpi.wmaa_path` | yes | ACPI path to the WMI method |
| `acpi.group` | yes | `WMAA` input byte 0 (hex) |
| `acpi.get_command` | yes | `GTUB` command byte (hex) |
| `acpi.set_command` | yes | `STUB` command byte (hex) |
| `defaults.poll_interval` | no | Seconds; default `0.5` |
| `defaults.notify_app` | no | Notification app name; default `HONOR` |
| `tested` | for `verified` | BIOS, distro, kernel, measured watts |
| `notes` | no | Free-form notes |

## Current profiles

| ID | DMI product | CPU | Status |
|---|---|---|---|
| `fri-hxx` | `FRI-HXX` | Ryzen 7 7840HS | verified |
