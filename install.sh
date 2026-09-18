#!/usr/bin/env bash
#
# OmaTTY installer. Safe to re-run: menu written once (quiet skips rewrite when
# // omatty:start markers already exist); starship TTY wiring on interactive
# install-menu. Does NOT change /etc/vconsole.conf until you pick a font (sudo).
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

# Tombstone from uninstall: Service --quiet must not resurrect wiring.
if [[ -f $state/uninstalled ]]; then
  if (( quiet )); then
    exit 0
  fi
  rm -f "$state/uninstalled"
fi

mkdir -p "$state"

chmod 755 "$here"/bin/* "$here/check.sh" \
  "$here/install.sh" "$here/uninstall.sh" 2>/dev/null || true

export OMATTY_PLUGIN_DIR="$here"

# After GPU passthrough the DRM card comes back and fbcon often resets to a
# tiny default *before* SDDM. systemd-vconsole-setup frequently skips busy
# VTs; direct setfont still works. Install a udev rule that re-pushes FONT=.
install_drm_reapply() {
  local helper_src="$here/bin/omatty-reapply"
  local helper_dst="/usr/local/lib/omatty/reapply"
  local rule_src="$here/udev/99-omatty-reapply.rules"
  local rule_dst="/etc/udev/rules.d/99-omatty-reapply.rules"
  [[ -f $helper_src && -f $rule_src ]] || return 0

  if [[ -x $helper_dst ]] && cmp -s "$helper_src" "$helper_dst" 2>/dev/null \
      && [[ -f $rule_dst ]] && cmp -s "$rule_src" "$rule_dst" 2>/dev/null; then
    return 0
  fi

  local script
  script=$(cat <<EOF
set -euo pipefail
install -d -m 755 /usr/local/lib/omatty
install -m 755 $(printf %q "$helper_src") $(printf %q "$helper_dst")
install -m 644 $(printf %q "$rule_src") $(printf %q "$rule_dst")
udevadm control --reload-rules >/dev/null 2>&1 || true
EOF
)

  # Header + sudo — the system paths need root. Quiet Service used to launch
  # the install body *without* sudo, which failed with "cannot create directory
  # /usr/local/lib/omatty".
  local floater
  floater=$(cat <<EOF
set -uo pipefail
printf '%s\n' 'OmaTTY — DRM font reapply'
printf '%s\n' 'io.github.alxwolfenstein97.omatty'
printf '%s\n' 'Style → TTY Fonts — re-push FONT= after GPU passthrough'
printf '%s\n' '────────────────────────────────'
printf '%s\n' 'Needs to install (sudo):'
printf '%s\n' '  • /usr/local/lib/omatty/reapply — setfont helper for DRM card-add'
printf '%s\n' '  • /etc/udev/rules.d/99-omatty-reapply.rules — fires helper on GPU return'
printf '%s\n' '────────────────────────────────'
printf '%s\n' ''
sudo bash -c $(printf %q "$script")
EOF
)

  if (( quiet )); then
    if sudo -n bash -c "$script" >/dev/null 2>&1; then
      note "DRM reapply udev armed (passwordless sudo)"
      return 0
    fi
    # One floating prompt once — same pattern as package pulls.
    if [[ -f $state/udev-prompted ]]; then
      warn "OmaTTY still missing DRM reapply udev (Style → TTY Fonts after GPU passthrough) — run install.sh interactively or: sudo bash -c $(printf %q "$script")"
      return 1
    fi
    mkdir -p "$state"
    touch "$state/udev-prompted"
    local udev_script="$state/udev-floater.sh"
    {
      printf '%s\n' '#!/usr/bin/env bash'
      printf '%s\n' "$floater"
    } >"$udev_script"
    chmod 755 "$udev_script"
    if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
      warn "OmaTTY needs DRM reapply udev (Style → TTY Fonts after GPU passthrough) — opening floating terminal"
      omarchy-launch-floating-terminal-with-presentation \
        "bash $(printf %q "$udev_script")" >/dev/null 2>&1 &
    else
      warn "run (sudo): install DRM reapply — $here/install.sh"
    fi
    return 1
  fi

  printf '%s\n' 'OmaTTY — DRM font reapply'
  printf '%s\n' 'io.github.alxwolfenstein97.omatty'
  printf '%s\n' 'Style → TTY Fonts — re-push FONT= after GPU passthrough'
  printf '%s\n' '────────────────────────────────'
  printf '%s\n' 'Needs to install (sudo):'
  printf '%s\n' '  • /usr/local/lib/omatty/reapply — setfont helper for DRM card-add'
  printf '%s\n' '  • /etc/udev/rules.d/99-omatty-reapply.rules — fires helper on GPU return'
  printf '%s\n' '────────────────────────────────'
  printf '%s\n' ""
  if sudo bash -c "$script"; then
    rm -f "$state/udev-prompted"
    note "DRM card-add → setfont reapply armed (/etc/udev/rules.d/99-omatty-reapply.rules)"
    return 0
  fi
  warn "OmaTTY could not install DRM reapply udev (sudo denied) — Style → TTY Fonts still works live"
  return 1
}

install_drm_reapply || true

# Packages need sudo. Interactive: header in this TTY. Service --quiet:
# one headed floating terminal once (pkgs-prompted). Headers name this plugin,
# what it does, and why each package is missing.
pull_pkgs() {
  local -a missing=()
  local pkg
  for pkg in "$@"; do
    pacman -Q "$pkg" &>/dev/null || missing+=("$pkg")
  done
  if ((${#missing[@]} == 0)); then
    rm -f "$state/pkgs-prompted"
    return 0
  fi

  if ! command -v omarchy >/dev/null 2>&1; then
    warn "OmaTTY needs ${missing[*]} for: Style → TTY Fonts — console font mockups + FONT= — install manually: pacman -S ${missing[*]}"
    return 1
  fi

  note "OmaTTY needs ${missing[*]} — Style → TTY Fonts — console font mockups + FONT="
  if (( ! quiet )) && [[ -t 0 || -t 1 ]]; then
    printf '%s\n' "OmaTTY"
    printf '%s\n' "io.github.alxwolfenstein97.omatty"
    printf '%s\n' "Style → TTY Fonts — console font mockups + FONT="
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' "Needs to install (sudo / pacman):"
    for pkg in "${missing[@]}"; do
      case $pkg in
        python-pillow) printf '  • %s — %s\n' "$pkg" 'draw TTY Fonts PSF carousel mockups' ;;
        terminus-font) printf '  • %s — %s\n' "$pkg" 'Terminus faces shown in TTY Fonts' ;;
        *) printf '  • %s\n' "$pkg" ;;
      esac
    done
    printf '%s\n' "────────────────────────────────"
    printf '%s\n' ""
    if omarchy pkg add "${missing[@]}"; then
      rm -f "$state/pkgs-prompted"
      return 0
    fi
    warn "OmaTTY could not install: ${missing[*]}"
    return 1
  fi

  if [[ -f $state/pkgs-prompted ]]; then
    warn "OmaTTY still missing ${missing[*]} (Style → TTY Fonts — console font mockups + FONT=) — run: omarchy pkg add ${missing[*]}"
    return 1
  fi
  mkdir -p "$state"
  touch "$state/pkgs-prompted"
  local script="$state/install-floater.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -uo pipefail'
    printf '%s\n' "printf '%s\\n' 'OmaTTY'"
    printf '%s\n' "printf '%s\\n' 'io.github.alxwolfenstein97.omatty'"
    printf '%s\n' "printf '%s\\n' 'Style → TTY Fonts — console font mockups + FONT='"
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' 'Needs to install (sudo / pacman):'"
    for pkg in "${missing[@]}"; do
      case $pkg in
        python-pillow) printf '%s\n' "printf '  • %s — %s\n' 'python-pillow' 'draw TTY Fonts PSF carousel mockups'" ;;
        terminus-font) printf '%s\n' "printf '  • %s — %s\n' 'terminus-font' 'Terminus faces shown in TTY Fonts'" ;;
        *) printf '%s\n' "printf '  • %s\n' $(printf %q "$pkg")" ;;
      esac
    done
    printf '%s\n' "printf '%s\\n' '────────────────────────────────'"
    printf '%s\n' "printf '%s\\n' ''"
    printf '%s\n' "omarchy pkg add ${missing[*]}"
    if [[ -n ${PULL_PKGS_AFTER:-} ]]; then
      printf '%s\n' "$PULL_PKGS_AFTER"
    fi
  } >"$script"
  chmod 755 "$script"
  if command -v omarchy-launch-floating-terminal-with-presentation >/dev/null 2>&1; then
    warn "OmaTTY missing ${missing[*]} (Style → TTY Fonts — console font mockups + FONT=) — opening floating terminal"
    omarchy-launch-floating-terminal-with-presentation "bash $(printf %q "$script")" >/dev/null 2>&1 &
  else
    warn "OmaTTY: run omarchy pkg add ${missing[*]}"
  fi
  return 1
}



# Pillow rasterises real PSF glyphs; terminus-font ships the ter-v* faces the
# carousel shows — install both before warming so every tile is a real mockup.
# Interactive: ask in this TTY. Quiet/Service: one floating terminal once
# (pkgs-prompted), never again on later boots if dismissed.
pull_pkgs python-pillow terminus-font || true

# Style extenders share omarchy-menu.jsonc — flock so parallel Services don't
# clobber each other. Interactive: always install-menu. Quiet: only if our
# markers are absent (no rewrite/normalize every boot). Refresh only when written.
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"
menu_sha="$HOME/.local/state/omarchy/style-extenders/menu.sha"
menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  # Scrub Style rows for siblings removed via plugin remove (no uninstall.sh).
  scrubbed=0
  scrub_out=$(python3 - <<'ORPHANSCRUB' || true
from pathlib import Path
import re
menu = Path.home() / ".config/omarchy/extensions/omarchy-menu.jsonc"
if not menu.is_file():
    raise SystemExit(0)
plugins = Path.home() / ".config/omarchy/plugins"
pairs = [
    ("omacursor", "io.github.alxwolfenstein97.omacursor"),
    ("omaobs", "io.github.alxwolfenstein97.omaobs"),
    ("omaboot", "io.github.alxwolfenstein97.omaboot"),
    ("omavt", "io.github.alxwolfenstein97.omavt"),
    ("omatty", "io.github.alxwolfenstein97.omatty"),
    ("omahud", "io.github.alxwolfenstein97.omahud"),
]
text = menu.read_text(encoding="utf-8")
orig = text
for marker, pid in pairs:
    if (plugins / pid).is_dir():
        continue
    start, end = f"// {marker}:start", f"// {marker}:end"
    if start not in text:
        continue
    text = re.sub(re.escape(start) + r".*?" + re.escape(end) + r"\n?", "", text, flags=re.S)
if text != orig:
    menu.write_text(text, encoding="utf-8")
    print("scrubbed-orphan-style-menus")
ORPHANSCRUB
  )
  [[ $scrub_out == *scrubbed-orphan-style-menus* ]] && scrubbed=1
  write_menu=1
  if (( quiet )) && [[ -f $menu_file ]] && grep -qF '// omatty:start' "$menu_file"; then
    write_menu=0
  fi
  if (( write_menu )); then
    "$here/bin/omatty" install-menu
    if [[ -f $menu_file ]]; then
      new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
      old_sha=$(cat "$menu_sha" 2>/dev/null || true)
      if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
        printf '%s\n' "$new_sha" >"$menu_sha"
        if command -v omarchy-shell >/dev/null 2>&1; then
          stamp="$HOME/.local/state/omarchy/style-extenders/menu.refresh"
          do_refresh=1
          if (( quiet )) && [[ -f $stamp ]]; then
            now=$(date +%s)
            then=$(stat -c %Y "$stamp" 2>/dev/null || echo 0)
            if (( now - then < 3 )); then
              do_refresh=0
            fi
          fi
          if (( do_refresh )); then
            touch "$stamp"
            omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
            if (( ! quiet )); then
              omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true
            fi
          fi
        fi
      fi
    fi
  fi
  if (( scrubbed && ! write_menu )); then
    if [[ -f $menu_file ]]; then
      new_sha=$(sha256sum "$menu_file" 2>/dev/null | awk '{print $1}')
      old_sha=$(cat "$menu_sha" 2>/dev/null || true)
      if [[ -n $new_sha && $new_sha != "$old_sha" ]]; then
        printf '%s\n' "$new_sha" >"$menu_sha"
      fi
    fi
    if command -v omarchy-shell >/dev/null 2>&1; then
      stamp="$HOME/.local/state/omarchy/style-extenders/menu.refresh"
      touch "$stamp"
      omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
    fi
  fi
) 9>"$menu_lock"
if (( ! quiet )); then
  note "Style → TTY Fonts is live; if the row is missing, run: omarchy-shell shell rescanPlugins"
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
