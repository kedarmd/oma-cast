#!/usr/bin/env python3
"""Opt-in service-lifetime regression; uses disposable processes, never the bar."""
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parent.parent


def wait_for(check, timeout=5):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = check()
        if value:
            return value
        time.sleep(.05)
    raise AssertionError('Fixture did not become ready')


def alive(pid):
    try:
        return Path(f'/proc/{pid}/stat').read_text().split()[2] != 'Z'
    except FileNotFoundError:
        return False


def main():
    unit = 'kay-cast-lifetime-test-' + uuid.uuid4().hex + '.service'
    child = None
    with tempfile.TemporaryDirectory(prefix='kay-cast-lifetime-') as temp:
        root = Path(temp)
        marker = root / 'child.pid'
        shell = root / 'shell.qml'
        literal_args = ['--leading-flag', '$HOME', '$(must-not-run)', 'line\none 🚀']
        argv = ['/bin/bash', '-c', 'marker=$1; shift; printf "%s\\0" "$@" > "$marker.args"; printf "%s" "$$" > "$marker"; exec sleep 60', 'fixture', str(marker), *literal_args]
        shell.write_text('import QtQuick\nimport Quickshell\n'
                         f'import "{(REPO / "plugin/compat").as_uri()}"\n'
                         'ShellRoot { Component.onCompleted: Quickshell.watchFiles = false\n'
                         f'Timer {{ interval: 50; running: true; onTriggered: Util.execArgv({json.dumps(argv)}) }}\n}}\n')
        command = ['systemd-run', '--user', '--quiet', '--collect', '--service-type=exec', '--unit=' + unit]
        for name in ['PATH', 'WAYLAND_DISPLAY', 'DISPLAY', 'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS', 'QT_QPA_PLATFORM']:
            if name in os.environ:
                command.append('--setenv=' + name)
        try:
            subprocess.run(command + ['qs', '-p', str(shell)], check=True)
            wait_for(marker.exists)
            child = int(marker.read_text())
            assert Path(str(marker) + '.args').read_bytes().split(b'\0')[:-1] == [a.encode() for a in literal_args]
            group = Path(f'/proc/{child}/cgroup').read_text().strip()
            print('Child control group:', group, flush=True)
            assert unit not in group, 'Launched process inherits the launcher service; restarting the launcher kills it'
            subprocess.run(['systemctl', '--user', 'stop', unit], check=True)
            time.sleep(.15)
            assert alive(child), 'Launched process died with its launcher'
            print('  ok    launched processes survive their launcher service stopping')
        finally:
            subprocess.run(['systemctl', '--user', 'stop', unit], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if child and alive(child):
                os.kill(child, signal.SIGTERM)


if __name__ == '__main__':
    main()
