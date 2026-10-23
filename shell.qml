import QtQuick
import Quickshell
import "plugin"

ShellRoot {
  // Avoid Qt/Wayland surface destruction during in-process hot reload.
  // FileView still watches theme/config data; source edits use kay-cast reload.
  Component.onCompleted: Quickshell.watchFiles = false
  Launcher {}
}
