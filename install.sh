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

# Style extenders all rewrite the same extensions file. Shell-service --quiet
# starts them in parallel — flock so we don't clobber each other's rows, then
# refresh the live menu only when the file actually changed (avoids stacked
# Hypr "zoom strokes" on every boot).
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"
menu_sha="$HOME/.local/state/omarchy/style-extenders/menu.sha"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omatty" install-menu
  if command -v omarchy-shell >/dev/null 2>&1 && [[ -f $menu_file ]]; then
    new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
    old_sha=$(cat "$menu_sha" 2>/dev/null || true)
    if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
      omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
      printf '%s\n' "$new_sha" >"$menu_sha"
    fi
  fi
) 9>"$menu_lock"
if (( ! quiet )); then
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
