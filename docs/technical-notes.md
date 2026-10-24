# Technical notes

These notes document the reverse engineering behind `HonorFNPP` on a HONOR
MagicBook X 14 Pro (FRI-HXX, Ryzen 7 7840HS, BIOS 1.15, Debian 13, kernel
7.2.6). They are meant to make porting to other MagicBook models practical.
The porting procedure and profile format are in
[`adding-device.md`](adding-device.md); this file explains the underlying
ACPI/EC details.

## 1. ACPI / EC topology

Relevant objects:

| Object | Meaning |
|---|---|
| `\_SB.WMI1` | `PNP0C14`, `_UID = "HWMI"`; HONOR BIOS WMI device |
| `\_SB.WMI1.WMAA` | ACPI WMI method (`OemWMIMethod` / `OemWMIfun` in Windows) |
| EC `0xDC` bit 0 | `TUBF` performance bit (0 = smart, 1 = performance) |
| `GTUB` | get TUBF, group `0x04`, command `0x0e` |
| `STUB` | set TUBF, group `0x04`, command `0x0f` |
| WMI event `0x2a0` | Fn+P smart / off |
| WMI event `0x2a1` | Fn+P performance / on |
| WMI event `0x2a6` | Fn+P toggle (reported on some models) |

`WMAA` takes three arguments:

- `Arg0`: instance
- `Arg1`: call type (`1` for normal method calls)
- `Arg2`: 64-byte input buffer, at least `<group> <command> <value>`

The Windows driver calls the same interface as `OemWMIMethod.OemWMIfun` with a
64-byte `u8Input`, where the first three bytes are group, command and value.
`honor-pc-helper` documents this mapping.

### DSDT snippets (FRI-HXX)

```asl
OperationRegion (ERM2, EmbeddedControl, Zero, 0xFF)
Field (ERM2, ByteAcc, Lock, Preserve)
{
    Offset (0xDC),
    TUBF,   1
}

Method (GTUB, 1, NotSerialized)
{
    Name (BUFF, Buffer (0x0100){})
    Local0 = Arg0
    CreateByteField (BUFF, Zero, STAT)
    CreateByteField (BUFF, One, MODE)
    STAT = Zero
    DAIN = Local0
    MODE = \_SB.PCI0.LPC0.EC0.ECRD (RefOf (\_SB.PCI0.LPC0.EC0.TUBF))
    DAOU = BUFF
    Return (BUFF)
}

Method (STUB, 1, NotSerialized)
{
    Name (BUFF, Buffer (0x0100){})
    Local0 = Arg0
    CreateByteField (BUFF, Zero, STAT)
    STAT = Zero
    DAIN = Local0
    Name (INPT, Buffer (0x40){})
    INPT = DAIN
    If (((DerefOf (INPT [0x02]) != Zero) & (DerefOf (INPT [0x02]) != One)))
    {
        STAT = One
    }
    ElseIf ((DerefOf (INPT [0x02]) == Zero))
    {
        \_SB.PCI0.LPC0.EC0.ECWT (Zero, RefOf (\_SB.PCI0.LPC0.EC0.TUBF))
    }
    Else
    {
        \_SB.PCI0.LPC0.EC0.ECWT (One, RefOf (\_SB.PCI0.LPC0.EC0.TUBF))
    }
    Return (BUFF)
}
```

`WMAA` dispatches `MFID = input[0]`, `SFID = input[1]`:

- `MFID == 0x04`, `SFID == 0x0e` → `GTUB`
- `MFID == 0x04`, `SFID == 0x0f` → `STUB`

## 2. Reproducing the ACPI dump

```bash
mkdir -p /tmp/acpi && cd /tmp/acpi
sudo acpidump -b
for f in *.dat; do iasl -d "$f"; done
grep -n 'TUBF\|Method (GTUB\|Method (STUB\|Method (WMAA' dsdt.dsl ssdt*.dsl
grep -n 'Device (WMI1' ssdt*.dsl
```

Find the `_UID` of the `PNP0C14` device that owns `WMAA`. On FRI-HXX it is
`\_SB.WMI1` (`_UID = "HWMI"`). The WMI method GUID is
`ABBC0F6A-8EA1-11D1-00A0-C90629100000`.

## 3. ACPI calls

`acpi_call` must be loaded (`sudo modprobe acpi_call`). The 64-byte input is
written as a hex string after `b`.

### Read TUBF (GTUB)

```bash
# group 0x04, command 0x0e, value 0x00 + 61 zero bytes
sudo sh -c 'echo "\\_SB.WMI1.WMAA 0 1 b040e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > /proc/acpi/call'
sudo cat /proc/acpi/call
```

The result is a package of two buffers:

```
[{0x00, 0x00, 0x00, 0x00}, {0x00, <TUBF>, 0x00, ...}]
```

`/proc/acpi/call` returns only the first 256 formatted bytes, so the second
buffer is truncated. The parser only needs the first two bytes after `}, {`.

