const test = require('node:test')
const assert = require('node:assert/strict')
const Desktop = require('../plugin/core/Desktop.js')
const Theme = require('../plugin/core/Theme.js')
const fs = require('node:fs')
const os = require('node:os')
const path = require('node:path')
const { spawnSync } = require('node:child_process')
const RS = require('../plugin/core/RootSearch.js')

test('desktop catalog requires available integrations and keeps paths literal', () => {
  assert.deepEqual(Desktop.catalog('', '/missing'), [])
  const root = '/a directory/$(not-a-command)'
  const rows = Desktop.catalog('script:toggle.sh\ntool:qs\ntool:hyprshot\nscript:theme-switcher\ntheme:nord\ntheme:../evil\n', root)
  assert.deepEqual(rows.find(c => c.id === 'kmdot:themes').argv, [root + '/kmdot/quickshell/scripts/toggle.sh', 'kmdot-theme'])
  assert.deepEqual(rows.find(c => c.id === 'kmdot:theme-nord').argv, [root + '/kmdot/theme-switcher/main.sh', 'nord'])
  assert.equal(rows.filter(c => c.id.startsWith('kmdot:theme-')).length, 1)
  assert.equal(rows.filter(c => c.id.startsWith('kmdot:screenshot-')).length, 3)
  assert.ok(!rows.some(c => c.id.startsWith('omarchy:')))
  assert.equal(new Set(rows.map(c => c.id)).size, rows.length)
})

test('custom commands validate unique IDs and argv boundaries before replacing the catalog', () => {
  const argv = ['printf', '$(touch forbidden)', '--', 'line\none']
  const result = Desktop.customCandidates([{ id: 'test', title: 'Test', argv }])
  assert.deepEqual(result[0].argv, argv)
  argv.push('later mutation')
  assert.equal(result[0].argv.length, 4)
  for (const bad of [{}, [{ id: 'x', title: 'Test', argv: 'sh -c dangerous' }], [{ id: 'x', title: 'Test', argv: ['x\0'] }], [{ id: 'x', title: 'Test', argv: ['true'] }, { id: 'x', title: 'Other', argv: ['false'] }]]) {
    assert.throws(() => Desktop.customCandidates(bad))
  }
  assert.equal(RS.actionsFor({ kind: 'desktop-action' })[1].id, 'copy-command')
  assert.equal(RS.actionsFor({ kind: 'disabled-command' })[0].id, 'enable')
})

test('theme parser accepts Qt ARGB literals and rejects incomplete or executable values', () => {
  const palette = { surface_high: '#16161e', text: '#c0caf5', primary: '#7aa2f7', primary_container: '#40292e42', on_primary_container: '#c0caf5', outline_variant: '#292e42' }
  const source = Object.entries(palette).map(([k, v]) => `readonly property color ${k}: "${v}"`).join('\n')
  assert.deepEqual(Theme.parse(source), palette)
  assert.throws(() => Theme.parse(source.replace('"#c0caf5"', 'runCode()')), /Missing/)
  assert.throws(() => Theme.parse('property color text: "#fff"'), /Missing/)
})

test('all installed kmDot theme renders satisfy the adapter contract', { skip: !fs.existsSync(path.join(os.homedir(), 'dev/kmDot/theme-switcher/render-quickshell.sh')) }, () => {
  const repo = path.join(os.homedir(), 'dev/kmDot')
  for (const theme of ['catppuccin', 'everforest', 'nord', 'tokyonight']) {
    const r = spawnSync('bash', [path.join(repo, 'theme-switcher/render-quickshell.sh'), path.join(repo, 'themes', theme, 'quickshell.conf')], { encoding: 'utf8' })
    assert.equal(r.status, 0, r.stderr)
    assert.ok(Theme.parse(r.stdout).primary)
  }
})

test('local binding hints and current theme decorate stable command identities', () => {
  const rows = Desktop.catalog('script:toggle.sh\nscript:theme-switcher\ntheme:nord\ntool:ghostty\n', '/config')
  const output = Desktop.decorate(rows, 'SUPER + T\tThemes\tkmdot-theme\nSUPER + RETURN\tTerminal\texec:/usr/bin/ghostty\n', 'nord\n', '/config')
  assert.match(output.find(c => c.id === 'kmdot:themes').subtitle, /SUPER \+ T/)
  assert.equal(output.find(c => c.id === 'kmdot:terminal').shortcut, 'SUPER + RETURN')
  assert.ok(output.find(c => c.id === 'kmdot:theme-nord').checked)
  assert.equal(rows.find(c => c.id === 'kmdot:terminal').shortcut, undefined)
})

test('Copy Command produces a runnable shell command without interpreting its arguments', () => {
  const values = ["single'quote", 'a directory', '$(exit 99)', '--flag', 'line\none']
  const r = spawnSync('/bin/bash', ['-c', Desktop.commandText(['/usr/bin/printf', '%s\\0', ...values])], { encoding: 'utf8' })
  assert.equal(r.status, 0, r.stderr)
  assert.deepEqual(r.stdout.split('\0').slice(0, -1), values)
})
