const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")

const source = fs.readFileSync(path.join(__dirname, "../plugin/ui/LauncherWindow.qml"), "utf8")
function body(signature) {
  const start = source.indexOf(signature)
  assert.ok(start >= 0, signature)
  const open = source.indexOf("{", start) + 1
  const end = source.indexOf("\n  }", open)
  return "(function() {\n" + source.slice(open, end) + "\n})()"
}

function harness(text) {
  const changes = []
  const window = {
    query: "before ", actionPanelOpen: false, view: { kind: "root" }, argFocus: -1,
    argDefs: [], argValues: {}, setQuery(value) { this.query = value; changes.push(value) }
  }
  const actionPanel = { filter: "" }
  const context = vm.createContext({ window, actionPanel, Quickshell: { clipboardText: text } })
  window.pasteClipboard = () => vm.runInContext(body("function pasteClipboard()"), context)
  return { window, actionPanel, changes, press(key, modifiers) {
    const Qt = { NoModifier: 0, ShiftModifier: 2, ControlModifier: 1, AltModifier: 4, MetaModifier: 8,
      Key_Escape: 27, Key_V: 86, Key_Insert: 45, Key_Plus: 43, Key_Equal: 61, Key_Minus: 45, Key_0: 48, Key_BracketLeft: 91,
      Key_K: 75, Key_P: 80, Key_T: 84, Key_Return: 13, Key_Enter: 13, Key_J: 74, Key_N: 78, Key_Up: 38, Key_Down: 40,
      Key_F: 70, Key_C: 67, Key_D: 68, Key_1: 49, Key_9: 57, Key_Tab: 9, Key_Backtab: 10, Key_Backspace: 8, Key_Delete: 46 }
    const event = { key: Qt[key], modifiers, text: "" }
    const context = vm.createContext({ window: Object.assign(window, {
      handleEscape() {}, setZoom() {}, closePopups() {}, pop() {}, pasteClipboard: window.pasteClipboard,
      isActionPanelKey: () => false, isTyping: () => false, direction: () => 0,
      toggleActionPanel() {}, toggleAbout() {}, toggleDropdown() {}, toggleToastPanel() {},
      performNth() {}, performIfOffered() {}, perform() {}, move() {}, recallHistory() { return false },
      jumpSection() {}, nthItem() { return -1 }, argDefs: window.argDefs, argFocus: window.argFocus,
      atRoot: true, historyIndex: -1, selectedIndex: 0, nextSelectable() { return 1 },
      query: window.query, view: window.view
    }), Qt, Util: { editsFilter: () => false, editedFilter: (e, q) => q }, actionPanel, Quickshell: { clipboardText: text } })
    context.event = event
    return vm.runInContext(body("function handleKey(event)"), context)
  } }
}

test("clipboard paste is plain text and routes to the active kay-cast field", () => {
  const h = harness("<b>你好</b> $(id)\r\nsecond\u2028third")
  h.window.pasteClipboard()
  assert.deepEqual(h.changes, ["before <b>你好</b> $(id) second third"])

  const args = harness("km dot")
  args.window.argDefs = [{ name: "query" }]
  args.window.argFocus = 0
  args.window.argValues = { query: "web " }
  args.window.pasteClipboard()
  assert.equal(args.window.argValues.query, "web km dot")
  assert.deepEqual(args.changes, [])

  const action = harness("Copy Result")
  action.window.actionPanelOpen = true
  action.actionPanel.filter = "Find "
  action.window.pasteClipboard()
  assert.equal(action.actionPanel.filter, "Find Copy Result")
})

test("Ctrl+V routes to the launcher clipboard handler", () => {
  const h = harness("pasted")
  h.press("Key_V", 1)
  assert.deepEqual(h.changes, ["before pasted"])
})

test("the Escape hint and root filter have separate header space", () => {
  assert.match(source, /anchors\.right:\s*filterButton\.visible\s*\?\s*filterButton\.left\s*:\s*parent\.right/)
  assert.match(source, /queryRoom:[^\n]*escapeHint\.width/)
})
