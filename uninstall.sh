#!/usr/bin/env bash
#
# Menu, starship TTY wiring, cache/state. Floating terminal clears FONT= and
# DRM reapply udev (sudo). Optional y/N pkg drop in the same floater.
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
    printf '%s\n' "printf '%s\n' '  • live setfont → default8x16 (so the TTY is not stuck fat)'"
    printf '%s\n' "printf '%s\n' '  • limine-mkinitcpio — drop baked FONT from initramfs (encrypted / LUKS)'"
    printf '%s\n' "printf '%s\n' '  • /etc/udev/rules.d/99-omatty-reapply.rules (if present)'"
    printf '%s\n' "printf '%s\n' '  • /usr/local/lib/omatty/reapply (if present)'"
    printf '%s\n' "printf '%s\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\n' 'Boot image rebuild can take a minute — leave this window open until Done.'"
    printf '%s\n' "printf '%s\n' ''"
    # Drop DRM udev first so a card-add cannot re-push the old face mid-clear.
    printf '%s\n' "sudo bash -c 'rm -f /etc/udev/rules.d/99-omatty-reapply.rules; rm -f /usr/local/lib/omatty/reapply; rmdir /usr/local/lib/omatty 2>/dev/null || true; udevadm control --reload-rules >/dev/null 2>&1 || true' \\"
    printf '%s\n' "  && printf 'DRM reapply udev removed\n' \\"
    printf '%s\n' "  || printf 'udev teardown failed — remove 99-omatty-reapply.rules by hand\n' >&2"
    printf '%s\n' "if $(printf '%q ' "$here/bin/omatty" clear); then"
    printf '%s\n' "  printf 'vconsole FONT= cleared + live face → default8x16 + boot image refresh\n'"
    printf '%s\n' 'else'
    printf '%s\n' "  printf 'clear failed — FONT= may still be set; try: sudo setfont default8x16 && sudo limine-mkinitcpio\n' >&2"
    printf '%s\n' 'fi'

# --- itemized optional drops (scan installed; one y/N each) ---
    if ((${#have[@]})); then
      printf '%s\n' ''
      printf '%s\n' "printf '%s\n' 'Optional package drops — scanned; only installed packages listed.'"
      printf '%s\n' "printf '%s\n' 'Answer n / Enter to keep. Close with Done when finished.'"
      for pkg in "${have[@]}"; do
        case $pkg in
          python-pillow)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'python-pillow'"
            printf '%s\n' "printf '%s\n' '  Used by Style carousel plugins (OmaBoot/OmaVT/OmaOBS/OmaHud/OmaCursor/OmaTTY).'"
            printf '%s\n' "printf '%s\n' '  MangoHud → python-matplotlib → pillow; goverlay → MangoHud. Lutris may too.'"
            printf '%s\n' "printf '%s\n' '  Removing breaks Style mockups until reinstalled; clear/uninstall still work without it.'"
            printf '%s\n' "printf '%s\n' '  If drop fails because those still need it — that is fine; keep Pillow.'"
            printf '%s\n' "req=\$(pacman -Qi python-pillow 2>/dev/null | awk -F': ' '/^Required By/{print \$2}')"
            printf '%s\n' "printf '  pacman Required By: %s\n' \"\${req:-none}\""
            printf '%s\n' "read -r -p 'Drop python-pillow? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS])"
            printf '%s\n' "    if omarchy pkg drop python-pillow; then printf 'dropped python-pillow\n'"
            printf '%s\n' "    else printf 'not dropped (other packages still need it — that is fine)\n'; fi"
            printf '%s\n' "    ;;"
            printf '%s\n' "  *) printf 'kept python-pillow\n' ;;"
            printf '%s\n' "esac"
            ;;
          terminus-font)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'terminus-font — Terminus console faces for TTY Fonts'"
            printf '%s\n' "read -r -p 'Drop terminus-font? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop terminus-font && printf 'dropped terminus-font\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept terminus-font\n' ;;"
            printf '%s\n' "esac"
            ;;
          python-numpy)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'python-numpy — fast Adwaita cursor remaps (OmaCursor)'"
            printf '%s\n' "req=\$(pacman -Qi python-numpy 2>/dev/null | awk -F': ' '/^Required By/{print \$2}')"
            printf '%s\n' "printf '  pacman Required By: %s\n' \"\${req:-none}\""
            printf '%s\n' "read -r -p 'Drop python-numpy? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS])"
            printf '%s\n' "    if omarchy pkg drop python-numpy; then printf 'dropped python-numpy\n'"
            printf '%s\n' "    else printf 'not dropped (still required elsewhere — fine)\n'; fi"
            printf '%s\n' "    ;;"
            printf '%s\n' "  *) printf 'kept python-numpy\n' ;;"
            printf '%s\n' "esac"
            ;;
          adw-gtk-theme)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf '%s\n' 'adw-gtk-theme — GTK theme Chroma paints over'"
            printf '%s\n' "read -r -p 'Drop adw-gtk-theme? [y/N] ' a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop adw-gtk-theme && printf 'dropped adw-gtk-theme\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept adw-gtk-theme\n' ;;"
            printf '%s\n' "esac"
            ;;
          *)
            printf '%s\n' "printf '%s\n' ''"
            printf '%s\n' "printf 'Package: %s\n' $(printf %q "$pkg")"
            printf '%s\n' "read -r -p \"Drop $pkg? [y/N] \" a"
            printf '%s\n' "case \$a in"
            printf '%s\n' "  [yY]|[yY][eE][sS]) omarchy pkg drop $pkg && printf 'dropped\n' || printf 'not dropped\n' ;;"
            printf '%s\n' "  *) printf 'kept\n' ;;"
            printf '%s\n' "esac"
            ;;
        esac
      done
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

if (( assume_yes )); then
  # inline FONT=/udev reset (no floater) + best-effort package drops
  note "full wipe (--yes): resetting FONT= / DRM udev inline"
  if command -v pkexec >/dev/null 2>&1; then
    pkexec /bin/sh -c 'rm -f /etc/udev/rules.d/99-omatty-reapply.rules; rm -f /usr/local/lib/omatty/reapply; rmdir /usr/local/lib/omatty 2>/dev/null || true; udevadm control --reload-rules >/dev/null 2>&1 || true'       && note "DRM reapply udev removed"       || note "udev teardown failed — remove 99-omatty-reapply.rules by hand"
  else
    sudo bash -c 'rm -f /etc/udev/rules.d/99-omatty-reapply.rules; rm -f /usr/local/lib/omatty/reapply; rmdir /usr/local/lib/omatty 2>/dev/null || true; udevadm control --reload-rules >/dev/null 2>&1 || true'       && note "DRM reapply udev removed"       || note "udev teardown failed — remove 99-omatty-reapply.rules by hand"
  fi
  if "$here/bin/omatty" clear; then
    note "vconsole FONT= cleared + live face → default8x16 + boot image refresh"
  else
    note "clear failed — try: sudo setfont default8x16 && sudo limine-mkinitcpio"
  fi
  note "full wipe (--yes): trying package drops (kept if still required elsewhere)"
  try_pkg_drop python-pillow terminus-font
else
  launch_cleanup_floater python-pillow terminus-font
fi

note "done — no omatty menu or starship TTY profile left; FONT=/udev reset in floating terminal"
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
