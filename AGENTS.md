# ComposeDeck Agent Guide

Conventions for contributors and AI agents working on ComposeDeck. User-facing documentation lives in [README.md](README.md).

## Project

ComposeDeck is a GTK4/libadwaita app for managing Docker Compose projects on Podman or Docker. It discovers compose projects in a configurable folder (default `~/Apps`), reads service state from the engine's Docker-compatible API, and provides start/stop/restart, logs, ports, orphan cleanup, and web-app shortcuts.

## Architecture

- `src/Logic/Main.vala` — entry point; runs `Logic.Application`.
- `src/Logic/Application.vala` — `Adw.Application` lifecycle. Creates the central `State`, presents `Views.Window`, and calls `ComposeDeck.start()`. Views obtain state through `Logic.Application.getState()`.
- `src/Logic/ComposeDeck.vala` — business logic and orchestration. Scans the apps folder, parses compose files, schedules refreshes, and runs app actions. It mutates `State`, then emits `State.changed`.
- `src/Logic/ComposeService.vala` — container-engine integration. Detects and activates Podman or Docker, then performs the Docker-compatible socket calls. It contains no business orchestration.
- `src/Logic/State.vala` — shared state and settings: `apps`, `selectedApp` (`null` means Overview), the computed `overviewSelected`, `actionInProgress`, `actionError`/`actionSuccess`, `engineReachable`, `refreshInterval`, `pinnedApps`, window size, and the `changed` signal.
- `src/Logic/ContainerEngine.vala`, `ComposeApp.vala`, `AppService.vala`, `AppPort.vala`, `AppShortcut.vala`, and `WebAppBrowser.vala` — engine, model, and helper types.
- `src/Views/*.vala` — GTK controllers. They own template bindings, signals, and rendering from `State`. They contain no business logic and no polling timers.

`ComposeDeck.start()` installs a one-second timeout that rediscovers apps once the configured `State.refreshInterval` (default 10 seconds) has elapsed. Views re-render when `State` emits `changed`; do not add polling timers to views.

## UI declaration

- All UI lives in `.blp` (Blueprint) files under `src/blueprints/` and compiles to `.ui` at build time. Resource IDs are filename-based, for example `/com/a2way/ComposeDeck/Window.ui`.
- Vala classes use `[GtkTemplate (ui = "...")]`, `[GtkChild]`, and `[GtkCallback]`. Do not use `Gtk.Builder`.
- Use one class per template. Prefer camelCase for project identifiers, and keep library methods under their own names.

## Layout / UX

- Follow a GNOME Settings-style layout: `Adw.NavigationSplitView` inside an `Adw.ToastOverlay`, with the sidebar spanning the full height.
- `Sidebar` owns the left `Adw.HeaderBar` (app title and hamburger menu via `Hamburger`), the search entry, and the app list. The menu contains About, Settings, and Quit.
- `ContentArea` owns the right `Adw.HeaderBar` with a dynamic title ("Overview" or the selected app) and the window controls.
- Do not repeat the same title across both headers.
- Keep header and menu widgets flat and minimally padded.
- Render running/stopped indicators as markup (a coloured `●`), using `set_markup` or `use-markup`.

## Build

- `build.sh` compiles every `src/blueprints/*.blp`, generates the GResource bundle, and builds every `src/Logic/*.vala` and `src/Views/*.vala` source. New files are discovered automatically; no build edits are needed.
- The Flatpak manifest uses `buildsystem: simple` with `sh build.sh` and a `dir` source. Build with the GNOME 51 SDK (`org.gnome.Sdk//51`), as the Makefile and CI do.
- `Makefile` targets: `flatpak-build`, `flatpak-run`, `bundle`, `flatpak-repo`, and `clean`.
- Keep generated artifacts (`*.ui`, `compose-deck.gresource.xml`, `compose-deck.c`, and binaries) under `build/` or the build script's temporary directory. Never put them in `src/` or the project root; `*.ui` is gitignored.
- Do not add host-only build dependencies; the build tools come from the Flatpak SDK.

## Code style

- Methods and functions are camelCase (`discoverApps`, `fetchApps`, `listServices`). Vala library methods keep snake_case (`get_first_child`, `set_markup`).
- Declarations keep a space before the parameter list (`private void foo ()`); calls omit it (`foo()`, `new Foo()`).
- Section comments use:
  ```vala
  /*
   * Section name
   */
  ```
  Avoid banner comments and editorial asides.
- Indent namespace contents one level (4 spaces).
- `[GtkChild]` fields are bound in the template constructor; do not add null guards for them.
- Use `this.` for instance fields, properties, and methods.
- Prefix view classes with `[CCode (cname = "...")]` so Blueprint `template class="X"` resolves to the generated type name.
- Keep class names aligned with their file names.

## Documentation

- Do not manually wrap Markdown prose. Keep each paragraph and list item on one line and let the renderer wrap it.
- Keep `README.md` user-facing and `AGENTS.md` contributor-facing.

## Repository rules

- Do not commit generated build artifacts or local Flatpak state.
- Keep behavior in `ComposeDeck`/`State` and presentation in views; do not move orchestration into the UI layer.
