## What changed

- [ ] New device profile in `devices/`
- [ ] Runtime/daemon change
- [ ] OSD/desktop change (GNOME / KDE / Deepin)
- [ ] Documentation / CI

## Device (for new profiles)

- Model:
- DMI vendor / product:
- BIOS:
- Distro / kernel:
- Desktop(s):
- Profile ID:
- Status: `experimental` / `verified`

## Evidence

- [ ] `python3 tools/validate_devices.py devices`
- [ ] `make test`
- [ ] `make lint`
- [ ] `sudo honorfnpp check` output attached
- [ ] DSDT snippet with `TUBF`, `GTUB`, `STUB`, `WMAA` attached
- [ ] Fn+P toggles the EC bit on the machine
- [ ] Power numbers for balanced / performance (for `verified`)

```text
# check output
```

```text
# power test output
```

## Notes

Anything unusual: BIOS quirks, thermal limits, desktop-specific behavior,
what still does not work.
