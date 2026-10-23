const test = require("node:test")
const assert = require("node:assert/strict")
const Paths = require("../plugin/core/Paths.js")

const envOf = (vars) => (name) => vars[name] || ""

test("defaults follow the XDG base directory spec", () => {
  const p = Paths.resolve(envOf({ HOME: "/home/u", XDG_RUNTIME_DIR: "/run/user/1000" }))
  assert.equal(p.config, "/home/u/.config/kay-cast")
  assert.equal(p.configFile, "/home/u/.config/kay-cast/config.json")
  assert.equal(p.db, "/home/u/.local/share/kay-cast/db")
  assert.equal(p.extensions, "/home/u/.local/share/kay-cast/extensions")
  assert.equal(p.cache, "/home/u/.cache/kay-cast")
  assert.equal(p.logs, "/home/u/.local/state/kay-cast/logs")
  assert.equal(p.runtime, "/run/user/1000/kay-cast")
  assert.equal(p.scriptCommands, "/home/u/.config/kay-cast/script-commands")
})

test("absolute XDG overrides win, relative ones are ignored", () => {
  const p = Paths.resolve(envOf({
    HOME: "/home/u/",
    XDG_CONFIG_HOME: "/cfg/",
    XDG_DATA_HOME: "relative/data",
    XDG_STATE_HOME: "/st"
  }))
  assert.equal(p.config, "/cfg/kay-cast")
  assert.equal(p.data, "/home/u/.local/share/kay-cast")
  assert.equal(p.state, "/st/kay-cast")
})

test("missing HOME is an error", () => {
  assert.throws(() => Paths.resolve(envOf({})), /HOME is not set/)
})

test("startup creates the persistent dirs and the runtime dir", () => {
  const p = Paths.resolve(envOf({ HOME: "/h", XDG_RUNTIME_DIR: "/r" }))
  assert.deepEqual(Paths.directoriesToCreate(p), [
    "/h/.config/kay-cast", "/h/.local/share/kay-cast/db", "/h/.cache/kay-cast",
    "/h/.local/state/kay-cast/logs", "/h/.local/state/kay-cast/backups", "/r/kay-cast"
  ])
})
