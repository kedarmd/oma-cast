# CachyOS / kmDot port

## Scope and acceptance

Port the existing launcher to the local kmDot desktop, retaining its ranker,
frecency, aliases, favorites, disabled commands, calculator/history and explicit
agent hand-off. This does not mean implementing every future Raycast feature in
SPEC.md: extension hosting, snippets, file indexing and rayconfig import are
separate products of the upstream roadmap.

## Desktop inventory (2026-10-22)

Source: ../kmDot and installed ~/.config/kmdot. Hyprland uses Lua `hl.bind`
and `require("keybinds")`, not Omarchy's `o.bind` / `hypr.*` module paths.
Quickshell's default instance owns the bar, notifications and kmDot launchers.
Super+Space, Super+K/T/V/H/Escape/N and Super+Ctrl+Space are occupied. Ghostty
is the terminal; Zen is the browser. Themes are catppuccin, everforest, nord,
and tokyonight. theme-switcher renders Colors.qml and uses `pkill -x quickshell` before
restarting the default shell. The installed kay-cast service runs as `qs`, and
its restart policy also covers termination. Tokens.qml defines semantic
colors and a 1.5 px surface outline. UI uses JetBrainsMono Nerd Font, rounded
cards and tonal elevation.

## Implementation sequence

1. **Independent runtime.** Add shell.qml, path-scoped IPC and lifecycle commands.
   No omarchy-shell, Commons, Ui, socat, uwsm or Omarchy font requirement.
   Keep kmDot's default shell running. Accept: separate instance starts, backend
   becomes ready, apps index, RPC answers, show/hide work without QML errors.
2. **Theme and presentation.** Read generated kmDot Colors.qml as data with a
   bounded parser; watch atomic replacements; map semantic surface, text,
   selection and outline roles. Match font, border and rounded geometry. Support
   focused-monitor placement and small monitors. Accept: all four palettes parse;
   a theme update rebinds colors without resetting launcher state.
3. **Desktop commands.** Replace Omarchy catalog with available kmDot launcher
   hand-offs, system/notification controls, screenshots and discovered theme
   choices. Hide unavailable integrations; preserve safe argv boundaries and
   expose editable custom commands. Refresh on open. Accept: search sees local
   commands and no unusable Omarchy entries; unavailable tools disappear.
4. **App/browser/clipboard/agent adapters.** Launch DesktopEntry objects through
   Quickshell (including Terminal=true); use xdg-open for URLs; implement
   clipboard paste after dismissal with correct terminal chord. Launch explicitly
   configured local agent in Ghostty with literal prompt arguments and bounded,
   question-free preflight. Accept: missing dependencies fail visibly; no prompt
   executes as shell code or enters search history.
5. **Installation and session integration.** Link CLI and standalone config;
   install user service with restart after kmDot's blanket quickshell kill.
   Write an idempotent Alt+Space Lua module using hl.bind; preserve existing
   bindings, reject conflicts, remove only owned files on uninstall. Include
   doctor, reload and dev. Accept: repeated install/setup works; uninstall keeps
   data and unrelated config; no global pkill from kay-cast.
6. **Verification and documentation.** Run existing core tests, new adapter and
   isolated installer tests, shell syntax checks, live IPC and layer smoke tests.
   Record what was actually exercised. Document configuration, dependency list,
   setup, sync caveats and unresolved desktop-only acceptance.

## Remaining boundaries

Do not test power actions, submit agent questions, paste into unrelated windows,
or switch the user's desktop theme just to exercise plumbing. These require a
controlled interactive check. kmDot sync may overwrite a manually added require;
setup is repeatable and the generated module can be sourced from kmDot's own
source-of-truth later. No changes to the dotfiles repository are needed here.

## Delivered implementation

All six porting steps above are implemented. The running provider contains
available desktop entries plus 23 kmDot actions and two built-ins on this machine
(106 total). It refreshes tools and shortcut hints on open, reads the active-theme
marker, and supports a watched custom argv catalog. Omarchy parser/service files
remain as upstream reference fixtures; they are not loaded by the runtime.

Additional port fixes include Terminal=true application launching, original
working directories and desktop field-code expansion, correct desktop-ID copying,
runnable shell quoting for Copy Command, and a view for restoring disabled apps
and commands. Theme failures keep the previous valid palette. Startup and store
changes refresh an open result view. Source reload uses a process restart after
an observed Qt/Wayland teardown crash; data-file watches remain enabled.

