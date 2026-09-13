#!/usr/bin/env bash
#
# Remove OmaTTY menu + bashrc starship snippet. Does not rewrite
# /etc/vconsole.conf — your last FONT= stays until you change it yourself.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"
cache="$HOME/.cache/omarchy/omatty"

note() { printf 'omatty: %s\n' "$1"; }

export OMATTY_PLUGIN_DIR="$here"
"$here/bin/omatty" uninstall-menu || true

rm -rf "$state" "$cache"
note "cleared state/cache"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — plugin files left at $here; vconsole FONT= left as last applied"
note "TTY starship.toml under ~/.config/omarchy/omatty/ left in place (harmless)"
exit 0