### Write TUBF (STUB)

```bash
# value 1 (performance): group 0x04, command 0x0f, value 0x01
sudo sh -c 'echo "\\_SB.WMI1.WMAA 0 1 b040f01000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000" > /proc/acpi/call'
```

`STUB` accepts only value 0 or 1; anything else returns `STAT = 1` and does not
change the EC. Read back `EC 0xDC` or call `GTUB` to confirm.

### Direct EC read

```bash
sudo xxd -p -s 0xdc -l 1 /sys/kernel/debug/ec/ec0/io
```

`ec_sys` is built-in on Debian's kernel (`CONFIG_ACPI_EC_DEBUGFS=y`). Each
byte read is an EC transaction; read only the byte you need.

## 4. Power matrix

Measured with `turbostat --show PkgWatt`, 12 threads of `yes`, 3 s warmup,
10 × 1 s samples, 60 s cooldown between runs, PPD stopped during the test:

| EC TUBF | platform_profile | avg PkgWatt |
|---|---|---|
| 0 | balanced | 35.00 |
| 0 | performance | 35.00 |
| 1 | balanced | 34.71 |
| 1 | **performance** | **45.00** |

Short runs can exceed these numbers because of PL2/boost; the table is the
sustained limit after the EC/PMF settings settle. At 45 W the package reached
100 °C on this chassis during the test, so sustained 45 W is thermally limited.

## 5. Why `platform_profile` alone is not enough

`/sys/firmware/acpi/platform_profile` is provided by the AMD PMF driver
(`AMDI0102`, `amd_pmf`). On this machine it is a separate knob from the HONOR
EC `TUBF` bit:

- writing `performance` with `TUBF = 0` → still 35 W
- pressing Fn+P with `platform_profile = balanced` → still 35 W

Both are gates. This is why generic advice such as "install
power-profiles-daemon" does not enable 45 W here.

`power-profiles-daemon` (PPD) writes the same `platform_profile` sysfs and
exposes it over D-Bus. The daemon uses `powerprofilesctl set` so PPD's own
state stays consistent, and reads the sysfs file for the fast path.

## 6. Fn+P event path

The EC sends a WMI event for Fn+P. On this machine the in-tree `huawei-wmi`
keymap only covers a subset of HONOR codes, so the event is logged as:

```
input input15: Unknown key pressed, code: 0x02a1
```

The event codes are `0x02a0` (off), `0x02a1` (on) and `0x02a6` (toggle,
reported on some models). Because the EC applies `TUBF` itself, the daemon does
not need these events; it detects the EC bit change by polling. This avoids a
kernel patch and works even when `huawei-wmi` ignores the key.

If you want instant key events and clean dmesg, add a keymap patch:

```c
{ KE_KEY, 0x2a0, { KEY_PROG1 } },  /* smart / off */
{ KE_KEY, 0x2a1, { KEY_PROG2 } },  /* performance / on */
{ KE_KEY, 0x2a6, { KEY_PROG3 } },  /* toggle */
```

Build `drivers/platform/x86/huawei-wmi.c` for the running kernel, install it in
`/lib/modules/$(uname -r)/updates/`, run `depmod -a`, and reboot. This is
optional; the daemon's 0.5 s poll is enough for the OSD and mode switch.

## 7. EC polling and keyboard contention

The first prototype read the whole 256-byte EC region every 0.5 s. `ec_sys`
performs one EC transaction per byte, so that was roughly 512 EC transactions
per second. The EC also serves the keyboard matrix; on this machine that
caused visible input lag and dropped keys. The fixed version reads one byte at
`0xDC` per poll (2 transactions/s) and reads `platform_profile` from sysfs
instead of spawning `powerprofilesctl` twice a second. The daemon now uses
about 0.0–0.1 % CPU.

If a future model still shows input lag, increase `POLL_INTERVAL` to 1.0 or 2.0,
or switch to an event-driven trigger (`acpi_listen` + one EC read per WMI
event).

## 8. References

- Wintego/Honor-PC-Helper — Windows `OemWMIMethod` / `OemWMIfun` command map:
  <https://github.com/Wintego/Honor-PC-Helper>
- aymanbagabas/Huawei-WMI — in-tree driver history and HONOR keymap:
  <https://github.com/aymanbagabas/Huawei-WMI>
- colorcube/Linux-on-Honor-Magicbook-14-Pro — HONOR ACPI/EC notes:
  <https://github.com/colorcube/Linux-on-Honor-Magicbook-14-Pro>
- rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010 — HONOR hotkey
  keymap patch and capture scripts:
  <https://github.com/rs0x29a/Linux-on-HONOR-MagicBook-14-Pro-2026-AI_ZQC-P_M1010>
- Linux `drivers/platform/x86/huawei-wmi.c`,
  `drivers/acpi/ec_sys.c`, `drivers/platform/x86/amd/pmf/`.
