# Contributing

Thanks for helping make more HONOR MagicBook models work on Linux.

## Ways to contribute

- **Add a device profile** for a new MagicBook model (most useful).
- Improve KDE/Deepin/GNOME OSD handling.
- Fix bugs or documentation.
- Test an existing `experimental` profile and report power numbers.

## Add a device

Read [`docs/adding-device.md`](docs/adding-device.md). In short:

1. Collect DMI and `honorfnpp check` output.
2. Find the EC `TUBF` offset and the `WMAA`/`GTUB`/`STUB` values in the DSDT.
3. Copy `devices/_template.json` to `devices/<id>.json` and fill it in.
4. Validate:

   ```bash
   python3 tools/validate_devices.py devices
   ```

5. Test on the machine with `HONORFNPP_DEVICE_PROFILE=...` (details in the guide).
6. Open a PR with the template.

If you do not have all the data yet, open a **Device support request** issue;
that is still useful.

## Development setup

```bash
git clone <repo-url> HonorFNPP
cd HonorFNPP
make validate
make test
make lint
```

Run the daemon/CLI from the checkout:

```bash
sudo ./bin/honorfnpp check
sudo ./bin/honorfnpp status
sudo ./bin/honorfnpp notify-test
```

Install locally:

```bash
sudo ./install.sh
```

## Validation

Every PR must pass:

```bash
make validate   # device profiles
make test       # py_compile + bash -n
make lint       # shellcheck, if installed
```

CI runs the same checks. Hardware tests cannot run in CI; include the evidence
in the PR instead.

## Device profile policy

- `experimental`: the DSDT evidence is consistent, but the hardware test is
  incomplete. This is fine for a first PR.
- `verified`: Fn+P works, the EC bit and `platform_profile` change, and the
  sustained power numbers are measured. Fill `tested` with BIOS, distro,
  kernel, and balanced/performance watts.
- Do not mark a profile `verified` based only on the DSDT.
- Do not include serial numbers, UUIDs, MAC addresses, or other personal data.

## Pull request checklist

- [ ] `python3 tools/validate_devices.py devices` passes.
- [ ] `make test` and `make lint` pass.
- [ ] New model tested with `HONORFNPP_DEVICE_PROFILE=...` (or a clear note why not).
- [ ] `check` output and DSDT snippet attached for a new device.
- [ ] Power numbers attached for `verified`.
- [ ] No BIOS flashing, DSDT override, or direct EC RAM writes.
- [ ] README/docs updated if behavior changed.

## Code style

- Python: standard library only for the runtime script and validator.
- Shell: `bash -n` and `shellcheck` clean.
- Keep the daemon small and dependency-light; KDE/Deepin support should remain
  fallback-based rather than requiring a specific desktop package.
- Do not add a kernel module requirement. `acpi_call` remains optional for
  read-only Fn+P sync.

## Commit messages

Short and scoped, for example:

```
devices: add HONOR MagicBook X 16 Pro (FRI-H76)
daemon: retry PPD writes after suspend
docs: document Deepin OSD limitations
```

## License

By contributing, you agree that your changes are licensed under the MIT
License (see [`LICENSE`](LICENSE)).
