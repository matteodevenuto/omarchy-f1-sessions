# F1 Sessions for Omarchy

![License](https://img.shields.io/badge/license-MIT-green)

A status-bar widget for [Omarchy](https://omarchy.org/) that counts down to the
next Formula 1 session and lists every upcoming race weekend with full session
schedules.

![preview](preview.png)

## Features

- **Bar countdown** to the next F1 session — right-click cycles what it shows:
  next session (`SPRINT 12:00`), time-only, race-weekend view (`NED GP Sat`),
  or logo-only.
- **Schedule popup** listing all upcoming GPs grouped by weekend and day, with
  emoji flags, city/country, live highlighting (`● LIVE`), and the next session
  pinned at the top.
- **Session alerts** — toggle the 🔔 in the panel corner to get a desktop
  notification 5 minutes before each session starts. A test notification fires
  when you enable it.
- **Resilient data** — pulls from [OpenF1](https://openf1.org/) and falls back
  to [Jolpica](https://github.com/jolpica/jolpica-f1) automatically if OpenF1
  is unavailable. The footer shows which source is live.
- **Timezone aware** — all times render in your local timezone and re-render
  when it changes.
- Rolls over to the next season's calendar once the current one ends.

## Install

```bash
omarchy plugin add https://github.com/matteodevenuto/omarchy-f1-sessions.git
```

Then open the **Plugin Manager** (or `omarchy plugin list`) and enable
**F1 Sessions** on the bar — or:

```bash
omarchy plugin enable matteodevenuto.f1-sessions right
```

## Usage

| Input | Action |
|---|---|
| Left-click | Open/close the schedule panel |
| Right-click | Cycle bar display mode |
| Middle-click | Refresh schedule now |
| 🔔 (panel, bottom-right) | Toggle session alerts |

### IPC

```bash
omarchy-shell matteodevenuto.f1-sessions toggle    # open/close panel
omarchy-shell matteodevenuto.f1-sessions refresh   # refetch schedule
omarchy-shell matteodevenuto.f1-sessions cycleDisplay
```

## Settings

Settings live in the widget entry of `~/.config/omarchy/shell.json`
(`bar.layout.*` → the widget object):

| Key | Default | Description |
|---|---|---|
| `refreshMinutes` | `60` | Schedule refresh interval |
| `daysAhead` | `21` | How many days of upcoming sessions to show |
| `hideWhenQuiet` | `false` | Hide the bar widget when nothing is scheduled in range |
| `use24h` | `true` | 24-hour times |
| `displayMode` | `"next"` | Bar label mode (`next`, `time`, `weekend`, `logo`) |
| `notifications` | `true` | Alert 5 minutes before each session |

## Screenshots

![Panel](docs/screenshot-panel.png)

![Bar and panel](docs/screenshot-bar.png)

## Data sources & disclaimer

Schedule data comes from [OpenF1](https://openf1.org/) with automatic failover
to the Ergast-compatible [Jolpica API](https://api.jolpi.ca/). Thanks to both
projects.

This plugin is unofficial and not associated with Formula 1, the FIA, or any
of their subsidiaries. F1, FORMULA ONE, FIA FORMULA ONE WORLD CHAMPIONSHIP,
GRAND PRIX and related marks are trademarks of Formula One Licensing B.V.
The bundled logo is used solely for identification and comes from
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Formula_One_logo.svg).

## Development

The plugin lives in `~/.config/omarchy/plugins/matteodevenuto.f1-sessions/`.
Edits hot-reload — no shell restart needed. Validate changes with:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/matteodevenuto.f1-sessions
```

## License

[MIT](LICENSE)
