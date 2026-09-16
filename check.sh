#!/usr/bin/env bash
# Lightweight self-check for OmaTTY (no sudo, no live /etc/vconsole.conf writes).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0
pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'FAIL %s\n' "$1"; fail=1; }

[[ -x $here/bin/omatty ]] || bad "omatty not executable"
[[ -x $here/bin/omatty-switcher ]] || bad "omatty-switcher not executable"
[[ -f $here/manifest.json ]] || bad "manifest.json missing"
[[ -f $here/lib/omatty.py ]] || bad "lib/omatty.py missing"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/consolefonts" "$tmp/state" "$tmp/cache" \
  "$tmp/.config/omarchy/extensions" "$tmp/.config/omarchy/omatty"

# Copy a couple of real fonts into the fake consolefonts dir.
for stem in default8x16 Lat2-Terminus16 eurlatgr ter-v16n; do
  for ext in psfu.gz psf.gz psfu psf; do
    src="/usr/share/kbd/consolefonts/${stem}.${ext}"
    if [[ -f $src ]]; then
      cp -a "$src" "$tmp/consolefonts/"
      break
    fi
  done
done

cat >"$tmp/vconsole.conf" <<'EOF'
# Written by systemd-localed(8)
KEYMAP=us
XKBLAYOUT=us
XKBMODEL=pc105+inet
XKBOPTIONS=terminate:ctrl_alt_bksp
FONT=default8x16
EOF

cat >"$tmp/.bashrc" <<'EOF'
[[ -r /usr/share/omarchy/default/bash/env-bootstrap ]] && source /usr/share/omarchy/default/bash/env-bootstrap
[[ $- != *i* ]] && return
source "$OMARCHY_PATH/default/bash/rc"
# user stuff
alias ll='ls -la'
EOF

export OMATTY_HOME="$tmp"
export OMATTY_PLUGIN_DIR="$here"
export OMATTY_STATE_DIR="$tmp/state"
export OMATTY_CACHE_DIR="$tmp/cache"
export OMATTY_VCONSOLE="$tmp/vconsole.conf"
export OMATTY_CONSOLEFONTS="$tmp/consolefonts"
export OMATTY_CONFIG_DIR="$tmp/.config/omarchy/omatty"
export OMATTY_BASHRC="$tmp/.bashrc"
# Point HOME-derived menu path via OMATTY_HOME
export HOME="$tmp"

if "$here/bin/omatty" list | grep -q 'default8x16'; then
  pass "list shows default8x16"
else
  bad "list shows default8x16"
fi

if "$here/bin/omatty" list | grep -q 'ter-v16n'; then
  pass "list shows curated terminus"
else
  bad "list shows curated terminus"
fi

if "$here/bin/omatty" set Lat2-Terminus16 --quiet; then
  pass "set Lat2-Terminus16"
else
  bad "set Lat2-Terminus16"
fi

grep -q 'FONT=Lat2-Terminus16' "$tmp/vconsole.conf" && pass "FONT updated" || bad "FONT updated"
grep -q 'KEYMAP=us' "$tmp/vconsole.conf" && pass "KEYMAP kept" || bad "KEYMAP kept"
grep -q '# omatty:start' "$tmp/vconsole.conf" && pass "managed markers" || bad "managed markers"
grep -q 'XKBLAYOUT=us' "$tmp/vconsole.conf" && pass "XKB kept" || bad "XKB kept"

# Second apply replaces rather than stacking markers.
"$here/bin/omatty" set default8x16 --quiet
starts=$(grep -c '# omatty:start' "$tmp/vconsole.conf" || true)
[[ $starts -eq 1 ]] && pass "single managed block" || bad "single managed block"
grep -q 'FONT=default8x16' "$tmp/vconsole.conf" && pass "re-set FONT" || bad "re-set FONT"

[[ "$(cat "$tmp/state/current")" == "default8x16" ]] && pass "state current" || bad "state current"

if "$here/bin/omatty" preview Lat2-Terminus16 >/dev/null; then
  [[ -f $tmp/cache/previews/Lat2-Terminus16.png ]] && pass "preview png" || bad "preview png"
else
  bad "preview png"
fi

# Terminus tile renders real PSF glyphs when the face is present (install pulls
# terminus-font; check copies one face into the fixture when available).
if [[ -f $tmp/consolefonts/ter-v16n.psfu.gz || -f $tmp/consolefonts/ter-v16n.psf.gz \
   || -f $tmp/consolefonts/ter-v16n.psfu || -f $tmp/consolefonts/ter-v16n.psf ]]; then
  if "$here/bin/omatty" preview ter-v16n >/dev/null; then
    [[ -f $tmp/cache/previews/ter-v16n.png ]] && pass "terminus preview png" || bad "terminus preview png"
  else
    bad "terminus preview png"
  fi
else
  pass "terminus preview skipped (no ter-v16n in fixture)"
fi

# dry-run does not touch the file
cp "$tmp/vconsole.conf" "$tmp/vconsole.before"
"$here/bin/omatty" set Lat2-Terminus16 --dry-run >/dev/null
cmp -s "$tmp/vconsole.before" "$tmp/vconsole.conf" && pass "dry-run no write" || bad "dry-run no write"

# Starship TTY profile + bashrc snippet
"$here/bin/omatty" install-starship >/dev/null
[[ -f $tmp/.config/omarchy/omatty/starship-tty.toml ]] && pass "starship-tty.toml" || bad "starship-tty.toml"
grep -q 'success_symbol = "\[>\]' "$tmp/.config/omarchy/omatty/starship-tty.toml" && pass "ascii success glyph" || bad "ascii success glyph"
grep -q '# omatty:start' "$tmp/.bashrc" && pass "bashrc markers" || bad "bashrc markers"
grep -q 'STARSHIP_CONFIG' "$tmp/.bashrc" && pass "bashrc STARSHIP_CONFIG" || bad "bashrc STARSHIP_CONFIG"
# Snippet should sit before the omarchy rc source.
python3 - <<'PY' && pass "snippet before rc source" || bad "snippet before rc source"
from pathlib import Path
import os
text = Path(os.environ["OMATTY_BASHRC"]).read_text()
assert text.index("# omatty:start") < text.index('source "$OMARCHY_PATH/default/bash/rc"')
PY

# Menu install into extensions file
mkdir -p "$tmp/.config/omarchy/extensions"
printf '{\n}\n' >"$tmp/.config/omarchy/extensions/omarchy-menu.jsonc"
"$here/bin/omatty" install-menu >/dev/null
grep -q 'style.tty-font' "$tmp/.config/omarchy/extensions/omarchy-menu.jsonc" && pass "menu entry" || bad "menu entry"
grep -q 'TTY Fonts' "$tmp/.config/omarchy/extensions/omarchy-menu.jsonc" && pass "menu label" || bad "menu label"

"$here/bin/omatty" uninstall-menu >/dev/null
grep -q 'style.tty-font' "$tmp/.config/omarchy/extensions/omarchy-menu.jsonc" && bad "menu removed" || pass "menu removed"
grep -q '# omatty:start' "$tmp/.bashrc" && bad "bashrc cleaned" || pass "bashrc cleaned"

if command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin validate "$here" >/dev/null 2>&1; then
    pass "omarchy plugin validate"
  else
    bad "omarchy plugin validate"
  fi
fi

if (( fail )); then
  echo "omatty check: FAILED"
  exit 1
fi
echo "omatty check: all good"
exit 0
