#!/usr/bin/env bash
# Live desktop acceptance: no typing, launching apps, paste or power changes.
set -euo pipefail
cd "$(dirname "$0")/.."
bin/kay-cast doctor
python3 - <<'PY'
import json
import os
from pathlib import Path
import socket
import subprocess
import time

cli = str(Path('bin/kay-cast').resolve())

def command(*args):
    return subprocess.check_output([cli, *args], text=True).strip()

def rpc(method, data=None):
    result = json.loads(command('call', method, json.dumps(data or {})))
    assert result['ok'], result
    return result['data']

info = rpc('system.info')
assert info['ready'] and info['platform'] == 'kmdot', info
assert info['candidates'] > 0
assert json.loads(command('call', 'foo.bar'))['ok'] is False
assert 'popToRootTimeout' in rpc('settings.getGeneralSettings')
assert rpc('calculator.calculate', {'query': '5 ft to cm'})
sections = rpc('rootSearch.search', {'query': 'zzzz-no-match'})
assert sections[-1]['id'] == 'fallback-commands'
applications = rpc('rootSearch.search', {'query': '', 'filter': 'applications'})
assert applications and all(row['type'] == 'application' for section in applications for row in section['rows'])
commands = rpc('rootSearch.search', {'query': 'google', 'filter': 'commands'})
assert all(row['type'] == 'command' for section in commands for row in section['rows'])
quicklinks = rpc('rootSearch.search', {'query': 'google'})
google = next(row for section in quicklinks for row in section['rows'] if row['id'] == 'builtin:google-search')
details = rpc('rootSearch.getItemInfo', {'id': google['id']})
assert any(row['label'] == 'Arguments' and row['value'] == 'query' for row in details)
confirmation = rpc('rootSearch.performAction', {'id': 'calculator-history:fixture', 'action': 'delete-all-entries'})
assert confirmation['confirm']['destructive'] is True
rows = [r for s in rpc('rootSearch.search') for r in s['rows']]
assert not any(r['id'].startswith('omarchy:') or r['id'] == 'builtin:omarchy-menu' for r in rows)
print(f'  ok    RPC, calculator and {info["candidates"]} indexed apps/commands')

# Listen only to this Hyprland socket; no subprocess watcher or global pkill.
runtime = os.environ['XDG_RUNTIME_DIR']
signature = os.environ['HYPRLAND_INSTANCE_SIGNATURE']
sock = socket.socket(socket.AF_UNIX)
sock.settimeout(2)
sock.connect(f'{runtime}/hypr/{signature}/.socket2.sock')
original_open = subprocess.check_output(['qs', 'ipc', '-p', str(Path('shell.qml').resolve()), 'call', '--', 'kay-cast', 'isOpen'], text=True).strip() == 'true'

def wait_layer(kind):
    buffer = b''
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        buffer += sock.recv(65536)
        while b'\n' in buffer:
            line, buffer = buffer.split(b'\n', 1)
            if line.startswith(kind.encode() + b'>>') and b'kay-cast' in line:
                return
    raise AssertionError('Missing layer event: ' + kind)

try:
    if original_open:
        command('hide')
        wait_layer('closelayer')
    worst = 0
    for _ in range(3):
        start = time.monotonic()
        assert command('show') == 'shown'
        wait_layer('openlayer')
        elapsed = (time.monotonic() - start) * 1000
        worst = max(worst, elapsed)
        assert command('hide') == 'hidden'
        wait_layer('closelayer')
    assert worst < 250, worst
    print(f'  ok    show/hide mapping; worst show {worst:.0f} ms (250 ms budget)')
finally:
    sock.close()
    command('show' if original_open else 'hide')
PY
