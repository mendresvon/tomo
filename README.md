# Tomo

A Pomodoro timer for macOS with a blocky pixel-art tomato pet. Tomo floats above every app, on every desktop, and over full-screen apps.

- **Focus:** Tomo puts on a headband and types on a tiny laptop.
- **Break:** Tomo sways and sips tea.
- **Paused:** Tomo sleeps.
- **Phase end:** Tomo jumps with sparkles, plays a sound, and shows a notification.

## Build and run

You need macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not required.

```bash
./scripts/build.sh
```

```bash
open build/Tomo.app
```

To copy the app to `~/Applications` so you can open it from Spotlight:

```bash
./scripts/build.sh --install
```

## Use

| Action | How |
| --- | --- |
| Start or pause | Click Tomo, or press ⌃⌥P in any app |
| Skip to the next phase | ⌃⌥S, or right-click > Skip |
| Hide or show Tomo | ⌃⌥T |
| Move Tomo | Drag it |
| Settings, reset, quit | Right-click Tomo |
| Change the shortcuts | Right-click > Settings, click a shortcut, then press the new keys |

Tomo has no Dock icon. If you hide it and forget the shortcut, open the app again and Tomo comes back.

To start a focus round as Tomo opens:

```bash
open ~/Applications/Tomo.app --args --start
```

## Resource use

Tomo is made to stay open all day at almost no cost:

- It uses plain AppKit and Core Animation, with no SwiftUI.
- The pet animation is a looping Core Animation keyframe animation. The system compositor plays it, so Tomo's own code does no work per frame.
- With no timer running, Tomo has no timers at all and uses no CPU.
- While a timer runs, Tomo wakes once a second to update the time. When Tomo is hidden or covered, it wakes only when the phase ends.

On an Apple silicon Mac, Tomo uses about 0% CPU when idle, about 0.2% while a timer runs, and about 11 MB of memory.

## Test

```bash
./scripts/test.sh
```

## Project layout

| Path | What it does |
| --- | --- |
| `Sources/TomoCore/TimerEngine.swift` | Pomodoro state machine. Time left comes from a fixed end date, so it stays correct after sleep. |
| `Sources/Tomo/FloatingPanel.swift` | The always-on-top, transparent panel. |
| `Sources/Tomo/Sprites.swift` | Tomo's pixel art as text grids, one character per pixel. Edit these to change the art. Each frame is rendered once to a tiny cached image. |
| `Sources/Tomo/PetView.swift` | The pet, time badge, progress bar, click, drag, and right-click menu, drawn with Core Animation layers. |
| `Sources/Tomo/SettingsWindow.swift` | The Settings window (AppKit): durations, alerts, size, launch at login, and shortcuts. |
| `Sources/Tomo/AlertService.swift` | Sound and notification at the end of a phase. |
| `Sources/Tomo/HotKeys.swift` | Global shortcuts you can change in Settings (Carbon hot keys, no Accessibility permission needed). |
| `Sources/Tomo/Export.swift` | `--export-sprites`, `--export-window`, `--export-icon`, and `--export-settings` image export. |

To preview art changes without launching the app:

```bash
./scripts/build.sh && build/Tomo.app/Contents/MacOS/Tomo --export-sprites .build/preview
```

## Notes

- The build uses `swiftc` directly because Swift Package Manager is broken in the current Command Line Tools install. `Package.swift` is still here, so you can open the project in Xcode later.
- The release build uses `-O -wmo`, dead-code stripping, and `strip -x` to keep the app small.