Installed locally:

- `~/.local/bin/kay-cast` links to this checkout's CLI.
- `~/.config/kay-cast/runtime` links to this checkout.
- `~/.config/systemd/user/kay-cast.service` is enabled and running.
- `~/.config/kmdot/hyprland/kay-cast.lua` binds Alt+Space with `hl.bind`;
  the installed Hyprland entry point requires it. Existing bindings are preserved.
- The source `~/dev/kmDot` checkout was only read.

## Validation record (2026-10-22)

- Full Node suite: 98 passing tests, zero failures, one skipped upstream live
  Omarchy-menu fixture (99 total). No npm packages.
- All four kmDot palette renders satisfy the theme adapter.
- `python3 tests/desktop-live.py`: an isolated Quickshell instance verified atomic
  palette replacement, invalid-theme recovery, desktop-entry quoting, working
  directory and field codes, Terminal=true through a fake terminal, and disabling /
  restoring a command through the same APIs as the UI. No real app was launched.
- Agent/terminal fixtures verified prompt boundaries, leading flags, Unicode,
  newlines, shell metacharacters, missing tooling and cancellation. Clipboard
  fixtures verified literal text and terminal/browser paste chords without typing.
- Installer fixtures verified repeat installation, refusal to replace foreign
  files, path-scoped IPC, Lua and .conf setup, binding conflict handling, opaque
  Hyprland Lua callbacks, and preservation of modified bindings and user data.
- `tests/smoke.sh`: real backend ready, calculator, app/command indexing and three
  layer show/hide cycles passed. Latest measured worst show: 118 ms (250 ms
  portable smoke budget; cold mapping and CLI overhead included).
- The user service recovered after SIGTERM to **only kay-cast**. The default
  Quickshell bar instance remained running. `systemd-analyze --user verify`
  accepted the unit, and `hyprctl configerrors` reported no errors.
- Rendered launcher inspected on the active Tokyo Night desktop; final shell log
  contains Configuration Loaded with no QML errors. Shell syntax, Python parsing
  and `git diff --check` passed.

## Manual acceptance still required

These checks intentionally affect real desktop state and are not covered by
fixtures: authenticate and submit a real agent question, paste into a chosen app,
and switch themes using the full kmDot theme-switcher. The independent palette
watch and service-recovery pieces of theme switching were tested separately.
Only the current monitor arrangement was exercised live. Early keystrokes before
the overlay maps remain an upstream limitation. Full settings UI, Raycast
extensions, snippets, file indexing and rayconfig import remain future work.

## Visual refinement and local trial binding

The local kmDot source now maps Super+Space to `hl.dsp.global("kay-cast:toggle")`;
its Hyprland sync deployed that replacement and removed the temporary installed
Alt+Space module. The original kmDot app picker remains accessible from its menu.

After desktop review, the launcher uses 15 px medium Adwaita Sans result titles
and 12 px secondary lines, with Nerd Font glyphs kept separate from text.
`KAY_CAST_FONT_FAMILY` can override the UI family. The centered card is 680×520
with 20 px corners, a thin outline, subtle shadow and themed backdrop. Result
rows are 56 px with 10 px selection corners, consistent icon spacing, and a
separate subtitle line. Repeated Command/Application labels were removed; status,
favorites, aliases and calculator timestamps remain. The actions panel and key
hints follow the same typography and spacing. Search and action-panel screenshots
are in docs/screenshots/cachyos-{search,actions}.png.

Search and action-panel renders were inspected on-screen. The 99-test suite
passed (98 pass, one Omarchy fixture skipped), isolated desktop integration checks
passed, and the live smoke check measured 116 ms worst show with no QML errors.

## Theme-watch recovery and branding

A live mismatch was reproduced: the generated palette was Everforest
(`surface_high=#272e33`, `primary=#a7c080`), while the launcher retained
Catppuccin (`#181825`, `#cba6f7`). A minimal integration reproduction showed
that replacing the containing config directory loses FileView's watch, even
though repeated atomic replacement of the palette file itself succeeds.

