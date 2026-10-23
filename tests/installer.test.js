const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const cli = path.resolve(__dirname, '../bin/kay-cast')
const setup = path.resolve(__dirname, '../bin/kay-cast-hyprland.py')

function fixture(t, type = 'lua') {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'kay-cast-install-'))
  t.after(() => fs.rmSync(home, { recursive: true, force: true }))
  const bin = path.join(home, 'bin')
  fs.mkdirSync(bin)
  const config = path.join(home, '.config')
  const hypr = path.join(config, 'hypr')
  fs.mkdirSync(hypr, { recursive: true })
  const main = path.join(hypr, 'hyprland.' + type)
  fs.writeFileSync(main, type === 'lua' ? 'require("keybinds")\n' : '# User config\n')
  function script(name, body) { fs.writeFileSync(path.join(bin, name), '#!/bin/bash\n' + body, { mode: 0o700 }) }
  script('qs', 'printf "%s\\n" "$*" >> "$HOME/qs.log"\n[[ $* != *" ping"* ]] || printf "ok\\n"\n')
  script('systemctl', 'printf "%s\\n" "$*" >> "$HOME/systemctl.log"\n')
  script('hyprctl', 'if [[ $1 == binds ]]; then printf "%s" "${TEST_BINDS:-[]}"; fi\n')
  const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: config, PATH: bin + ':' + process.env.PATH }
  const run = args => spawnSync('/bin/bash', [cli, ...args], { env, encoding: 'utf8' })
  const bind = action => spawnSync('python3', [setup, action], { env, encoding: 'utf8' })
  return { home, config, hypr, main, env, run, bind }
}

test('install is repeatable, scopes IPC and uninstall preserves user data', t => {
  const f = fixture(t)
  for (let n = 0; n < 2; n++) assert.equal(f.run(['install']).status, 0)
  const service = path.join(f.config, 'systemd/user/kay-cast.service')
  assert.match(fs.readFileSync(service, 'utf8'), /Restart=always/)
  const data = path.join(f.config, 'kay-cast/commands.json')
  fs.writeFileSync(data, '[]')
  assert.equal(f.run(['show']).status, 0)
  assert.match(fs.readFileSync(path.join(f.home, 'qs.log'), 'utf8'), /ipc -p .*shell.qml call -- kay-cast show/)
  assert.equal(f.run(['uninstall']).status, 0)
  assert.ok(!fs.existsSync(service))
  assert.ok(!fs.existsSync(path.join(f.home, '.local/bin/kay-cast')))
  assert.equal(fs.readFileSync(data, 'utf8'), '[]')
})

test('installer refuses existing files and foreign symlinks', t => {
  const f = fixture(t)
  fs.mkdirSync(path.join(f.home, '.local/bin'), { recursive: true })
  const link = path.join(f.home, '.local/bin/kay-cast')
  fs.writeFileSync(link, 'user file')
  assert.notEqual(f.run(['install']).status, 0)
  assert.equal(fs.readFileSync(link, 'utf8'), 'user file')
})

for (const type of ['lua', 'conf']) test(`binding setup is idempotent and reversible for ${type}`, t => {
  const f = fixture(t, type)
  const original = fs.readFileSync(f.main, 'utf8')
  assert.equal(f.bind('setup').status, 0)
  if (type === 'lua') f.env.TEST_BINDS = JSON.stringify([{ modmask: 8, key: 'SPACE', dispatcher: '__lua', arg: '10' }])
  assert.equal(f.bind('setup').status, 0)
  const config = fs.readFileSync(f.main, 'utf8')
  assert.equal(config.match(/managed by kay-cast/g).length, 1)
  if (type === 'lua') assert.match(fs.readFileSync(path.join(f.hypr, 'kay-cast.lua'), 'utf8'), /hl.bind\(/)
  assert.equal(f.bind('uninstall').status, 0)
  assert.equal(fs.readFileSync(f.main, 'utf8').trim(), original.trim())
})

test('binding conflicts fail without changing config; edited modules survive uninstall', t => {
  const f = fixture(t)
  f.env.TEST_BINDS = JSON.stringify([{ modmask: 8, key: 'SPACE', dispatcher: 'exec', arg: 'user-app' }])
  assert.notEqual(f.bind('setup').status, 0)
  assert.equal(fs.readFileSync(f.main, 'utf8'), 'require("keybinds")\n')
  f.env.TEST_BINDS = '[]'
  assert.equal(f.bind('setup').status, 0)
  const module = path.join(f.hypr, 'kay-cast.lua')
  fs.appendFileSync(module, '-- User customization\n')
  assert.equal(f.bind('uninstall').status, 0)
  assert.ok(fs.existsSync(module))
  assert.match(fs.readFileSync(f.main, 'utf8'), /require\("kay-cast"\)/)
})
