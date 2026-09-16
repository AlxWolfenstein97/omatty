#!/usr/bin/env bash
#
# Full clean-slate: menu, bashrc starship snippet, starship-tty.toml, vconsole
# FONT= block, cache/state. Does not pacman -R terminus-font (shared system font).
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"
cache="$HOME/.cache/omarchy/omatty"
config="$HOME/.config/omarchy/omatty"

note() { printf 'omatty: %s\n' "$1"; }
warn() { printf 'omatty: %s\n' "$1" >&2; }

export OMATTY_PLUGIN_DIR="$here"
"$here/bin/omatty" uninstall-menu || true

# Clears FONT= markers (sudo) + removes starship wiring / config dir.
if ! "$here/bin/omatty" clear --quiet; then
  warn "could not clear vconsole FONT= (sudo?) — bashrc/starship still removed above"
  rm -rf "$config"
fi

rm -rf "$state" "$cache" "$config"
note "cleared state/cache/config"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no omatty menu, starship TTY profile, or managed FONT= left"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow terminus-font  # if nothing else needs them"
exit 0
