const test = require('node:test')
const assert = require('node:assert/strict')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const helper = path.resolve(__dirname, '../bin/kay-cast-launch')

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'kay-cast-launch-'))
  t.after(() => fs.rmSync(root, { recursive: true, force: true }))
  const bin = path.join(root, 'bin')
  fs.mkdirSync(bin)
  const cwd = path.join(root, 'a directory')
  fs.mkdirSync(cwd)
  function script(name, body) { fs.writeFileSync(path.join(bin, name), '#!/bin/bash\n' + body, { mode: 0o700 }) }
  script('systemctl', 'exit "${TEST_NO_MANAGER:-0}"\n')
  script('systemd-run', 'printf "%s\\0" "$@" > "$TEST_ARGS"\n')
  const env = { ...process.env, PATH: bin, TEST_ARGS: path.join(root, 'args'), TEST_CUSTOM_ENV: 'inherited value', NOTIFY_SOCKET: '/old/service/socket' }
  const run = argv => spawnSync('/bin/bash', [helper, cwd, ...argv], { env, encoding: 'utf8' })
  return { root, cwd, env, run }
}

test('launches use an independent user service and preserve literal arguments', t => {
  const f = fixture(t)
  const argv = ['/program', '--flag', '$HOME', '$(not shell code)', 'new\nline 🚀']
  const result = f.run(argv)
  assert.equal(result.status, 0, result.stderr)
  const args = fs.readFileSync(f.env.TEST_ARGS, 'utf8').split('\0').slice(0, -1)
  assert.ok(args.includes('--property=ExitType=cgroup'))
  assert.ok(args.includes('--expand-environment=no'))
  assert.ok(args.includes('--working-directory=' + f.cwd))
  assert.ok(args.includes('--setenv=TEST_CUSTOM_ENV'))
  assert.ok(!args.includes('--setenv=NOTIFY_SOCKET'))
  assert.ok(!args.some(arg => arg.includes('inherited value')))
  assert.deepEqual(args.slice(args.indexOf('--') + 1), argv)
})

test('manual launches without a user manager retain cwd and argv', t => {
  const f = fixture(t)
  f.env.TEST_NO_MANAGER = '1'
  const result = f.run(['/bin/bash', '-c', 'printf "%s\\n" "$PWD" "$1"', 'fixture', '$HOME literal'])
  assert.equal(result.status, 0, result.stderr)
  assert.equal(result.stdout, f.cwd + '\n$HOME literal\n')
  assert.ok(!fs.existsSync(f.env.TEST_ARGS))
})
