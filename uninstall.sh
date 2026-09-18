#!/usr/bin/env bash
#
# Clean-slate: menu, bashrc starship snippet, starship-tty.toml, cache/state.
# Best-effort clear of managed FONT= once (sudo). Same class as Style → Unlock
# themes: console font may stay until you pick stock again — we do not open a
# floating-terminal retry. Does not pacman -R terminus-font.
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="io.github.alxwolfenstein97.omatty"
state="$HOME/.local/state/omarchy/omatty"
cache="$HOME/.cache/omarchy/omatty"
config="$HOME/.config/omarchy/omatty"
menu_lock="$HOME/.local/state/omarchy/style-extenders/menu.lock"

note() { printf 'omatty: %s\n' "$1"; }

export OMATTY_PLUGIN_DIR="$here"
mkdir -p "$(dirname "$menu_lock")"
(
  flock 9
  "$here/bin/omatty" uninstall-menu || true
) 9>"$menu_lock"

# Best-effort once — uninstall-menu already stripped starship wiring; this also
# clears FONT=. No floating-terminal fight if sudo is unavailable.
if ! "$here/bin/omatty" clear --quiet 2>/dev/null; then
  note "vconsole FONT= left in place (sudo needed) — pick a stock console font or run: $here/bin/omatty clear"
fi

# Drop DRM reapply udev + helper (best-effort).
udev_cleanup=$(cat <<'EOF'
set -euo pipefail
rm -f /etc/udev/rules.d/99-omatty-reapply.rules
rm -f /usr/local/lib/omatty/reapply
rmdir /usr/local/lib/omatty 2>/dev/null || true
udevadm control --reload-rules >/dev/null 2>&1 || true
EOF
)
if sudo -n bash -c "$udev_cleanup" >/dev/null 2>&1 \
    || sudo bash -c "$udev_cleanup" >/dev/null 2>&1; then
  note "removed DRM reapply udev"
else
  note "DRM reapply udev left in place (sudo needed) — remove /etc/udev/rules.d/99-omatty-reapply.rules by hand"
fi

rm -rf "$state" "$cache" "$config"
mkdir -p "$state"
touch "$state/uninstalled"
note "cleared state/cache/config (tombstone left so quiet install cannot resurrect)"

omarchy-shell -q omarchy.menu refresh >/dev/null 2>&1 || true
omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 || true

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$plugin_id" >/dev/null 2>&1 || true
fi

note "done — no omatty menu or starship TTY profile left; FONT= stays until cleared"
note "plugin files remain at $here until you omit/remove the plugin"
note "optional: omarchy pkg drop python-pillow terminus-font  # if nothing else needs them"
exit 0
