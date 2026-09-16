#!/usr/bin/env bash
#
# OmaTTY installer. Safe to re-run: rewrites menu + starship TTY wiring.
# Does NOT change /etc/vconsole.conf until you pick a font (sudo).
# Pulls python-pillow + terminus-font so every curated tile is a real mockup.
#
# Flags:
#   --quiet   less chatter (used by the shell service on startup)
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quiet=0
for arg in "$@"; do
  case $arg in
    --quiet) quiet=1 ;;
  esac
done

note() { (( quiet )) || printf 'omatty: %s\n' "$1"; }
warn() { printf 'omatty: %s\n' "$1" >&2; }

plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"

mkdir -p "$state"

chmod 755 "$here"/bin/* "$here/check.sh" \
  "$here/install.sh" "$here/uninstall.sh" 2>/dev/null || true

export OMATTY_PLUGIN_DIR="$here"

ensure_pkg() {
  local pkg=$1
  local why=$2
  if pacman -Q "$pkg" &>/dev/null; then
    return 0
  fi
  note "installing $pkg — $why"
  if command -v omarchy >/dev/null 2>&1; then
    omarchy pkg add "$pkg" || warn "could not install $pkg"
  else
    warn "install $pkg manually — $why"
  fi
}

# Pillow rasterises real PSF glyphs; terminus-font ships the ter-v* faces the
# carousel shows — install both before warming so every tile is a real mockup.
ensure_pkg python-pillow "draws Style → TTY Fonts mockups from real console fonts"
ensure_pkg terminus-font "Terminus console faces for Style → TTY Fonts"

"$here/bin/omatty" install-menu
# Shell service re-runs install --quiet on every boot — skip menu/shell
# rescans there (they stack across plugins and feel like a Hypr "zoom stroke").
if (( ! quiet )); then
  omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
  omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
fi

if (( ! quiet )); then
  (
    "$here/bin/omatty" preview >/dev/null 2>&1 || true
  ) &
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — Style > TTY Fonts, or '$here/bin/omatty switcher'"
note "applying prompts for sudo in a floating terminal"
exit 0
