// Desktop integration: argv arrays are never interpolated into a shell command.
function catalog(snapshot, configRoot) {
  var available = {}, out = []
  String(snapshot).split("\n").forEach(function(line) { available[line.trim()] = true })
  function add(id, title, group, argv, glyph) {
    out.push({ id: "kmdot:" + id, type: "command", kind: "desktop-action", title: title,
      subtitle: "kmDot › " + group, keywords: ["kmdot", "cachyos", group], typeLabel: "Command",
      glyph: glyph || "\uf013", argv: argv, rootSearch: { when: "always" } })
  }
  var scripts = configRoot + "/kmdot/quickshell/scripts/"
  if (available["script:toggle.sh"]) {
    var menus = [
      ["menu", "kmDot Menu", "kmdot-kmdot"], ["apps", "Application Launcher", "kmdot-launcher"],
      ["themes", "Appearance / Themes", "kmdot-theme"], ["wallpapers", "Wallpapers", "kmdot-wallpaper"],
      ["clipboard", "Clipboard History", "kmdot-clipboard"], ["connections", "Connections", "kmdot-connections"],
      ["wifi", "Wi-Fi", "kmdot-wifi"], ["bluetooth", "Bluetooth", "kmdot-bluetooth"],
      ["handy", "Handy Transcriptions", "kmdot-handy-launcher"], ["keybinds", "Keyboard Shortcuts", "kmdot-keybinds"],
      ["system", "System / Power Menu", "kmdot-system"]
    ]
    var menuIcons = { menu: "\uf009", apps: "\uf00a", themes: "\uf1fc", wallpapers: "\uf03e",
      clipboard: "\uf0ea", connections: "\uf0ac", wifi: "\uf1eb", bluetooth: "\uf293",
      handy: "\uf130", keybinds: "\uf11c", system: "\uf011" }
    menus.forEach(function(m) { add(m[0], m[1], "Desktop", [scripts + "toggle.sh", m[2]], menuIcons[m[0]]) })
  }
  if (available["script:lock-screen.sh"]) add("lock", "Lock Screen", "System", [scripts + "lock-screen.sh"], "\uf023")
  if (available["tool:qs"] && available["script:toggle.sh"]) {
    var shell = configRoot + "/quickshell/shell.qml"
    add("notifications", "Notification Center", "Notifications", ["qs", "ipc", "-p", shell, "call", "notifications", "togglePanel"], "\uf0f3")
    add("dnd", "Toggle Do Not Disturb", "Notifications", ["qs", "ipc", "-p", shell, "call", "notifications", "toggleDnd"], "\uf1f6")
  }
  if (available["tool:hyprshot"]) ["region", "window", "output"].forEach(function(mode) {
    add("screenshot-" + mode, "Screenshot " + mode, "Screenshots", ["hyprshot", "-m", mode], "\uf030")
  })
  if (available["tool:ghostty"]) add("terminal", "Open Ghostty", "Applications", ["ghostty"], "\uf120")
  if (available["tool:nautilus"]) add("files", "Open File Manager", "Applications", ["nautilus"], "\uf07b")
  if (available["script:theme-switcher"]) Object.keys(available).sort().forEach(function(key) {
    if (key.indexOf("theme:") !== 0) return
    var name = key.slice(6)
    if (!/^[a-z][a-z0-9_-]*$/.test(name)) return
    add("theme-" + name, "Theme: " + name, "Appearance", [configRoot + "/kmdot/theme-switcher/main.sh", name], "\uf1fc")
  })
  return out
}

function customCandidates(value) {
  if (!Array.isArray(value)) throw new Error("commands.json must be an array")
  var ids = {}, out = []
  value.forEach(function(c) {
    if (!c || !/^[a-zA-Z0-9_-]+$/.test(c.id || "") || ids[c.id]) throw new Error("Custom command ids must be unique letters, digits, _ or -")
    if (typeof c.title !== "string" || !c.title.trim()) throw new Error("Custom command needs a title")
    if (!Array.isArray(c.argv) || !c.argv.length || !c.argv.every(function(a) { return typeof a === "string" && a.indexOf("\u0000") < 0 })) throw new Error("Custom command argv must be a non-empty string array")
    ids[c.id] = true
    out.push({ id: "custom:" + c.id, type: "command", kind: "desktop-action", title: c.title,
      subtitle: c.subtitle || "Custom Command", keywords: Array.isArray(c.keywords) ? c.keywords : [],
      glyph: c.glyph || "\uf120", argv: c.argv.slice(), typeLabel: "Command", rootSearch: { when: "always" } })
  })
  return out
}
if (typeof module !== "undefined") module.exports = { catalog: catalog, customCandidates: customCandidates }

// kmDot's own Lua inspector resolves hl.bind expressions without guessing key names.
function decorate(candidates, shortcutText, activeTheme, configRoot) {
  var shortcuts = {}
  String(shortcutText).split("\n").forEach(function(line) {
    var columns = line.split("\t")
    if (columns.length >= 3 && columns[2]) shortcuts[columns[2].replace(/\/usr\/bin\//g, "").replace(/~\/\.config/g, configRoot)] = columns[0]
  })
  return candidates.map(function(c) {
    var next = Object.assign({}, c)
    var target = c.argv[0].slice(-9) === "toggle.sh" ? c.argv[1] : "exec:" + c.argv.join(" ")
    var shortcut = shortcuts[target.replace(/\/usr\/bin\//g, "")]
    if (shortcut) { next.shortcut = shortcut; next.subtitle += " · " + shortcut }
    next.checked = c.id === "kmdot:theme-" + String(activeTheme).trim()
    return next
  })
}
if (typeof module !== "undefined") module.exports.decorate = decorate

function commandText(argv) {
  return argv.map(function(arg) { return "'" + String(arg).replace(/'/g, "'\\''") + "'" }).join(" ")
}
if (typeof module !== "undefined") module.exports.commandText = commandText
