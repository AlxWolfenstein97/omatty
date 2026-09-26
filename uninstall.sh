#!/usr/bin/env bash
#
# Menu, starship TTY wiring, cache/state. Clears FONT= + DRM udev in this TTY
# (sudo) + optional y/N pkg drop. --yes does both inline. Prompts stay in this TTY.
#
set -euo pipefail

assume_yes=0
for arg in "$@"; do
  case $arg in --yes|-y) assume_yes=1 ;; esac
done

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"
cache="$HOME/.cache/omarchy/omatty"
config="$HOME/.config/omarchy/omatty"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omatty: %s\n' "$1"; }

# Prefer sudo on a TTY (wipe-all / interactive). pkexec for GUI / non-TTY.
elevate() {
  if { [[ -t 0 ]] || [[ -t 1 ]]; } && command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  elif command -v pkexec >/dev/null 2>&1; then
    pkexec "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    return 127
  fi
}

try_pkg_drop() {
  # Best-effort: drop packages we may have pulled. If something else still
  # needs them, pacman refuses and we leave them — that is fine.
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || continue
    if command -v omarchy >/dev/null 2>&1 && omarchy pkg drop "$pkg"; then
      note "dropped $pkg"
    else
      note "kept $pkg (still required elsewhere or drop failed — fine)"
    fi
  done
}

ask_pkg_drop() {
  # Interactive — prompts in this terminal (this TTY).
  local -a have=()
  local pkg a req
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null && have+=("$pkg")
  done
  ((${#have[@]})) || return 0
  note "optional package drops — n / Enter keeps; pacman may refuse if still required"
  for pkg in "${have[@]}"; do
    case $pkg in
      python-pillow)
        note "python-pillow — Style carousel mockups (shared); MangoHud/goverlay/Lutris may need it"
        req=$(pacman -Qi python-pillow 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      python-numpy)
        note "python-numpy — OmaCursor Adwaita remaps"
        req=$(pacman -Qi python-numpy 2>/dev/null | awk -F': ' '/^Required By/{print $2}')
        note "  pacman Required By: ${req:-none}"
        ;;
      terminus-font)
        note "terminus-font — OmaTTY console faces"
        ;;
      adw-gtk-theme)
        note "adw-gtk-theme — GTK theme Chroma paints over"
        ;;
      *)
        note "package: $pkg"
        ;;
    esac
    read -r -p "Drop $pkg? [y/N] " a || a=
    case $a in
      [yY]|[yY][eE][sS]) try_pkg_drop "$pkg" ;;
      *) note "kept $pkg" ;;
    esac
  done
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

rm -rf "$cache"
# Do not rm -rf "$config" — users may keep files under ~/.config/omarchy/omatty.
# uninstall_starship_tty already removed/restored OmaTTY-owned starship files.
rmdir "$config" 2>/dev/null || true
find "$state" -mindepth 1 ! -name uninstalled -delete 2>/dev/null || true
touch "$state/uninstalled"
note "cleared state/cache; config dir left if it still has user files"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

udev_teardown() {
  note "removing DRM reapply udev (password once — sudo on TTY)"
  if elevate /bin/sh -c 'rm -f /etc/udev/rules.d/99-omatty-reapply.rules; rm -f /usr/local/lib/omatty/reapply; rmdir /usr/local/lib/omatty 2>/dev/null || true; udevadm control --reload-rules >/dev/null 2>&1 || true'; then
    note "DRM reapply udev removed"
  else
    note "udev teardown failed — remove 99-omatty-reapply.rules by hand"
  fi
}

if (( assume_yes )); then
  note "full wipe (--yes): resetting FONT= / DRM udev inline"
  udev_teardown
  if "$here/bin/omatty" clear; then
    note "vconsole FONT= cleared + live face → default8x16 + boot image refresh"
  else
    note "clear failed — try: sudo setfont default8x16 && sudo limine-mkinitcpio"
  fi
  note "full wipe (--yes): trying package drops (kept if still required elsewhere)"
  try_pkg_drop python-pillow terminus-font
else
  note "resetting FONT= / DRM udev (may prompt for sudo)"
  udev_teardown
  if "$here/bin/omatty" clear; then
    note "vconsole FONT= cleared + live face → default8x16 + boot image refresh"
  else
    note "clear failed — try: sudo setfont default8x16 && sudo limine-mkinitcpio"
  fi
  ask_pkg_drop python-pillow terminus-font
fi

note "done — no omatty menu or starship TTY profile left"
if (( assume_yes )); then
  note "full wipe (--yes): removing plugin $plugin_id"
  if command -v omarchy >/dev/null 2>&1; then
    # Leave the tree before Omarchy deletes it out from under us.
    cd "${HOME:-/}" || cd /
    omarchy plugin remove "$plugin_id" --yes \
      || note "plugin remove failed — try: omarchy plugin remove $plugin_id --yes"
  else
    note "omarchy CLI missing — delete by hand: $here"
  fi
else
  note "plugin files remain at $here until you omit/remove the plugin"
  note "  omarchy plugin remove $plugin_id"
fi

exit 0