Color.qml now retries unavailable files every 500 ms, stops retrying after a
successful read, and refreshes when the launcher opens. Invalid palette content
still preserves the last valid colors without repeated warning/poll loops.
The active theme marker remains informational; rendered colors come from the
actual generated palette.

BrandMark.qml uses the exact kmDot mark from
`config/quickshell/components/r1icons.js` (component
354ba062-72fc-8008-8008-c87ee54dd13e), vendored in core/Brand.js. Header and footer
bind its stroke to `primary` and its accent dot to `primary_alt`, matching the
kmDot topbar without requiring the source checkout at runtime.

Validation: the expanded isolated desktop test reproduced the directory-watch
failure before the fix and now verifies recovery, subsequent edits, repeated
complete palettes for all four kmDot themes, and reactive primary/accent logo
colors. The running launcher's palette was compared against its generated file.
All 101 unit tests ran: 100 pass, one upstream Omarchy fixture skipped. Live
smoke checks passed (110 ms worst show), and the reloaded shell logged no QML
errors. The user's desktop theme was not switched by these tests.

## kay-cast identity

The CLI and helpers, service, IPC target, global shortcut, layer namespace,
plugin ID (`kmdot.kay-cast`), environment variables (`KAY_CAST_*`), XDG paths,
logs, tests and documentation use kay-cast. The local installation's settings,
history and cache directories were moved intact to the new XDG paths before the
renamed service started. kmDot's source binding and installed configuration now
use `kay-cast:toggle` for Super+Space. Screenshots were refreshed and unused
screenshots carrying obsolete branding were removed. The original upstream URL
is retained solely for attribution.

Validation: 100 unit tests pass with one upstream-only fixture skipped. Isolated
palette/logo/app integration tests and live smoke checks pass; the new shortcut
opens and closes the launcher. The service unit verifies, Hyprland reports no
configuration errors, and the renamed CLI's doctor passes.

## Launched-process lifetime fix

The main kmDot shell was absent while kay-cast.service remained healthy. Its
startup configuration loaded successfully when the bar was brought back.
The launch path had a service-lifetime bug: Quickshell.execDetached double-forks
but keeps descendants in kay-cast.service's cgroup. A theme hook can restart the
bar inside that group, so stopping kay-cast later also stops that bar.

`python3 tests/launch-lifecycle.py` reproduced this with a disposable launcher
service and a sleep process: the child's cgroup was the launcher service. The
fixed Util.execArgv uses bin/kay-cast-launch to start an independent user service,
preserving the caller's environment, cwd and literal argv. Systemd expansion is
disabled, service-control environment variables are excluded, and ExitType=cgroup
keeps forked processes alive. This also covers apps, terminal sessions, browser
launches and clipboard owners. DesktopEntry.command supplies already expanded
field codes; desktop workingDirectory is preserved. Without a user manager,
manually started instances fall back to direct execution.

The regression now passes, including literal $HOME, shell metacharacters,
newlines and leading flags. The actual bar retained PID 234390 across kay-cast
reload, with notification and lockscreen IPC responding. No main-shell source
files or unrelated display changes in kmDot were changed for this fix.

## Upstream changes adapted (2026-10-23)

Fetched `typecraft-dev/oma-cast` through `103aa67` and compared it with the
fork's shared base `90efedd`. Upstream had two feature commits: calculator
preferences plus mixed quantities, work-time and Unix-time conversions; Emacs
and Vim navigation, inline web-search arguments and root filters; item details,
confirmation dialogs and undoable toast actions; and plain-text clipboard paste
in launcher fields. Those behaviors are now integrated using kay-cast's local
candidate IDs, `xdg-open`, kmDot-owned power menus, Quickshell clipboard access,
and the existing semantic color/font/spacing components. No upstream Omarchy
executable or visual asset was brought into the runtime. The local card, logo,
fonts, colors and row styling remain in place.

New coverage checks mixed and work units, Unix timestamps, config validation,
quicklink URL encoding, root filters, item details, history-clear confirmation
and clipboard routing. The current full suite passes 110 tests, with one
Omarchy-only fixture skipped. The live Quickshell shell loads without QML errors;
isolated theme/app tests, process-lifetime checks, installer checks and live
show/hide smoke checks pass. Notification and lockscreen IPC continue to answer
from the kmDot bar. Power actions remain under kmDot's existing confirmation UI.
