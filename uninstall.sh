#!/usr/bin/env bash
#
# Menu, starship TTY wiring, cache/state. Floating terminal clears FONT= and
# DRM reapply udev (sudo). Optional y/N pkg drop in the same floater.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"
cache="$HOME/.cache/omarchy/omatty"
config="$HOME/.config/omarchy/omatty"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omatty: %s\n' "$1"; }

launch_cleanup_floater() {
  local -a have=()
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null && have+=("$pkg")
  done
  local list="${have[*]}"
  local script="$state/uninstall-floater.sh"
  mkdir -p "$state"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\n' 'OmaTTY — uninstall'"
    printf '%s\n' "printf '%s\n' 'io.github.alxwolfenstein97.omatty'"
    printf '%s\n' "printf '%s\n' 'Style → TTY Fonts — console font mockups + FONT='"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\n' 'Will remove / reset (sudo):'"
    printf '%s\n' "printf '%s\n' '  • managed FONT= block in /etc/vconsole.conf'"
    printf '%s\n' "printf '%s\n' '  • /etc/udev/rules.d/99-omatty-reapply.rules'"
    printf '%s\n' "printf '%s\n' '  • /usr/local/lib/omatty/reapply'"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\n' ''"
    printf '%s\n' "if $(printf '%q ' "$here/bin/omatty" clear); then"
    printf '%s\n' "  printf 'vconsole FONT= cleared\n'"
    printf '%s\n' 'else'
    printf '%s\n' "  printf 'clear failed — FONT= may still be set\n' >&2"
    printf '%s\n' 'fi'
    printf '%s\n' "sudo bash -c 'rm -f /etc/udev/rules.d/99-omatty-reapply.rules; rm -f /usr/local/lib/omatty/reapply; rmdir /usr/local/lib/omatty 2>/dev/null || true; udevadm control --reload-rules >/dev/null 2>&1 || true' \\"
    printf '%s\n' "  && printf 'DRM reapply udev removed\n' \\"
    printf '%s\n' "  || printf 'udev teardown failed — remove 99-omatty-reapply.rules by hand\n' >&2"
    if ((${#have[@]})); then
      printf '%s\n' ''
      printf '%s\n' "printf '%s\n' 'Optional — packages OmaTTY may have pulled (only if nothing else needs them):'"
      for pkg in "${have[@]}"; do
        case $pkg in
          python-pillow) printf '%s\n' "printf '  • %s — %s\n' 'python-pillow' 'was used to draw TTY Fonts PSF carousel mockups'" ;;
          terminus-font) printf '%s\n' "printf '  • %s — %s\n' 'terminus-font' 'was used to Terminus faces shown in TTY Fonts'" ;;
          *) printf '%s\n' "printf '  • %s\n' $(printf %q "$pkg")" ;;
        esac
      done
      printf '%s\n' "printf '%s\n' '────────────────────────────────'"
      printf '%s\n' "read -r -p 'Drop ${list}? [y/N] ' a"
      printf '%s\n' 'case $a in'
      printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop ${list} ;;"
      printf '%s\n' "  *) printf 'skipped package drop\n' ;;"
      printf '%s\n' 'esac'
    fi
  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    note "opening floating terminal to reset FONT= / udev (+ optional pkg drop)"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    note "run: $here/bin/omatty clear"
    note "and remove /etc/udev/rules.d/99-omatty-reapply.rules if present"
    ((${#have[@]})) && note "optional: omarchy pkg drop $list"
  fi
}


export OMATTY_PLUGIN_DIR="$here"

mkdir -p "$state"
touch "$state/uninstalled"
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omatty" uninstall-menu || true
) 9>"$menu_lock"

rm -rf "$cache" "$config"
find "$state" -mindepth 1 ! -name uninstalled -delete 2>/dev/null || true
touch "$state/uninstalled"
note "cleared state/cache/config (tombstone left so quiet install cannot resurrect)"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

launch_cleanup_floater python-pillow terminus-font

note "done — no omatty menu or starship TTY profile left; FONT=/udev reset in floating terminal"
note "plugin files remain at $here until you omit/remove the plugin"
exit 0
