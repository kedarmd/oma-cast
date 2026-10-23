const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const { spawnSync } = require("node:child_process")
const Agent = require("../plugin/core/Agent.js")
const helper = path.resolve(__dirname, "../bin/kay-cast-desktop")

function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "kay-cast-agent-"))
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))
  const script = (name, source) => fs.writeFileSync(path.join(dir, name), "#!/bin/bash\n" + source, { mode: 0o700 })
  for (const name of ["opencode", "codex", "claude", "ghostty", "kitty", "foot", "alacritty"]) script(name, "exit 99\n")
  const env = { ...process.env, PATH: dir, KAY_CAST_AGENT: "opencode", KAY_CAST_TERMINAL: "ghostty" }
  const run = (args, extra) => spawnSync("/bin/bash", [helper, ...args], { env: { ...env, ...extra }, encoding: "utf8" })
  return { dir, script, run }
}

test("agent preflight validates supported local agents and terminals without executing them", t => {
  const f = fixture(t)
  for (const agent of ["opencode", "codex", "claude"]) for (const terminal of ["ghostty", "kitty", "foot", "alacritty"]) {
    const r = f.run(["agent-check"], { KAY_CAST_AGENT: agent, KAY_CAST_TERMINAL: terminal })
    assert.equal(r.status, 0, r.stderr)
  }
  assert.match(f.run(["agent-check"], { KAY_CAST_AGENT: "invalid" }).stderr, /KAY_CAST_AGENT/)
  assert.match(f.run(["agent-check"], { KAY_CAST_TERMINAL: "invalid" }).stderr, /KAY_CAST_TERMINAL/)
  fs.unlinkSync(path.join(f.dir, "opencode"))
  assert.match(f.run(["agent-check"]).stderr, /Agent not installed/)
})

test("terminal and agent receive literal prompt arguments including leading flags and shell code", t => {
  const f = fixture(t)
  f.script("ghostty", '[[ $1 == -e ]] || exit 8\nshift\nexec "$@"\n')
  f.script("opencode", '[[ $# == 2 && $1 == --prompt ]] || exit 8\nprintf "%s" "$2"\n')
  f.script("codex", '[[ $# == 2 && $1 == -- ]] || exit 8\nprintf "%s" "$2"\n')
  f.script("claude", '[[ $# == 2 && $1 == -- ]] || exit 8\nprintf "%s" "$2"\n')
  const marker = path.join(f.dir, "must-not-exist")
  for (const agent of ["opencode", "codex", "claude"]) for (const prompt of ["--help", "  Why?  ", 'Quotes: "hello" and \'hi\'', "line one\nline two 🚀", `$(touch ${marker}); \`touch ${marker}\`; >${marker}`]) {
    const argv = Agent.launchArgv(prompt, helper)
    const r = f.run(argv.slice(1), { KAY_CAST_AGENT: agent })
    assert.equal(r.status, 0, r.stderr)
    assert.equal(r.stdout, prompt)
    assert.ok(!fs.existsSync(marker))
  }
})

test("empty, NUL and oversized prompts fail before any process starts", () => {
  for (const query of [null, undefined, "", " \n\t "]) assert.throws(() => Agent.launchArgv(query), /Type a question/)
  assert.throws(() => Agent.launchArgv("a\0b"), /NUL/)
  assert.throws(() => Agent.launchArgv("x".repeat(16385)), /characters/)
  assert.equal(Agent.launchArgv("x".repeat(16384))[2].length, 16384)
})

test('paste adapter copies literal text and uses the restored window’s paste chord', t => {
  const f = fixture(t)
  f.script('sleep', 'exit 0\n')
  f.script('sed', 'exec /usr/bin/sed "$@"\n')
  f.script('hyprctl', 'printf \'{"class":"%s"}\\n\' "$TEST_CLASS"\n')
  f.script('wl-copy', '/bin/cat > "$TEST_COPY"\n')
  f.script('wtype', 'printf "%s\\n" "$@" > "$TEST_KEYS"\n')
  const copied = path.join(f.dir, 'copied')
  const keys = path.join(f.dir, 'keys')
  const text = '--literal\n$(touch nope) 🚀'
  for (const windowClass of ['com.mitchellh.ghostty', 'kitty', 'Alacritty', 'foot', 'zen']) {
    const result = f.run(['paste', text], { TEST_CLASS: windowClass, TEST_COPY: copied, TEST_KEYS: keys })
    assert.equal(result.status, 0, result.stderr)
    assert.equal(fs.readFileSync(copied, 'utf8'), text)
    const chord = fs.readFileSync(keys, 'utf8')
    assert.match(chord, /ctrl/)
    assert.equal(chord.includes('shift'), windowClass !== 'zen')
  }
})
