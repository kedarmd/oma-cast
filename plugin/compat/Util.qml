pragma Singleton
import QtQuick
import Quickshell

QtObject {
  readonly property string launchHelper: decodeURIComponent(Qt.resolvedUrl("../../bin/kay-cast-launch").toString().replace("file://", ""))
  function execArgv(argv, workingDirectory) {
    Quickshell.execDetached([launchHelper, workingDirectory || Quickshell.env("HOME")].concat(argv))
  }
  function execDetached(command) { execArgv(["bash", "-c", command]) }
  function alpha(color, opacity) { var c = Qt.color(color); return Qt.rgba(c.r, c.g, c.b, opacity) }
  function editsFilter(event, query) {
    return event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete ||
      ((event.modifiers & Qt.ControlModifier) && [Qt.Key_U, Qt.Key_W, Qt.Key_H, Qt.Key_V].indexOf(event.key) >= 0)
  }
  function editedFilter(event, query) {
    if (event.key === Qt.Key_U) return ""
    if (event.key === Qt.Key_W) return query.replace(/\s*\S+\s*$/, "")
    if (event.key === Qt.Key_V) return query + Quickshell.clipboardText
    return Array.from(query).slice(0, -1).join("")
  }
}
