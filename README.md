# Race Circuit for Garmin Venu 3

An independent, configurable race-training companion for a common eight-run,
eight-station fitness-race format. It can also time a single workout station.

This project is unaffiliated with and not endorsed by any race organizer or
fitness brand. Product and company names are intentionally omitted from the app.

## Features

- Full race or single-station mode
- Women/Men and Open/Pro load presets
- 25%, 50%, or 100% distance and repetition scaling
- Freely reorderable workout stations
- Current segment, segment time, total time, and progress
- Large, color-coded live heart-rate display
- Division-specific loads and scaled distances/repetitions
- Vibration feedback for heart-rate thresholds and segment changes
- Undo protection for accidental segment changes
- Post-session timing summary
- Exit by swiping right before a session starts

Distances are timed from manual segment changes, so the app also works indoors
without reliable GPS. The app does not record a FIT activity and does not persist
session results.

## Controls

- Swipe in setup: change selection
- Start key: confirm a selection
- Start key on the order screen: enter or leave move mode
- Swipe in move mode: move the selected station
- Menu key on the order screen: finish setup
- Swipe right before starting: exit the app
- Start key during training: start or advance to the next segment
- Back key twice within two seconds during training: undo one segment
- Menu key after finishing: reset the session

## Requirements

- Garmin Connect IQ SDK Manager with the Venu 3 device package
- Java runtime supported by the installed Connect IQ SDK
- A local Connect IQ developer key

## Build

```powershell
.\build.ps1
```

The developer key is generated locally when needed and is excluded from Git.
The resulting `bin/RaceCircuit.prg` file is also excluded from Git.

## Install on a Venu 3

Connect the watch by USB and copy `bin/RaceCircuit.prg` to
`Internal Storage/GARMIN/Apps`.

## Privacy

The app has no network integration, account system, analytics, or embedded user
identity. It reads live heart-rate sensor data only while the app is open.
