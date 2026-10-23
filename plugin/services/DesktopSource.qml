import QtQuick
import Quickshell
import Quickshell.Io
import "../core/Desktop.js" as Desktop

Item {
  id: source
  readonly property string configRoot: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
  property var discovered: []
  property string shortcutText: ""
  property string activeTheme: ""
  readonly property var candidates: Desktop.decorate(source.discovered, source.shortcutText, source.activeTheme, source.configRoot)
  property var custom: []
  property bool canPaste: false
  property bool canLaunchTerminal: false
  property bool loading: probe.running
  property int revision: 0
  signal message(string level, string text, var metadata)
  function refresh() {
    if (!probe.running) probe.running = true
    if (!keybinds.running) keybinds.running = true
  }
  onCandidatesChanged: revision++
  Component.onCompleted: refresh()
  Process {
    id: probe
    command: ["bash", "-c", 'for t in qs hyprshot ghostty nautilus wl-copy wtype; do command -v "$t" >/dev/null && printf "tool:%s\\n" "$t"; done; command -v "${KAY_CAST_TERMINAL:-ghostty}" >/dev/null && printf "tool:terminal\\n"; for s in toggle.sh lock-screen.sh; do test ! -x "$1/kmdot/quickshell/scripts/$s" || printf "script:%s\\n" "$s"; done; if test -x "$1/kmdot/theme-switcher/main.sh"; then printf "script:theme-switcher\\n"; for p in "$1"/kmdot/themes/*/quickshell.conf; do test -f "$p" || continue; p=${p%/quickshell.conf}; printf "theme:%s\\n" "${p##*/}"; done; fi; true', "kay-cast-probe", source.configRoot]
    stdout: StdioCollector {
      onStreamFinished: {
        source.canLaunchTerminal = text.indexOf("tool:terminal\n") >= 0
        source.canPaste = text.indexOf("tool:wl-copy\n") >= 0 && text.indexOf("tool:wtype\n") >= 0
        source.discovered = Desktop.catalog(text, source.configRoot)
        source.revision++
      }
    }
  }
  Process {
    id: keybinds
    command: ["bash", "-c", 'command -v lua >/dev/null && test -f "$1/kmdot/hyprland/scripts/keybinds.lua" && lua "$1/kmdot/hyprland/scripts/keybinds.lua" "$1/kmdot/hyprland/keybinds.lua"', "kay-cast-shortcuts", source.configRoot]
    stdout: StdioCollector { onStreamFinished: source.shortcutText = text }
  }
  FileView {
    path: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/kmdot_theme"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: source.activeTheme = text().trim()
  }
  FileView {
    path: source.configRoot + "/kay-cast/commands.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { source.custom = Desktop.customCandidates(JSON.parse(text())); source.revision++ }
      catch (e) { source.message("warning", "Keeping previous custom commands: " + e, null) }
    }
    onLoadFailed: function(error) {
      if (error === FileViewError.FileNotFound) { source.custom = []; source.revision++ }
    }
  }
}
