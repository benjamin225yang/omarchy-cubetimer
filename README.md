# Cube Timer

A speedcubing timer that lives in the Omarchy bar. Hold space, release, solve,
hit anything to stop.

Press `f` for solo mode — the clock on its own surface over everything, bar
included.

## What it does that cstimer doesn't

- **A pace line.** Between solves it tells you what the next one has to beat to
  move your best Ao5 — `PB Ao5 needs ≤ 11.23` — including the two cases that
  read differently: when even a DNF would still beat it, and when it is already
  out of reach. cstimer leaves you to work that out from the table afterwards.
- **Personal bests as desktop notifications.** A record single, Ao5, or Ao12
  fires a `notify-send`, so it lands even with the panel closed.
- **Scramble previews for every NxN from 2 to 7**, drawn from a real facelet
  simulation rather than a lookup of small cases.
- **It is a bar widget**, not a browser tab. It themes itself from Omarchy, and
  a keybinding opens it over whatever you are doing.
- **A real fullscreen solo mode** on its own layer surface — it covers the bar
  too, takes the keyboard exclusively so nothing leaks to the window behind,
  and keeps a running solve going as you move in and out of it.

Everything you'd expect from cstimer is here too: WCA inspection with the +2
and DNF rules, `+2`/`DNF`/delete penalties, multiple sessions, per-solve notes,
rolling and best Ao5/Ao12/Ao50/Ao100, a distribution histogram, and CSV export.

## Install

```bash
omarchy plugin add https://github.com/benjamin225yang/omarchy-cubetimer.git --enable
```

That drops it into `~/.config/omarchy/plugins/` and puts the widget in the bar.
If you skip `--enable`, add `{"id": "pyang.cubetimer"}` to the bar layout in
`~/.config/omarchy/shell.json` yourself.

Optional keybinding — `SUPER + ALT + C`, refuses to clobber a key already in
use:

```bash
~/.config/omarchy/plugins/pyang.cubetimer/install-bindings
```

Later, to pick up changes:

```bash
omarchy plugin update pyang.cubetimer
```

## Keys

| Key | Does |
| --- | --- |
| `space` hold, then release | Start the solve (or inspection first, if enabled) |
| any key | Stop the solve |
| `esc` | Backs out one layer: discard a running solve, then leave fullscreen, then close the panel |
| `tab` / `shift-tab` | Cycle tabs; `1` `t` `3` `4` jump straight to one |
| `2` | Toggle +2 on the solve |
| `d` | Toggle DNF |
| `x` / `backspace` | Delete the solve |
| `f` | Fullscreen solo mode — `f` or `esc` comes back |
| `s` | New scramble |
| `e` | Export the session as CSV |
| `↑` `↓` | Pick a solve on the Times tab |
| `enter` | Re-use that solve's scramble — the quickest way to retry a case |
| `n` | Add a note to the selected solve |

On the Times tab the penalty keys act on the selected solve; everywhere else
they act on the most recent one.

## IPC

```bash
omarchy-shell pyang.cubetimer toggle
omarchy-shell pyang.cubetimer tab stats     # jump straight to a tab
omarchy-shell pyang.cubetimer scramble      # new scramble without opening
omarchy-shell pyang.cubetimer fullscreen    # straight into solo mode
omarchy-shell pyang.cubetimer windowed      # and back out
```

Solo mode holds the keyboard exclusively while it is up, which is the point —
a key pressed mid-solve must not reach the window underneath. Three ways out:
`esc`, `f`, or clicking the widget in the bar.

## Settings

Change anything on the Settings tab and it is saved immediately. Defaults come
from this widget's entry in `~/.config/omarchy/shell.json`, so the settings you
want everywhere can travel in your dotfiles:

```jsonc
{
  "id": "pyang.cubetimer",
  "puzzle": "333",          // 222 333 444 555 666 777 333oh 333bld
                            // pyram skewb mega sq1 clock
  "scrambleLength": 0,      // 0 = the event's own default
  "scrambler": "",          // external command; its stdout is the scramble
  "inspection": false,      // WCA 15s inspection
  "inspectionSeconds": 15,
  "holdMs": 300,            // how long space must be held before it arms
  "decimals": 2,            // 2 or 3
  "hideWhileRunning": false,
  "showPreview": true,
  "targetSeconds": 0,       // highlight solves at or under this; 0 = off
  "notifyPB": true,
  "barDisplay": "last",     // icon | last | ao5 | count
  "timerScale": 1.0,
  "cubeColors": ["#e9e9e7", "#c0392b", "#2a9245", "#d9b61c", "#d2691e", "#2b6cb0"]
}
```

Precedence is **config.json > shell.json > built-in default**. `puzzle` is the
exception: it seeds the first session and nothing else, because after that the
event belongs to the session — averaging a 2x2 time into a 5x5 Ao12 would be
nonsense, so the two travel together. Changing the event on the Settings tab
changes the current session's event. Each solve still records the event it was
done on, so an export stays truthful even for a session you switched midway.

## Scrambles

The built-in scrambler produces **random-move** scrambles, not the
**random-state** ones the WCA requires. The panel says so under every scramble
rather than letting you assume otherwise. A random-state scrambler picks a
position uniformly from the whole group and solves backwards into it, which
needs a two-phase solver and multi-megabyte tables — not something to build at
shell startup. The move counts here are at the generous end of convention to
keep the distribution close to uniform, and the generator refuses sequences
that collapse to something shorter (no repeated layer within a run of moves
that commute).

If you want the real thing, point `scrambler` at a command that prints one
scramble on stdout and its output is used verbatim:

```jsonc
"scrambler": "tnoodle-scramble 333"
```

## Where your data lives

| Path | What |
| --- | --- |
| `~/.local/state/pyang.cubetimer/sessions.json` | every solve — the one file here you can't regenerate |
| `~/.local/state/pyang.cubetimer/config.json` | settings changed at runtime |
| `~/cubetimer-<session>.csv` | written by Export CSV |

A corrupt sessions.json is repaired field by field rather than discarded, and
nothing is written until the existing file has been read, so a slow read can't
truncate a session you've been building for weeks.

## Layout

| File | What |
| --- | --- |
| `Cube.js` | NxN facelet simulator for the preview — stickers are points with normals, rotated in 3D, so there are no hand-written strip cycles to get wrong |
| `Scramble.js` | scramble generation for all thirteen events |
| `Stats.js` | WCA averages, formatting, the pace calculation, session file format |
| `Panel.qml` | bar widget, key dispatch, timer state machine, persistence |
| `TimerTab.qml` `TimesTab.qml` `StatsTab.qml` `SettingsTab.qml` | the four tabs |
| `FullscreenTimer.qml` | the solo-mode surface |

The clock text, pace line, sparkline and preview net are computed once on the
panel root, so the card and the fullscreen view cannot disagree about what the
session looks like.

## Licence

MIT.
