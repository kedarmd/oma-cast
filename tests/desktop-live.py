#!/usr/bin/env python3
"""Opt-in Wayland integration checks with isolated config, data, apps and palette.

Does not map a launcher, switch the desktop theme or contact an agent.
"""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
from urllib.parse import unquote

REPO = Path(__file__).resolve().parent.parent
QS = shutil.which('qs')


def wait_for(check, timeout=5):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = check()
            if last:
                return last
        except (AssertionError, KeyError, ValueError, subprocess.SubprocessError):
            pass
        time.sleep(.05)
    raise AssertionError(f'Timed out: {last}')


def main():
    with tempfile.TemporaryDirectory(prefix='kay-cast-live-') as temp:
        root = Path(temp)
        config, data, cache = root / 'config', root / 'data', root / 'cache'
        for p in [config / 'kay-cast', data / 'applications', cache, root / 'bin']:
            p.mkdir(parents=True, exist_ok=True)
        (config / 'kay-cast/config.json').write_text('{"currencyRates":false}')
        palette = root / 'colors/Colors.qml'
        palette.parent.mkdir()
        roles = dict(surface_high='#16161e', text='#c0caf5', primary='#7aa2f7',
                     primary_container='#40292e42', on_primary_container='#c0caf5', outline_variant='#292e42')

        def write_palette(colors):
            pending = palette.with_suffix('.pending')
            pending.write_text('\n'.join(f'property color {k}: "{v}"' for k, v in colors.items()))
            pending.replace(palette)

        write_palette(roles)
        marker = root / 'launched'
        executable = root / 'bin/test-app'
        executable.write_text('#!/bin/bash\nprintf "%s\\n" "$PWD" "$@" > ' + str(marker) + '\n')
        executable.chmod(0o700)
        terminal_marker = root / 'terminal-launched'
        terminal = root / 'bin/ghostty'
        terminal.write_text('#!/bin/bash\nprintf "terminal" > ' + str(terminal_marker) + '\n[[ $1 == -e ]] || exit 9\nshift\nexec "$@"\n')
        terminal.chmod(0o700)
        app = data / 'applications/kay-cast-fixture.desktop'
        app.write_text(f'[Desktop Entry]\nType=Application\nName=kay-cast fixture\nExec={executable} "literal argument" %f\nPath={root}\nTerminal=false\n')
        (data / 'applications/kay-cast-fixture-terminal.desktop').write_text(app.read_text().replace('Terminal=false', 'Terminal=true'))
        shell = root / 'shell.qml'
        shell.write_text('import QtQuick\nimport Quickshell\nimport Quickshell.Io\n'
                         f'import "{(REPO / "plugin").as_uri()}"\n'
                         f'import "{(REPO / "plugin/ui").as_uri()}"\n'
                         'ShellRoot {\nComponent.onCompleted: Quickshell.watchFiles = false\nLauncher {}\nBrandMark { id: fixtureLogo; width: 24; height: 24 }\n'
                         'IpcHandler { target: "fixture"\n'
                         'function logo(): string { return fixtureLogo.source.toString() }\n'
                         'function entry(): string { var e = DesktopEntries.byId("kay-cast-fixture"); return JSON.stringify({ command: e.command, terminal: e.runInTerminal }) }\n}\n}\n')
        env = dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
                   XDG_CACHE_HOME=str(cache), XDG_STATE_HOME=str(root / 'state'),
                   KAY_CAST_THEME_FILE=str(palette), KAY_CAST_TERMINAL="ghostty", PATH=str(root / 'bin') + ':' + os.environ['PATH'])
        with (root / 'log').open('w+') as log:
            proc = subprocess.Popen([QS, '-p', str(shell)], env=env, stdout=log, stderr=log)

            def ipc(target, method, *args):
                return subprocess.check_output([QS, 'ipc', '-p', str(shell), 'call', '--', target, method, *args], text=True, stderr=subprocess.DEVNULL).strip()

            def rpc(method, params=None):
                result = json.loads(ipc('kay-cast', 'call', method, json.dumps(params or {})))
                assert result['ok'], result
                return result['data']

            try:
                wait_for(lambda: rpc('system.info')['ready'])
                wait_for(lambda: rpc('system.info')['theme']['loaded'])
                assert rpc('system.info')['theme']['palette']['primary'] == roles['primary']
                roles['primary'] = '#abcdef'
                write_palette(roles)
                wait_for(lambda: rpc('system.info')['theme']['palette']['primary'] == '#abcdef')
                for color in ['#a7c080', '#88c0d0', '#cba6f7', '#a7c080']:
                    roles['primary'] = color
                    write_palette(roles)
                    wait_for(lambda: rpc('system.info')['theme']['palette']['primary'] == color, timeout=2)
                print('  ok    repeated atomic palette replacement (Everforest / Nord colors)')
                # kmDot sync replaces the containing config directory; file-only
                # replacement coverage misses a watcher lost with that directory.
                shutil.rmtree(palette.parent)
                wait_for(lambda: rpc('system.info')['theme']['error'], timeout=2)
                palette.parent.mkdir()
                roles['primary'] = '#88c0d0'
                write_palette(roles)
                wait_for(lambda: rpc('system.info')['theme']['palette']['primary'] == roles['primary'], timeout=2)
                roles['primary'] = '#a7c080'
                write_palette(roles)
                wait_for(lambda: rpc('system.info')['theme']['palette']['primary'] == roles['primary'], timeout=2)
                print('  ok    palette watch recovers after directory replacement and keeps following edits')
                # Exercise full generated palettes too when the user's kmDot
                # checkout is available; synthetic fixtures remain portable.
                kmdot = Path.home() / 'dev/kmDot'
                renderer = kmdot / 'theme-switcher/render-quickshell.sh'
                if renderer.exists():
                    for name in ['everforest', 'nord', 'catppuccin', 'tokyonight', 'everforest', 'nord']:
                        rendered = subprocess.check_output(['bash', str(renderer), str(kmdot / 'themes' / name / 'quickshell.conf')], text=True)
                        roles = dict(re.findall(r'property color (\w+): "(#[0-9a-fA-F]+)"', rendered))
                        pending = palette.with_suffix('.pending')
                        pending.write_text(rendered)
                        pending.replace(palette)
                        wait_for(lambda: rpc('system.info')['theme']['palette'] == roles, timeout=2)
                        def logo_matches():
                            svg = unquote(ipc('fixture', 'logo'))
                            return ('stroke="' + roles['primary'] + '"' in svg
                                    and 'fill="' + roles['primary_alt'] + '"' in svg)
                        wait_for(logo_matches, timeout=2)
                    print('  ok    complete kmDot palettes and two-color logo follow all four themes, including Everforest and Nord')
                palette.write_text('malformed theme')
                wait_for(lambda: rpc('system.info')['theme']['error'])
                assert rpc('system.info')['theme']['palette']['primary'] == roles['primary']
                print('  ok    atomic palette replacement and malformed-theme recovery')
                wait_for(lambda: any(r['id'] == 'app:kay-cast-fixture' for s in rpc('rootSearch.search', {'query': 'kay-cast fixture'}) for r in s['rows']))
                assert rpc('rootSearch.performAction', {'id': 'app:kay-cast-fixture', 'action': 'open'})['close']
                wait_for(marker.exists)
                assert marker.read_text().splitlines() == [str(root), 'literal argument']
                print('  ok    DesktopEntry execution preserves cwd, quoting and field codes')
                marker.unlink()
                wait_for(lambda: rpc('rootSearch.performAction', {'id': 'app:kay-cast-fixture-terminal', 'action': 'open'}))
                wait_for(terminal_marker.exists)
                wait_for(marker.exists)
                assert marker.read_text().splitlines() == [str(root), 'literal argument']
                print('  ok    Terminal=true apps launch inside the configured terminal')
                # Disable/restore through the same pushed-view API used by the UI.
                rpc('rootSearch.performAction', {'id': 'app:kay-cast-fixture', 'action': 'disable'})
                hidden = rpc('rootSearch.search', {'view': {'kind': 'disabled-commands'}})
                assert hidden[0]['rows'][0]['id'] == 'app:kay-cast-fixture'
                assert rpc('rootSearch.getActions', {'id': 'app:kay-cast-fixture'})[0]['id'] == 'enable'
                rpc('rootSearch.performAction', {'id': 'app:kay-cast-fixture', 'action': 'enable'})
                assert not rpc('rootSearch.search', {'view': {'kind': 'disabled-commands'}})[0]['rows']
                print('  ok    disabling and restoring a command through the UI APIs')
                assert ipc('kay-cast', 'isOpen') == 'false'
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
                log.seek(0)
                text = log.read()
                errors = [line for line in text.splitlines() if 'ERROR' in line or 'ReferenceError' in line or 'TypeError' in line]
                assert not errors, '\n'.join(errors)


if __name__ == '__main__':
    main()
