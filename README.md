# OmaTTY

**Omarchy themes your desktop. OmaTTY picks the console font behind
Ctrl+Alt+F3 — real PSF mockups in the Style menu, then `FONT=` in
`/etc/vconsole.conf`.**

![OmaTTY — Terminus 32 Bold mockup, hilariously cropped like a real TTY](preview.png)

Built first for **accessibility** — low vision, a mostly-blind bastard who still
wants a usable virtual console, HiDPI / 1440p+ glass where `default8x16` is
squint-land, and the kind of session where you drop into a single-GPU
passthrough VM curator or read kernel logs after the desktop has gone away.
Big fat Terminus clamps whip the TTY the way bitmap consoles used to.

Stock Omarchy never sets a console font. Recent
[archinstall](https://github.com/archlinux/archinstall) builds expose a
**Console font** locales menu that lists every `*.gz` under
`/usr/share/kbd/consolefonts` (default `default8x16`, auto-straps
`terminus-font` for `ter-*`). Dumping that whole list into Style would be
hundreds of codepage relics and slow mockups.

OmaTTY keeps a curated Terminus-first set, renders each with the **actual
bitmap glyphs**, and applies with sudo the same way Style → Unlock / Boot
Themes do.

## Goals (and honest limits)

These Style plugins extend Omarchy’s theme system **without requiring theme
authors — or you — to ship anything extra**. Fonts come from packages on the
machine (`kbd`, `terminus-font`); themes are not asked for font assets. The
broader “theme every surface that accepts colour data” story and stop-line
live in [Chroma](https://github.com/AlxWolfenstein97/chroma).

| Goal | What that means here |
|------|----------------------|
| Zero extra theme assets | No per-theme font previews. Glyphs come from installed PSF files. |
| Extreme compatibility | Works beside any Omarchy theme; pairs with [OmaVT](https://github.com/AlxWolfenstein97/omavt) for palette. |
| Closest-to-real mockups | Actual PSF bitmaps in a fake VT frame — still not a live `/dev/tty` capture. |
| Carousel-safe | Mockups are 1536×864 (menu-images thumbnail size) with ~8% side inset so the 768×475 tile crop does not shave the subject. |
| Curated, not exhaustive | archinstall lists every console font; Style keeps a Terminus-first set so the picker stays usable. |

### Why a Style picker for fonts?

Fonts are not theme colours — you are choosing a face/size, not syncing
`colors.toml`. The carousel still earns its keep the same way the theme
plugins do: mockups let you compare Terminus sizes across the curated set
faster than applying each one and hopping to Ctrl+Alt+F3. Pair with
[OmaVT](https://github.com/AlxWolfenstein97/omavt) when you want the TTY
*palette* to match the desktop too.

## What you get

- **Style → TTY Fonts** — labelled image picker (`omarchy-menu-images`).
- **Real PSF mockups** — a fake virtual-console frame painted with the font's
  own glyphs (not a lookalike TTF), so sizes read true before you apply.
- **Cropped like a TTY, not Hyprland** — fixed “glass”; bigger faces fit fewer
  columns/rows and **crop the content**. That is 1970s zoom (same framebuffer,
  hungrier cells), not compositor zoom that keeps layout and shrinks the
  viewport. Side effects on TUIs are real — fewer cells is fewer cells — and
  the mockup shows that on purpose.
- **Every `ter-v*` weight the package ships** — 12–32, normal **and** bold
  (no `ter-v12b` upstream). On-demand `terminus-font` install when you pick one.
- **Safe `vconsole.conf` patch** — only `FONT=` (inside `# omatty` markers).
  `KEYMAP` / XKB stay untouched.
- **TTY-safe Starship** — Omarchy’s desktop prompt glyphs will tofu on a
  bitmap console; OmaTTY ships a parallel profile for real `/dev/tty*` only.

## Starship on a real TTY

Omarchy’s `starship.toml` is lovely under Nerd Fonts in Alacritty / Kitty /
Ghostty. On a PSF console those same glyphs are missing codepoints — tofu
blocks instead of a prompt:

| Desktop (Omarchy default) | TTY profile |
|---------------------------|-------------|
| `❯` success / `✗` error   | `>` / `x`   |
| `…/` truncation           | `.../`      |
| `⇡` `⇣` `⇕` git ahead/behind/diverged | `^` `v` `<>` |
| Nerd icons (`` `` ``)  | `!` `=` `*` |

OmaTTY writes `~/.config/omarchy/omatty/starship-tty.toml` and a marked block
in `~/.bashrc` that sets `STARSHIP_CONFIG` **only** when `tty` reports
`/dev/tty*` (Ctrl+Alt+F3 style). Graphical terminals keep the fancy profile.
Your Wayland session is untouched; the clamp only hits the virtual console.

## Install

```sh
omarchy plugin add https://github.com/AlxWolfenstein97/omatty.git --enable
```

That clones into `~/.config/omarchy/plugins/io.github.alxwolfenstein97.omatty`.
Or from a checkout:

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.omatty/install.sh
omarchy plugin enable io.github.alxwolfenstein97.omatty
```

**Needs:** Omarchy’s image picker, Python 3 with Pillow (`python-pillow`),
`kbd` (`setfont`), and sudo for apply. `terminus-font` is pulled when you pick
a Terminus face.

## How it works

1. `bin/omatty-switcher` renders PNGs into `~/.cache/omarchy/omatty/previews/`,
   busts the image-selector thumbnail cache, then opens `omarchy-menu-images`.
2. On selection, Style launches a floating terminal running `omatty-set`
   (same privilege pattern as Unlock): may install `terminus-font`, patches
   `/etc/vconsole.conf`, restarts `systemd-vconsole-setup`, refreshes mockups.
3. Install also drops the Starship TTY profile + bashrc snippet.

CLI:

```sh
omatty list
omatty preview              # warm all mockups
omatty switcher             # picker → prints font id
omatty show ter-v32b        # print patched vconsole.conf
omatty set ter-v32b         # apply (sudo)
omatty set ter-v32b --dry-run
omatty current
```

Want even larger glyphs on a live console without changing `FONT=`? `setfont -d`
doubles whatever face is loaded (horizontal + vertical).

## Remove

```sh
~/.config/omarchy/plugins/io.github.alxwolfenstein97.omatty/uninstall.sh
omarchy plugin disable io.github.alxwolfenstein97.omatty
omarchy plugin remove io.github.alxwolfenstein97.omatty
```

Uninstall removes the menu row, bashrc snippet, and cache/state. It does
**not** rewrite `vconsole.conf` — your last `FONT=` stays until you change it.
The starship-tty.toml under `~/.config/omarchy/omatty/` is left in place
(harmless if unused).

## Why not every console font?

archinstall’s menu is exhaustive on purpose. For a Style carousel we only keep
faces you can tell apart at a glance: the Arch default, two useful kbd fonts,
and every Terminus Unicode size/weight the package ships. Missing `ter-*`
tiles still show a placeholder that says the package will be installed on
apply. ~20 mockups warm in a couple of seconds.

## Check

```sh
bash ~/.config/omarchy/plugins/io.github.alxwolfenstein97.omatty/check.sh
```

## Credits

- Sibling Style plugins: [OmaBoot](https://github.com/AlxWolfenstein97/omaboot),
  [OmaVT](https://github.com/AlxWolfenstein97/omavt),
  [OmaOBS](https://github.com/AlxWolfenstein97/omaobs).
- [archinstall](https://github.com/archlinux/archinstall) Console font menu /
  `terminus-font` auto-strap.
- [Omarchy](https://omarchy.org/) — Style menu image picker and floating-terminal
  sudo pattern.

## License

MIT — see [LICENSE](LICENSE).
