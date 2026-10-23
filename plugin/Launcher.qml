import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "compat"
import "ui"

Item {
  id: root


  property bool opened: false
  property double openedAt: 0


  function open(payloadJson) {
    Color.refresh()
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    var wasOpen = root.opened
    root.opened = true
    root.openedAt = Date.now()
    launcher.prepare(payload)
    if (!wasOpen) backend.emit("window.visibilityChanged", { visible: true })
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    backend.emit("window.visibilityChanged", { visible: false })
  }


  function show() {
    if (root.opened) return
    root.open("{}")
  }

  function hide() {
    if (!root.opened) return
    root.close()
  }

  function toggle() {
    if (root.opened) root.hide()
    else root.show()
  }

  function run(commandId) {
    var r = backend.callSync("rootSearch.performAction", { id: commandId, action: "open", query: "" })
    if (!r.ok) return r
    var outcome = r.data || {}
    if (outcome.push) {
      root.show()
      launcher.popToRoot()
      launcher.push(outcome.push)
    } else if (outcome.close) {
      root.hide()
      if (outcome.hud) launcher.hud(outcome.hud)
    }
    return r
  }

  Backend {
    id: backend
  }

  Connections {
    target: backend
    function onNotification(method, data) {
      if (method !== "agent.launchReady") return
      root.hide()
      launcher.popToRoot()
      Util.execArgv(data.argv)
    }
  }

  LauncherWindow {
    id: launcher
    shown: root.opened
    backend: backend
    appLibrary: backend.appLibrary
    onDismissRequested: root.hide()
  }

  GlobalShortcut {
    appid: "kay-cast"
    name: "toggle"
    description: "Toggle kay-cast"
    onPressed: root.toggle()
  }

  IpcHandler {
    target: "kay-cast"

    function toggle(): string {
      root.toggle()
      return root.opened ? "shown" : "hidden"
    }

    function show(): string {
      root.show()
      return "shown"
    }

    function hide(): string {
      root.hide()
      return "hidden"
    }

    function isOpen(): string {
      return root.opened ? "true" : "false"
    }

    function ping(): string {
      return "ok"
    }

    function run(commandId: string): string {
      return JSON.stringify(root.run(commandId))
    }

    function call(method: string, dataJson: string): string {
      var data = null
      if (dataJson && dataJson.length > 0) {
        try { data = JSON.parse(dataJson) } catch (e) {
          return JSON.stringify({ ok: false, error: "data is not JSON: " + e })
        }
      }
      return JSON.stringify(backend.callSync(method, data))
    }
  }
}
