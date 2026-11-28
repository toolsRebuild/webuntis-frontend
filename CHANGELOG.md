# Changelog

All notable changes to this project. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-28

The `untis` CLI now comes with the app: no Python, pipx or Chromium to
install before you can see your real timetable.

### Added

- Every release ships the `untis` CLI 1.1.0 (the Go version from
  [webuntis-scraper](https://github.com/toolsRebuild/webuntis-scraper/releases/tag/v1.1.0))
  next to the app: as a second sidecar in the desktop app, and in the
  portable folders and every web edition archive. Its version is pinned in
  `UNTIS_CLI_VERSION`; the release build downloads exactly that release
  and checks it against its `SHA256SUMS`.
- With the default executable `untis`, the app runs the bundled CLI and
  only falls back to the one in your `PATH` when there is none. A path in
  **Settings › Data source › Executable** still wins.
- The update button replaces the bundled CLI together with the app.

### Changed

- The release workflow publishes the release right away instead of
  leaving a draft.
- The "untis CLI not found" message points to the webuntis-scraper
  downloads instead of `pipx`.

### Known limits

- The bundled Go CLI logs in over plain HTTP only. Accounts that need the
  browser login (2FA, SSO) keep using the Python CLI: set its path in
  **Settings › Data source › Executable**.

## [1.1.1] - 2026-11-27

The first release that reaches 1.1.0 through the update button: press
**Update to 1.1.1** in the top bar instead of downloading it by hand.

### Fixed

- Changes found while no window was open are no longer lost. The backend
  keeps the last 50 change events, and a window that reconnects (the web
  edition's tab reopened, the app waking from sleep, the first refresh
  racing the page at startup) receives the ones it missed.
- Quiet hours work across midnight (22:00 to 6:30) and accept times like
  `22`, `22.00` or `6:30`. The fields save the time as HH:MM and mark
  input that is not a time instead of saving it.
- Timetable: an invalid `?date=` in the address (a typo in a bookmark) no
  longer freezes the app; the view falls back to today.

## [1.1.0] - 2026-11-13

The app can now update itself. Version 1.0.0 has no updater, so this
release has to be installed by hand once; later versions arrive through
the update button (see "Updating" in the installation guide).

### Added

- Update button: the app looks for a newer release once a day and shows
  an **Update to …** button in the top bar when there is one. Pressing it
  downloads the file that matches the platform and the way the app was
  installed, verifies it against the release's `SHA256SUMS` and installs
  it: AppImage, portable folders and the web edition are replaced in
  place and restarted, Windows installers and the macOS disk image are
  opened, `.deb`/`.rpm` packages are downloaded with the command to
  install them. Nothing is downloaded before the button is pressed.
- **Settings › General › Check for updates** switches the daily check off;
  **Status** shows the result of the last check and has **Check now**.
- Portable archives contain a `portable.txt` marker, and
  `untisd -version` of the web edition names the archive it came from.

### Fixed

- Timetable: stepping to another week or day no longer rebuilds the whole
  view, jumps back to the top and drops the keyboard focus.
- Status: last refresh, next refresh and last error follow background
  refreshes instead of going stale.
- A request that is cancelled (a closed or reloaded window) no longer
  fails the refresh it shared a CLI call with, which showed "untis did
  not answer in time" for a healthy backend.
- Settings written in quick succession can no longer leave the backend on
  the older one, e.g. on sample data after switching to the untis CLI.

## [1.0.0] - 2026-10-21

First release.

### Added

- Desktop app for Windows, macOS and Linux (Tauri) and a web edition
  (`untisd -web`) that runs in the browser on every platform Go supports,
  including FreeBSD, OpenBSD, NetBSD and DragonFly BSD.
- Go backend that drives the `untis` CLI, with a built-in, fully fictional
  sample school so the app works without an account.
- Dashboard with configurable widgets: now & next, agenda, upcoming
  changes, week stats, exams, homework, absences, messages, next break and
  recent notifications.
- Timetable by week or day with a period or true-time scale, parallel
  groups, merged double lessons, a current-time line, holidays and lesson
  details.
- Exams, homework, absences, messages and holidays views; local "done" and
  "read" marks.
- Change notifications (in-app and desktop) per change type, with quiet
  hours and grouping.
- Subject names, colours, emoji, hiding and only/except filters.
- Theme engine: modes, palettes, presets, accent and state colours, four
  state styles, fonts, density, radius, custom CSS.
- English and German; first day of week, 12/24 h clock, date format,
  relative dates.
- Command palette (Ctrl/Cmd+K) and rebindable keyboard shortcuts,
  including two-key sequences.
- 127 settings in 20 sections, with search, import, export and reset.

[1.2.0]: https://github.com/toolsRebuild/webuntis-frontend/releases/tag/v1.2.0
[1.1.1]: https://github.com/seesee010/webuntis-frontend/releases/tag/v1.1.1
[1.1.0]: https://github.com/seesee010/webuntis-frontend/releases/tag/v1.1.0
[1.0.0]: https://github.com/seesee010/webuntis-frontend/releases/tag/v1.0.0
