import QtQuick
import Quickshell
import Quickshell.Io
import "compat"
import "core/Rpc.js" as Rpc
import "core/Paths.js" as Paths
import "core/Log.js" as Log
import "core/Schema.js" as Schema
import "core/Ranker.js" as Ranker
import "core/Frecency.js" as Frecency
import "core/RootSearch.js" as RootSearch
import "core/Desktop.js" as Desktop
import "core/Agent.js" as Agent
import "core/Calculator.js" as Calculator
import "services"

Item {
  id: backend

  readonly property string desktopHelper: decodeURIComponent(Qt.resolvedUrl("../bin/kay-cast-desktop").toString().replace("file://", ""))
  readonly property string version: "0.1.0"
  readonly property var paths: Paths.resolve(function(name) { return Quickshell.env(name) })
  readonly property string desktop: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? "hyprland" : "unknown"

  property var appLibrary: null

  property var config: Schema.withConfigDefaults(null)
  property bool directoriesReady: false
  readonly property bool ready: directoriesReady && settingsStore.loaded && frecencyStore.loaded && calculatorStore.loaded

  readonly property var registry: Rpc.createRegistry()
  readonly property double startedAt: Date.now()
  readonly property var deps: ({ Ranker: Ranker, Frecency: Frecency })

  property var candidates: []
  property var candidatesById: ({})
  property int candidatesRevision: 0
  readonly property bool loading: menuSource.loading || agentLauncher.checking
  // Bumped when exchange rates or zone offsets arrive, so an open
  // calculator row re-evaluates.
  readonly property int calculatorRevision: (calculatorData.rates ? 1 : 0) + calculatorData.ratesFetchedAt + calculatorData.zonesAt

  signal notification(string method, var data)


  function call(method, data) { return Rpc.call(backend.registry, method, data) }
  function callSync(method, data) { return Rpc.callSync(backend.registry, method, data) }
  function subscribe(method, callback) { return Rpc.subscribe(backend.registry, method, callback) }

  function emit(method, data) {
    Rpc.emit(backend.registry, method, data, function(m, error) {
      backend.log("error", "rpc", "subscriber of " + m + " threw: " + error)
    })
    backend.notification(method, data)
  }

  function log(level, category, message, metadata) {
    if (!Log.shouldLog(level, backend.config.logLevel)) return
    var line = Log.format(level, category, message, metadata)
    var i = Log.levelIndex(level)
    if (i >= Log.levelIndex("error")) console.error(line)
    else if (i >= Log.levelIndex("warning")) console.warn(line)
    else if (i >= Log.levelIndex("info")) console.info(line)
    else console.log(line)
  }


  function appEntries() {
    if (backend.appLibrary) return backend.appLibrary.sortedEntries("").map(function(row) { return row.entry })
    return (DesktopEntries.applications.values || []).filter(function(e) { return !e.noDisplay })
  }

  function rebuildCandidates() {
    var next = []
    var apps = backend.appEntries()
    for (var i = 0; i < apps.length; i++) if (apps[i] && apps[i].id) next.push(RootSearch.appCandidate(apps[i]))
    next = next.concat(menuSource.candidates, menuSource.custom)
    for (var b = 0; b < RootSearch.BUILTINS.length; b++) {
      next.push(RootSearch.builtinCandidate(RootSearch.BUILTINS[b]))
    }
    var byId = ({})
    for (var j = 0; j < next.length; j++) byId[next[j].id] = next[j]
    backend.candidates = next
    backend.candidatesById = byId
    backend.candidatesRevision++
  }

  Timer {
    id: rebuildTimer
    interval: 30
    onTriggered: backend.rebuildCandidates()
  }

  function searchContext() {
    return {
      commands: settingsStore.loaded ? settingsStore.doc.commands : ({}),
      frecency: frecencyStore.loaded ? frecencyStore.doc.items : ({}),
      nowMs: Date.now(),
      sensitivity: settingsStore.loaded ? settingsStore.doc.general.rootSearchSensitivity : "medium"
    }
  }

  function decorated(id) {
    var c = backend.candidatesById[id]
    return c ? RootSearch.decorate(c, backend.searchContext(), backend.deps) : null
  }

  // ------------------------------------------------------------ calculator

  readonly property bool hour12: backend.config.clockFormat === "auto"
    ? Qt.locale().timeFormat(Locale.ShortFormat).toLowerCase().indexOf("ap") >= 0
    : backend.config.clockFormat === "12h"

  function calculatorEnv() {
    return {
      nowMs: Date.now(),
      localOffset: -new Date().getTimezoneOffset(),
      hour12: backend.hour12,
      rates: backend.config.currencyRates ? calculatorData.rates : null,
      zones: calculatorData.zones,
      remToPxRate: backend.config.remToPxRate,
      workHoursPerDay: backend.config.workHoursPerDay
    }
  }

  function calculate(query) {
    try {
      return Calculator.evaluate(query, backend.calculatorEnv())
    } catch (e) {
      backend.log("error", "calculator", "evaluating failed: " + e, { query: query })
      return null
    }
  }

  function saveCalculation(entry) {
    calculatorStore.update(function(doc) {
      doc.history = Calculator.pushHistory(doc.history, {
        id: String(Date.now()), query: entry.query, result: entry.result, copy: entry.copy, kind: entry.kind
      }, Date.now())
    })
    backend.emit("calculator.historyStateChanged", null)
  }

  // An action on the inline Calculator row or a Calculator History entry.
  // entry: {query, result, copy, kind}; history: whether it is saved already.
  function calculatorAction(action, entry, historyId) {
    switch (action) {
      case "open":
      case "copy-answer":
        if (!historyId) backend.saveCalculation(entry)
        Util.execArgv(["wl-copy", "--", entry.copy])
        return { close: true, hud: "Copied to Clipboard" }
      case "paste-answer":
        if (!menuSource.canPaste) throw new Error("Paste Answer requires wl-clipboard and wtype; Copy Answer is available")
        if (!historyId) backend.saveCalculation(entry)
        // Desktop adapter waits for the surface to unmap before pasting.
        Util.execArgv([backend.desktopHelper, "paste", entry.copy])
        return { close: true }
      case "copy-question-answer":
        if (!historyId) backend.saveCalculation(entry)
        Util.execArgv(["wl-copy", "--", entry.query + " = " + entry.result])
        return { close: true, hud: "Copied to Clipboard" }
      case "open-history":
        return { push: { kind: "calculator-history", title: "Calculator History" } }
      case "delete-entry":
        calculatorStore.update(function(doc) { doc.history = doc.history.filter(function(h) { return h.id !== historyId }) })
        backend.emit("calculator.historyStateChanged", null)
        return { toast: { style: "success", title: "Entry deleted" } }
      case "delete-all-entries":
        calculatorStore.update(function(doc) { doc.history = [] })
        backend.emit("calculator.historyStateChanged", null)
        return { toast: { style: "success", title: "History cleared" } }
    }
    throw new Error("Unknown action " + action)
  }

  function historyEntry(id) {
    var key = String(id).slice("calculator-history:".length)
    var list = calculatorStore.loaded ? calculatorStore.doc.history : []
    for (var i = 0; i < list.length; i++) if (list[i].id === key) return list[i]
    return null
  }

  // ------------------------------------------------------------- execution

  function recordVisit(id, query) {
    if (!frecencyStore.loaded) return
    frecencyStore.update(function(doc) {
      doc.items[id] = Frecency.recordVisit(doc.items[id] || null, Date.now(), query || "")
      if (query) doc.searchHistory = Schema.pushSearchHistory(doc.searchHistory, query)
    })
  }

  function updateCommand(id, mutator) {
    settingsStore.update(function(doc) {
      var current = doc.commands[id] || {}
      var next = mutator(JSON.parse(JSON.stringify(current)))
      var empty = true
      for (var k in next) if (next[k] !== null && next[k] !== undefined && next[k] !== "") empty = false
      if (empty) delete doc.commands[id]
      else doc.commands[id] = next
    })
    backend.emit("settings.commandSettingsChanged", { commandId: id })
  }

  function performAction(data) {
    var id = String(data && data.id || "")
    var action = String(data && data.action || "open")
    var query = String(data && data.query || "").trim()
    var candidate = backend.decorated(id)
    if (!candidate) throw new Error("Unknown command " + id)

    if (action === "open") {
      switch (candidate.kind) {
        case "app":
          backend.recordVisit(id, query)
          if (backend.appLibrary) backend.appLibrary.launch(candidate.appId, candidate.title)
          else {
            var entry = DesktopEntries.byId(candidate.appId)
            if (!entry) throw new Error("Application is no longer installed")
            if (entry.runInTerminal) {
              if (!menuSource.canLaunchTerminal) throw new Error("Install Ghostty or set KAY_CAST_TERMINAL in kay-cast/environment")
              Util.execArgv([backend.desktopHelper, "terminal", entry.workingDirectory || backend.paths.home].concat(entry.command))
            } else Util.execArgv(entry.command, entry.workingDirectory || backend.paths.home)
          }
          return { close: true }
        case "desktop-action":
          backend.recordVisit(id, query)
          Util.execArgv(candidate.argv)
          return { close: true }
        case "builtin":
          if (candidate.run.url) {
            var values = (data && data.arguments) || {}
            var missing = RootSearch.missingArgument(candidate.arguments, values)
            if (missing >= 0) throw new Error("Type a " + candidate.arguments[missing].placeholder.toLowerCase() + " first")
            backend.recordVisit(id, query)
            Util.execArgv(["xdg-open", RootSearch.fillArguments(candidate.run.url, values)])
            return { close: true }
          }
          backend.recordVisit(id, query)
          if (candidate.run.push) return { push: candidate.run.push }
          return { close: true }
        case "fallback":
          Util.execArgv(["xdg-open", RootSearch.fallbackUrl(candidate, query)])
          return { close: true }
      }
      throw new Error("Cannot open " + id)
    }

    switch (action) {
      case "copy-command":
      case "copy-id":
        Util.execArgv(["wl-copy", "--", action === "copy-id" ? (candidate.appId.replace(/\.desktop$/, "") + ".desktop") : (candidate.argv ? Desktop.commandText(candidate.argv) : candidate.action)])
        return { close: true, hud: "Copied to Clipboard" }
      case "favorite-add":
      case "favorite-remove":
      case "favorite-up":
      case "favorite-down":
        var orders = RootSearch.reorderFavorites(settingsStore.doc.commands, id, action)
        settingsStore.update(function(doc) {
          for (var key in orders) {
            var entry = doc.commands[key] || {}
            if (orders[key] === null) delete entry.favoriteOrder
            else entry.favoriteOrder = orders[key]
            if (Object.keys(entry).length === 0) delete doc.commands[key]
            else doc.commands[key] = entry
          }
        })
        var titles = { "favorite-add": "Added to Favorites", "favorite-remove": "Removed from Favorites", "favorite-up": "Moved Up", "favorite-down": "Moved Down" }
        return { toast: { style: "success", title: titles[action] } }
      case "set-alias":
        return { push: { kind: "alias", commandId: id, title: "Alias for " + candidate.title, value: candidate.alias } }
      case "remove-alias":
        backend.updateCommand(id, function(s) { delete s.alias; return s })
        return { toast: { style: "success", title: "Alias removed" } }
      case "reset-ranking":
        frecencyStore.update(function(doc) { delete doc.items[id] })
        return { toast: { style: "success", title: "Ranking reset" } }
      case "enable":
        backend.updateCommand(id, function(s) { delete s.enabled; return s })
        return { toast: { style: "success", title: candidate.title + " enabled" } }
      case "disable":
        backend.updateCommand(id, function(s) { s.enabled = false; return s })
        return { toast: { style: "success", title: candidate.title + " disabled", actions: [
          { id: "undo", title: "Undo", done: candidate.title + " enabled",
            call: { method: "settings.updateCommandSettings", data: { commandId: id, enabled: true } } }
        ] } }
    }
    throw new Error("Unknown action " + action)
  }


  function registerServices() {
    Rpc.register(backend.registry, "system", {
      healthPing: function() { return null },
      healthDatabase: function() {
        var t0 = Date.now()
        JSON.stringify(settingsStore.doc)
        JSON.stringify(frecencyStore.doc)
        return {
          workMs: Date.now() - t0,
          settings: { loaded: settingsStore.loaded, readOnly: settingsStore.readOnly, error: settingsStore.lastError },
          frecency: { loaded: frecencyStore.loaded, readOnly: frecencyStore.readOnly, error: frecencyStore.lastError },
          loaded: settingsStore.loaded, readOnly: settingsStore.readOnly, error: settingsStore.lastError
        }
      },
      info: function() {
        return {
          version: backend.version,
          desktop: backend.desktop,
          platform: "kmdot",
          theme: { loaded: Color.loaded, path: Color.themePath, error: Color.lastError, palette: Color.palette },
          ready: backend.ready,
          uptimeMs: Date.now() - backend.startedAt,
          candidates: backend.candidates.length,
          appLibrary: !!backend.appLibrary,
          methods: Rpc.methods(backend.registry)
        }
      },
      getPaths: function() { return backend.paths }
    })

    Rpc.register(backend.registry, "settings", {
      getGeneralSettings: function() {
        if (!settingsStore.loaded) throw new Error("settings not loaded")
        return settingsStore.doc.general
      },
      updateGeneralSettings: function(data) {
        if (!settingsStore.loaded) throw new Error("settings not loaded")
        if (settingsStore.readOnly) throw new Error("settings are read-only: " + (settingsStore.lastError || "written by a newer build"))
        var patch = data && typeof data === "object" ? data : {}
        var current = settingsStore.doc.general
        for (var key in patch) {
          if (current[key] === undefined) throw new Error("Unknown general setting " + key)
          if (typeof patch[key] !== typeof current[key]) throw new Error("Setting " + key + " must be a " + typeof current[key])
          var choices = Schema.generalChoices[key]
          if (choices && choices.indexOf(patch[key]) < 0) throw new Error("Setting " + key + " must be one of " + choices.join(", "))
        }
        settingsStore.update(function(doc) { for (var k in patch) doc.general[k] = patch[k] })
        backend.emit("settings.generalSettingsChanged", settingsStore.doc.general)
        return settingsStore.doc.general
      },
      getAllCommandSettings: function() { return settingsStore.doc.commands },
      getCommandSettings: function(data) { return settingsStore.doc.commands[String(data && data.commandId || "")] || {} },
      updateCommandSettings: function(data) {
        var id = String(data && data.commandId || "")
        if (!backend.candidatesById[id]) throw new Error("Unknown command " + id)
        if (data.alias !== undefined && data.alias !== null) {
          var alias = String(data.alias).trim().toLowerCase()
          if (/\s/.test(alias)) throw new Error("An alias cannot contain spaces")
          var commands = settingsStore.doc.commands
          for (var other in commands) {
            if (other !== id && commands[other].alias === alias && alias) throw new Error("Alias “" + alias + "” is already used by " + ((backend.candidatesById[other] || {}).title || other))
          }
        }
        backend.updateCommand(id, function(s) {
          if (data.alias !== undefined) { if (data.alias) s.alias = String(data.alias).trim().toLowerCase(); else delete s.alias }
          if (data.enabled !== undefined) { if (data.enabled === false) s.enabled = false; else delete s.enabled }
          return s
        })
        return settingsStore.doc.commands[id] || {}
      }
    })

    Rpc.register(backend.registry, "rootSearch", {
      search: function(data) {
        var query = String(data && data.query || "")
        var view = data && data.view
        var ctx = backend.searchContext()
        var sections
        if (view && view.kind === "disabled-commands") {
          var hidden = backend.candidates.filter(function(c) { return ctx.commands[c.id] && ctx.commands[c.id].enabled === false })
          var restored = hidden.map(function(c) { var r = Object.assign({}, c); r.kind = "disabled-command"; return r })
          sections = [{ id: "disabled", title: "Disabled Commands", rows: Ranker.rank(restored, query, { nowMs: ctx.nowMs }) }]
        }
        else if (view && view.kind === "menu") sections = RootSearch.submenuSections(backend.candidates, view.menuId, query, ctx, backend.deps)
        else if (view && view.kind === "calculator-history") sections = RootSearch.historySections(calculatorStore.doc.history, query, ctx.nowMs, Calculator.filterHistory)
        else {
          ctx.filter = String(data && data.filter || "all")
          if (query.trim() && ctx.filter === "all") ctx.calculation = backend.calculate(query)
          sections = RootSearch.rootSections(backend.candidates, query, ctx, backend.deps)
        }
        return sections.map(function(s) {
          return { id: s.id, title: s.title, rows: s.rows.map(function(r) { return r.candidate }) }
        })
      },
      getActions: function(data) {
        var rowId = String(data && data.id || "")
        if (rowId === RootSearch.CALCULATOR_ID) return RootSearch.actionsFor({ kind: "calculator" })
        if (rowId.indexOf("calculator-history:") === 0) return RootSearch.actionsFor({ kind: "calculator-history" })
        var candidate = backend.decorated(rowId)
        if (!candidate) {
          var fallback = RootSearch.FALLBACKS.filter(function(f) { return f.id === data.id })[0]
          if (!fallback) throw new Error("Unknown command " + (data && data.id))
          return RootSearch.actionsFor({ kind: "fallback", title: fallback.title })
        }
        if (candidate && settingsStore.doc.commands[rowId] && settingsStore.doc.commands[rowId].enabled === false) return RootSearch.actionsFor({ kind: "disabled-command" })
        return RootSearch.actionsFor(candidate)
      },
      getItemInfo: function(data) {
        var rowId = String(data && data.id || ""), nowMs = Date.now()
        if (rowId === RootSearch.CALCULATOR_ID) {
          var calc = backend.calculate(String(data.query || ""))
          return calc ? RootSearch.aboutFor(RootSearch.calculatorCandidate(calc), nowMs) : []
        }
        if (rowId.indexOf("calculator-history:") === 0) {
          var entry = backend.historyEntry(rowId)
          return entry ? RootSearch.aboutFor(RootSearch.historyCandidate(entry, nowMs), nowMs) : []
        }
        var candidate = backend.decorated(rowId)
        if (!candidate) {
          var fallback = RootSearch.FALLBACKS.filter(function(x) { return x.id === rowId })[0]
          if (!fallback) throw new Error("Unknown command " + rowId)
          return RootSearch.aboutFor({ id: fallback.id, kind: "fallback", title: fallback.title, typeLabel: "Fallback", url: fallback.url }, nowMs)
        }
        return RootSearch.aboutFor(candidate, nowMs)
      },
      performAction: function(data) {
        if (!(data && data.confirmed)) {
          var confirmation = RootSearch.confirmationFor(String(data && data.id || ""), String(data && data.action || "open"))
          if (confirmation) return { confirm: confirmation }
        }
        var fallback = RootSearch.FALLBACKS.filter(function(f) { return f.id === (data && data.id) })[0]
        if (fallback) {
          if (fallback.id === Agent.FALLBACK_ID) {
            agentLauncher.start(data.query)
            return { pending: true }
          }
          Util.execArgv(["xdg-open", RootSearch.fallbackUrl(fallback, data.query)])
          return { close: true }
        }
        // The calculator row is the query itself, evaluated again.
        if (data && data.id === RootSearch.CALCULATOR_ID) {
          var calc = backend.calculate(String(data.query || ""))
          if (!calc) throw new Error("Nothing to calculate")
          return backend.calculatorAction(String(data.action || "open"), { query: calc.input, result: calc.result, copy: calc.copy, kind: calc.kind }, "")
        }
        if (data && String(data.id).indexOf("calculator-history:") === 0) {
          var entry = backend.historyEntry(data.id)
          if (!entry) throw new Error("No such history entry")
          return backend.calculatorAction(String(data.action || "open"), entry, entry.id)
        }
        return backend.performAction(data)
      },
      getSearchHistory: function() { return frecencyStore.loaded ? frecencyStore.doc.searchHistory : [] }
    })

    // Names from Raycast's calculator namespace (ref 02 §2).
    Rpc.register(backend.registry, "calculator", {
      calculate: function(data) { return backend.calculate(String(data && data.query || "")) },
      historyGetAll: function() { return calculatorStore.loaded ? calculatorStore.doc.history : [] },
      historyDelete: function(data) { return backend.calculatorAction("delete-entry", null, String(data && data.id || "")) },
      historyDeleteAll: function() { return backend.calculatorAction("delete-all-entries", null, "") },
      refreshCurrencies: function() {
        if (!backend.config.currencyRates) throw new Error("currencyRates is off in config.json")
        calculatorData.fetchRates()
        return null
      },
      getCurrencies: function() {
        var r = calculatorData.rates
        return {
          enabled: backend.config.currencyRates,
          date: r ? r.date : null,
          base: r ? r.base : null,
          currencies: r ? Object.keys(r.rates).concat([r.base]).sort() : [],
          fetchedAt: calculatorData.ratesFetchedAt || null,
          zones: Object.keys(calculatorData.zones).length
        }
      }
    })

    Rpc.register(backend.registry, "frecency", {
      visit: function(data) { backend.recordVisit(String(data.id), String(data.query || "")); return null },
      get: function(data) {
        var entry = frecencyStore.doc.items[String(data && data.id || "")]
        return entry ? { anchor: entry.anchor, openedAt: entry.openedAt, score: Frecency.score(entry.anchor, Date.now() / 1000), searchTerms: entry.searchTerms } : null
      }
    })
  }

  Component.onCompleted: {
    registerServices()
    mkdirs.running = true
  }

  onAppLibraryChanged: rebuildTimer.restart()

  Connections {
    target: backend.appLibrary
    ignoreUnknownSignals: true
    function onAppsChanged() { rebuildTimer.restart() }
  }

  Connections {
    target: backend.appLibrary ? null : DesktopEntries.applications
    ignoreUnknownSignals: true
    function onValuesChanged() { rebuildTimer.restart() }
  }

  Component.onDestruction: { settingsStore.flush(); frecencyStore.flush(); calculatorStore.flush() }
  onNotification: function(method, data) {
    if (method === "window.visibilityChanged" && data && data.visible) {
      menuSource.refresh()
      calculatorData.refresh()
    }
    if (method === "window.visibilityChanged" && data && !data.visible) agentLauncher.cancel()
  }

  AgentLauncher {
    id: agentLauncher
    onPrepared: function(argv) { backend.emit("agent.launchReady", { argv: argv }) }
    onFailed: function(message) { backend.emit("agent.launchFailed", { message: message }) }
  }


  Process {
    id: mkdirs
    command: ["mkdir", "-p"].concat(Paths.directoriesToCreate(backend.paths))
    onExited: function(exitCode) {
      if (exitCode !== 0) backend.log("error", "paths", "could not create data directories", { exitCode: exitCode })
      backend.directoriesReady = true
    }
  }

  DesktopSource {
    id: menuSource
    onRevisionChanged: rebuildTimer.restart()
    onMessage: function(level, text, metadata) { backend.log(level, "desktop", text, metadata) }
  }

  JsonStore {
    id: settingsStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.settings.file
    migrations: Schema.documents.settings.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  JsonStore {
    id: frecencyStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.frecency.file
    migrations: Schema.documents.frecency.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  JsonStore {
    id: calculatorStore
    ready: backend.directoriesReady
    path: backend.paths.db + "/" + Schema.documents.calculator.file
    migrations: Schema.documents.calculator.migrations
    onMessage: function(level, text, metadata) { backend.log(level, "store", text, metadata) }
  }

  CalculatorData {
    id: calculatorData
    cacheDir: backend.directoriesReady ? backend.paths.cache : ""
    ratesEnabled: backend.config.currencyRates
    onMessage: function(level, text, metadata) { backend.log(level, "calculator", text, metadata) }
  }

  readonly property int dataRevision: candidatesRevision + (settingsStore.loaded ? 1 : 0) + (frecencyStore.loaded ? 1 : 0)
  property int storeRevision: 0
  Connections { target: settingsStore; function onChanged() { backend.storeRevision++ } }
  Connections { target: frecencyStore; function onChanged() { backend.storeRevision++ } }
  Connections { target: calculatorStore; function onChanged() { backend.storeRevision++ } }

  FileView {
    path: backend.directoriesReady ? backend.paths.configFile : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        backend.config = Schema.withConfigDefaults(JSON.parse(text()))
      } catch (e) {
        backend.config = Schema.withConfigDefaults(null)
        backend.log("warning", "config", "ignoring unreadable " + path + ": " + e)
      }
    }
    onLoadFailed: backend.config = Schema.withConfigDefaults(null)
  }
}
