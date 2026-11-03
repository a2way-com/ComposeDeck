# Standing Orders for ComposeDeck Development

Record of user directives to persist across sessions.

## Git
- NEVER make commits unless explicitly asked with `cmt`. User commits manually.
- Never auto-commit. Never force-push. Create commits only on request.
- Shorthands: `suc` = show uncommitted changes; `scm` = suggest a commit message (suggested only, no commit).

## Architecture (layering)
- Entry point: `Main.vala` (just `main()`).
- `Application.vala` — `Adw.Application` lifecycle: creates central `State`, presents window, owns no business logic.
- `ComposeDeck.vala` — pure business logic + orchestration (manipulates views through central `State`), no GTK templates.
- `ComposeService.vala` — talks with the Compose provider (podman socket REST `is_running`).
- `State.vala` (in Logic) — central state (`apps`, `total`, `running_count`, `selectedPath`, `overview_selected`) with `changed` signal. UI merely reads from it via `Logic.Application.getState()`.
- View files (`src/Views/*.vala` = controllers) — only GUI: template bindings, signals, rendering from `State`. No business logic, no polling timers.
- A 10-second polling timer? Orchestration lives in `ComposeDeck`, mutating `State` (which emits `changed`); views render on that signal.

## UI declaration
- All UI in `.blp` (Blueprint) files under `src/blueprints/`. Compiled to `.ui` at build time. Resource IDs are filename-based (`/com/a2way/ComposeDeck/X.ui`).
- Vala uses `[GtkTemplate (ui = ".../X.ui")]`, `[GtkChild]`, `[GtkCallback]`. No `Gtk.Builder`.
- One class per template. CamelCase for our identifiers; library methods keep their names.

## Layout / UX
- GNOME Settings style: `Adw.NavigationSplitView` as window content, sidebar spans full height.
- Sidebar (`Sidebar` partial) has its own `Adw.HeaderBar` with app name ("ComposeDeck") + hamburger `GtkMenuButton` (GMenu: About, Quit).
- Content area (`ContentArea`) has its own header with dynamic title (Overview / app name) + window close button.
- No duplicated titles between headers.
- `AdwToastOverlay` wraps the split view.
- Use `.flat` and minimal margins on header/menu widgets to avoid "hovered" look; avoid the 1px seam by hiding split-view separators and header bar borders (CSS).
- Indicator dots for running/stopped apps: use markup with `use-markup=true`.

## Build / autoload
- `Makefile` and `build.sh` auto-discover `*.vala` and `*.blp` (wildcards). Adding a file needs no build edit.
- Generated artifacts (`.ui`, `compose-deck.gresource.xml`, `compose-deck.c`, binary) live under `build/`, never in project root or `src/`.
- `.ui` files are gitignored (generated from `.blp`).
- Build must be containerized: `blueprint-compiler`, `glib-compile-resources`, `valac` run inside the GNOME 51 SDK (`flatpak build`). No host tools, no pip, no brew.
- Manifest uses `buildsystem: simple` with `sh build.sh`; sources use `dir` type.
- Never auto-commit. Don't install arbitrary deps via apt/brew/pip on host.

## Code style
- Method names camelCase (`discoverApps`, `computeStats`, `updateStatus`, `onSearchChanged`, etc.). Library methods (e.g. `get_first_child`, `set_markup`) keep snake_case.
- Method / constructor **calls** have no space before `(`: `foo (x)` → `foo(x)`, `new Foo ()` → `new Foo()`. **Declarations** (e.g. `private void foo () {`) retain the single space before `(`, matching Vala convention.
- Section comments, when used, must follow:
  ```vala
  /* ----
   * Section name
   */
  ```
  Not the `/* ---------- Section ---------- */` form.
- Namespace blocks indented one level (4 spaces) for classes/members.
- Null-guards on `[GtkChild]` fields are unnecessary (guaranteed bound in constructor) — don't add them.
- Use `this.` when accessing instance fields, properties, and methods (e.g. `this.state = ...`, `this.app = app`, `this.render()`, `this.set_visible(true)`).

## Naming / dirs
- `src/Logic`, `src/Views`, `src/blueprints`, `build/`.
- Namespace classes to match: `namespace Logic { }`, `namespace Views { }`.
- Use `[CCode (cname = "...")]` on view classes so GtkTemplate `template class="X"` resolves to the original type name.
- Class name should match file name (e.g. `Application` in `Application.vala`).
- No `public/index.php`-style comments or other editorial cruft.

## Standing rules
- Never commit unless user says `cmt`.
- Never auto-commit after changes.
- Ask before large architectural moves only if ambiguous; prefer implementing then committing only on request.
- Prefer flatpak containerized builds. Don't touch host tooling.

Last updated from session directives.
