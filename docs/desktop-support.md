# Desktop support (GNOME / KDE / Deepin)

The mode switching itself is desktop-independent: it only needs the EC and
`platform_profile`. This document covers the OSD/notification and the desktop
power-profile integration.

## Summary

| Desktop | OSD used | Power profile |
|---|---|---|
| GNOME | `notify-send` with `power-profile-*-symbolic` icons | power-profiles-daemon |
| KDE Plasma 5/6 | native Plasma OSD (`org.kde.osdService.showText`) | power-profiles-daemon / PowerDevil |
| Deepin DDE | freedesktop notification via `notify-send` (dde-osd) | power-profiles-daemon / sysfs |
| Other | `notify-send`, `kdialog` or raw `dbus-send` | PPD or sysfs |

Fallback chain: the selected backend first, then the other available
backends. A failure in one backend never blocks the next one.

## Detection

The daemon runs as root and does not inherit `XDG_CURRENT_DESKTOP`, so it
detects the desktop from running processes:

- KDE: `plasmashell`, `kwin_x11`, `kwin_wayland`
- Deepin: `dde-desktop`, `dde-dock`, `dde-shell`, `dde-session-daemon`, `startdde`,
  `treeland`
- GNOME: `gnome-shell`

Override for testing or unusual setups:

```ini
# /etc/honorfnpp.conf
DESKTOP_OVERRIDE=kde
```

or:

```bash
sudo HONOR_DESKTOP=deepin honorfnpp notify-test
```

## GNOME

```bash
sudo apt install libnotify-bin
sudo honorfnpp notify-test
```

Uses `notify-send` and the GNOME `power-profile-performance-symbolic` /
`power-profile-balanced-symbolic` icons.

## KDE Plasma

Plasma has a native OSD service:

```bash
qdbus org.kde.plasmashell /org/kde/osdService \
      org.kde.osdService.showText preferences-system-power-management \
      "高能模式 · 45W"
```

The daemon calls the same method through `dbus-send` first (no Qt/qdbus
installation needed), then falls back to `qdbus`/`qdbus6` if needed.

- Plasma 5: `qdbus`
- Plasma 6: `qdbus6` or `qdbus-qt6` (the daemon tries all three)
- `qdbus` is optional: the daemon prefers `dbus-send`, which needs no Qt
  tooling. If you want the qdbus fallback, install `kde-cli-tools` or the Qt
  DBus tools, or force `OSD_BACKEND=notify-send`.

If the Plasma OSD call fails, the daemon falls back to `notify-send`,
`kdialog`, then raw `dbus-send`.

For the KDE power-profile UI, install `power-profiles-daemon`. PowerDevil can
read/write the same `platform_profile`, and the daemon will mirror changes into
the EC `TUBF` bit.

## Deepin DDE

Deepin's `dde-osd` implements the standard
`org.freedesktop.Notifications` service, so `notify-send` works:

```bash
sudo apt install libnotify-bin
sudo honorfnpp notify-test
```

Deepin also exposes `org.deepin.dde.Osd1.ShowOSD`, but that method only accepts
a fixed enum of OSD types (`AudioUp`, `BrightnessUp`, `CapsLockOn`, ...), not
arbitrary text. It cannot display "高能模式 45W", so this project deliberately
uses the notification path on DDE.

If `power-profiles-daemon` is installed, the Deepin control center and this
daemon share `platform_profile`. If it is not installed, the daemon writes the
sysfs file directly; Fn+P and 45W still work, but the desktop UI may not show
the mode.

## Generic fallback

- `notify-send` (libnotify) — preferred on GNOME, Deepin and other DEs
- `kdialog --passivepopup` — KDE fallback
- `dbus-send org.freedesktop.Notifications.Notify` — last resort

Force a backend in `/etc/honorfnpp.conf`:

```ini
OSD_BACKEND=auto          # default
# OSD_BACKEND=kde-osd
# OSD_BACKEND=notify-send
# OSD_BACKEND=kdialog
# OSD_BACKEND=dbus
# OSD_BACKEND=none
```

## Testing

```bash
sudo honorfnpp check
sudo honorfnpp notify-test
sudo honorfnpp status --json | grep -E 'desktop|osd_backend'
```

`check` prints the detected desktop, the chosen backend and which tools are
available (`notify-send`, `kdialog`, `dbus-send`, `qdbus`).

## Troubleshooting

### KDE: no OSD, only a normal notification

The Plasma OSD call failed and the daemon fell back. Check:

```bash
journalctl -u honorfnpp -n 20 | grep -E 'kde-osd|notify'
```

Make sure `plasmashell` is running and `qdbus`/`qdbus6` is installed.

### Deepin: no notification

```bash
systemctl --user status dde-osd 2>/dev/null
notify-send "test" "hello"
```

Install `libnotify-bin` if `notify-send` is missing. If the DDE notification
service is not running, log out and back in.

### Wayland

No `DISPLAY` is needed; the daemon uses
`DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus`. `loginctl` must
report the session as `Type=wayland` and `Active=yes`.

### The desktop UI shows a different mode

The desktop and the daemon both write `platform_profile`. The daemon mirrors
any change into the EC on its next poll (0.5 s). If the desktop uses its own
EC/SMU path instead of `platform_profile`, the UI can disagree; run
`sudo honorfnpp status` to see the real EC and sysfs state.
