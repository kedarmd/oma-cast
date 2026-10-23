pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../core/Theme.js" as Theme

Singleton {
  id: colors
  // A complete Tokyo Night fallback allows first launch before kmDot is synced.
  property bool loaded: false
  property string lastError: ""
  property bool unavailable: false
  property var palette: ({ surface_high: "#16161e", text: "#c0caf5", primary: "#7aa2f7", primary_container: "#40292e42", on_primary_container: "#c0caf5", outline_variant: "#292e42" })
  readonly property string themePath: Quickshell.env("KAY_CAST_THEME_FILE") || (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/kmdot/quickshell/Colors.qml"
  readonly property var menu: ({ background: palette.surface_high, text: palette.text, selectedText: palette.on_primary_container, selectedBackground: palette.primary_container, border: palette.outline_variant })
  function refresh() { paletteFile.reload() }
  // kmDot sync can remove this directory and recreate it later. A watcher on
  // the old directory cannot see its replacement; retry only while unavailable.
  Timer {
    interval: 500
    repeat: true
    running: colors.unavailable
    onTriggered: colors.refresh()
  }
  FileView {
    id: paletteFile
    path: colors.themePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: {
      colors.unavailable = true
      colors.lastError = "kmDot palette unavailable; retrying with previous colors"
    }
    onLoaded: {
      colors.unavailable = false
      try { colors.palette = Theme.parse(text()); colors.loaded = true; colors.lastError = "" }
      catch (e) { colors.lastError = String(e); console.warn("[kay-cast] keeping previous theme: " + e) }
    }
  }
}
