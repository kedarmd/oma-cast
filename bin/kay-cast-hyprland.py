#!/usr/bin/env python3
"""Reversible binding integration; does not edit the kmDot source checkout."""
import json
import os
from pathlib import Path
import subprocess
import sys

MARKER = '-- Managed by kay-cast\n'
REQUIRE = 'require("kay-cast") -- managed by kay-cast'
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'hypr'


def main():
    lua = CONFIG / 'hyprland.lua'
    conf = CONFIG / 'hyprland.conf'
    main_path = lua if lua.exists() else conf
    if not main_path.exists():
        if sys.argv[1] == 'uninstall':
            return
        raise ValueError(f'No Hyprland config in {CONFIG}')
    # Use the actual module directory when ~/.config/hypr is a symlink.
    main_path = main_path.resolve()
    module = main_path.parent / ('kay-cast.lua' if main_path.suffix == '.lua' else 'kay-cast.conf')
    line = REQUIRE if main_path.suffix == '.lua' else f'source = {module} # managed by kay-cast'
    marker = MARKER if main_path.suffix == '.lua' else '# Managed by kay-cast\n'
    content = main_path.read_text()
    if sys.argv[1] == 'uninstall':
        # Preserve edited bindings: remove only the exact generated content.
        expected = binding(main_path.suffix, marker)
        if module.exists() and module.read_text() == expected:
            main_path.write_text(''.join(s for s in content.splitlines(keepends=True) if s.strip() != line))
            module.unlink()
    else:
        if module.exists() and not module.read_text().startswith(marker):
            raise ValueError(f'Refusing to overwrite {module}')
        result = subprocess.run(['hyprctl', 'binds', '-j'], capture_output=True, text=True, check=True)
        matches = [b for b in json.loads(result.stdout)
                   if b.get('modmask') == 8 and str(b.get('key', '')).lower() == 'space']
        # Lua dispatchers are opaque numeric callbacks in `hyprctl binds`.
        # Recognize the one owned module only when its generated binding is present.
        own_lua = (main_path.suffix == '.lua' and module.exists()
                   and line in content.splitlines()
                   and binding('.lua', marker).strip() in module.read_text())
        for bind in matches:
            if bind.get('dispatcher') == 'global' and bind.get('arg') == 'kay-cast:toggle':
                continue
            if own_lua and len(matches) == 1 and bind.get('dispatcher') == '__lua':
                continue
            raise ValueError('Alt+Space is already bound; choose another key in kay-cast.lua')
        if not module.exists():
            module.write_text(binding(main_path.suffix, marker))
        if line not in content.splitlines():
            main_path.write_text(content.rstrip() + '\n\n' + line + '\n')
        print(f'Configured Alt+Space in {module}')
    subprocess.run(['hyprctl', 'reload'], check=True, stdout=subprocess.DEVNULL)


def binding(suffix, marker):
    if suffix == '.lua':
        return marker + 'hl.bind("ALT + SPACE", hl.dsp.global("kay-cast:toggle"))\n'
    return marker + 'bind = ALT, SPACE, global, kay-cast:toggle\n'


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as exc:
        sys.exit(f'kay-cast: {exc}')
