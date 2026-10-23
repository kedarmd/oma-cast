# Development

This fork targets CachyOS + the user's kmDot Hyprland desktop. Read
[docs/CACHYOS-PORT.md](docs/CACHYOS-PORT.md) before changing desktop integration.
[SPEC.md](SPEC.md) and reference/ describe the original Raycast research and
upstream Omarchy architecture; the CachyOS port supersedes their host assumptions.

## Runtime and boundaries

`shell.qml` starts a separate Quickshell instance. `plugin/Launcher.qml` owns its
lifecycle, `Backend.qml` owns RPC and stores, `services/DesktopSource.qml` discovers
kmDot actions, and `compat/` provides local theme/window/input helpers. Scope every
CLI operation to the checkout's shell.qml; the default Quickshell instance owns
the user's bar, notifications and existing menus.

Keep runtime code QML, plain JS and bash. Python's standard library is used for
installer-only Hyprland config edits; Node's built-in runner is used for tests.
`plugin/core/*.js` files are independently importable by QML and Node, with guarded
module.exports and no inter-module imports. QML wires dependencies together.

Read the generated kmDot Colors.qml as data through Theme.js; never evaluate it.
Use DesktopEntry.command (already field-expanded) and workingDirectory for app
launches. Route literal argv through Util.execArgv and bin/kay-cast-launch; it
starts an independent user service with ExitType=cgroup, preserving forked apps
and clipboard owners. A double-fork or setsid retains the launcher service cgroup:
restarting kay-cast once killed the bar restarted by a theme command. Keep this
lifetime boundary for desktop actions, browser launches and agent sessions.
Use the existing kmDot scripts for menus. commands.json is an explicitly user-authored
argv catalog. OmarchyMenu.js and its source service are upstream references and
test fixtures, not the running provider.

Preserve the root ranker's behavior (reference/02-backend.md §4), versioned JSON
migrations, atomic writes, and read-only handling for malformed/newer documents.
Persisted paths follow XDG under kay-cast. Dynamic text uses Text.PlainText.

The agent action is an explicit terminal hand-off only. Keep prompts out of
preflight commands and search history. Preserve cancellation on hide, bounded
checks and literal arguments. No embedded model API, credentials, telemetry,
Raycast servers, proprietary code, icons or fonts.

## Workflow and validation

Run `node --test tests/*.test.js` and `bash -n bin/kay-cast bin/kay-cast-desktop bin/kay-cast-launch tests/smoke.sh`.
For runtime changes, run `bin/kay-cast reload`, then inspect
`qs log -n -p "$PWD/shell.qml" -t 40`. Source hot reload is disabled because the
installed Quickshell crashed during Qt/Wayland surface teardown. Theme/config
FileViews still watch data independently.

`python3 tests/launch-lifecycle.py` uses a disposable user service to verify that
spawned processes survive their launcher stopping and retain literal arguments.
`tests/smoke.sh` checks IPC, readiness, search, calculator and surface mapping;
it briefly shows/hides the launcher and sends no keyboard input. Never synthesize
keys into an unmapped or unfocused launcher. Validate agent execution, paste and
power actions with controlled fixtures; leave real accounts/windows/session state
alone during automated checks.

The installer edits installed Hyprland config only with an owned Alt+Space
module. kmDot sync can replace its require; document rerunning setup. Keep the
source dotfiles checkout untouched. Uninstall preserves modified binding files,
custom commands, settings and history.

## Status

The CachyOS port replaces Omarchy host services with standalone IPC, kmDot theme
roles, available desktop commands, xdg-open, native desktop entries, clipboard
paste and local agent adapters. A user service restarts it after kmDot's theme
hook kills all quickshell processes. Disabled Commands restores hidden commands.
Validation results and remaining manual checks live in docs/CACHYOS-PORT.md.

Extension hosting, snippets, file indexing, rayconfig import and a full settings
window remain future work. Upstream quicklinks, filters, item details, guarded
actions, clipboard paste and calculator/navigation improvements are adapted to
the local UI and desktop adapters.
