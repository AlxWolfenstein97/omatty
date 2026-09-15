#!/usr/bin/env python3
"""OmaTTY — Style-menu console (TTY) fonts with real bitmap mockups.

Curates the fonts people actually pick on Arch (stock default + Terminus
sizes, matching what recent archinstall Console-font menus surface via
terminus-font), renders each as a fake virtual-console mockup from the
real PSF glyphs, and writes FONT= into /etc/vconsole.conf (sudo).

Also ships a TTY-safe starship profile so Omarchy's fancy prompt glyphs
do not tofu on a bitmap console.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

PLUGIN_ID = "io.github.alxwolfenstein97.omatty"
MENU_START = "  // omatty:start"
MENU_END = "  // omatty:end"
BASHRC_START = "# omatty:start"
BASHRC_END = "# omatty:end"
VCONSOLE_START = "# omatty:start"
VCONSOLE_END = "# omatty:end"

PSF1_MAGIC = b"\x36\x04"
PSF2_MAGIC = 0x864AB572
PSF2_HAS_UNICODE = 0x01
UNICODE_SEPARATOR = 0xFFFF
UNICODE_STARTSEQ = 0xFFFE

# Curated set — archinstall lists every *.gz under consolefonts; that is
# hundreds of codepage relics. We keep the stock default, kbd's Terminus,
# one broad kbd Unicode face, and every ter-v* size terminus-font ships
# (normal + bold). No ter-v12b in the package — that is the only gap.
# Bold faces matter for low vision / HiDPI TTYs; setfont -d can still
# double any of these further on the console.
CURATED: list[dict[str, str]] = [
    {
        "id": "default8x16",
        "label": "Default 8x16",
        "file": "default8x16",
        "blurb": "Arch / archinstall default",
    },
    {
        "id": "Lat2-Terminus16",
        "label": "Terminus 16 (kbd)",
        "file": "Lat2-Terminus16",
        "blurb": "Shipped with kbd — Latin-2",
    },
    {
        "id": "eurlatgr",
        "label": "EurLatGr",
        "file": "eurlatgr",
        "blurb": "Euro + Latin + Greek (kbd)",
    },
    {
        "id": "ter-v12n",
        "label": "Terminus 12",
        "file": "ter-v12n",
        "blurb": "terminus-font · compact (no bold in package)",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v14n",
        "label": "Terminus 14",
        "file": "ter-v14n",
        "blurb": "terminus-font",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v14b",
        "label": "Terminus 14 Bold",
        "file": "ter-v14b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v16n",
        "label": "Terminus 16",
        "file": "ter-v16n",
        "blurb": "terminus-font · classic",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v16b",
        "label": "Terminus 16 Bold",
        "file": "ter-v16b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v18n",
        "label": "Terminus 18",
        "file": "ter-v18n",
        "blurb": "terminus-font",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v18b",
        "label": "Terminus 18 Bold",
        "file": "ter-v18b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v20n",
        "label": "Terminus 20",
        "file": "ter-v20n",
        "blurb": "terminus-font",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v20b",
        "label": "Terminus 20 Bold",
        "file": "ter-v20b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v22n",
        "label": "Terminus 22",
        "file": "ter-v22n",
        "blurb": "terminus-font",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v22b",
        "label": "Terminus 22 Bold",
        "file": "ter-v22b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v24n",
        "label": "Terminus 24",
        "file": "ter-v24n",
        "blurb": "terminus-font · roomy",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v24b",
        "label": "Terminus 24 Bold",
        "file": "ter-v24b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v28n",
        "label": "Terminus 28",
        "file": "ter-v28n",
        "blurb": "terminus-font",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v28b",
        "label": "Terminus 28 Bold",
        "file": "ter-v28b",
        "blurb": "terminus-font · bold",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v32n",
        "label": "Terminus 32",
        "file": "ter-v32n",
        "blurb": "terminus-font · HiDPI TTY",
        "pkg": "terminus-font",
    },
    {
        "id": "ter-v32b",
        "label": "Terminus 32 Bold",
        "file": "ter-v32b",
        "blurb": "terminus-font · HiDPI bold",
        "pkg": "terminus-font",
    },
]

CURATED_BY_ID = {item["id"]: item for item in CURATED}


def home() -> Path:
    return Path(os.environ.get("OMATTY_HOME", Path.home())).expanduser()


def plugin_dir() -> Path:
    override = os.environ.get("OMATTY_PLUGIN_DIR")
    if override:
        return Path(override).expanduser()
    return Path(__file__).resolve().parent.parent


def consolefonts_dir() -> Path:
    override = os.environ.get("OMATTY_CONSOLEFONTS")
    if override:
        return Path(override).expanduser()
    return Path("/usr/share/kbd/consolefonts")


def vconsole_path() -> Path:
    override = os.environ.get("OMATTY_VCONSOLE")
    if override:
        return Path(override).expanduser()
    return Path("/etc/vconsole.conf")


def paths() -> dict[str, Path]:
    h = home()
    return {
        "state": Path(os.environ.get("OMATTY_STATE_DIR", h / ".local/state/omarchy/omatty")),
        "cache": Path(os.environ.get("OMATTY_CACHE_DIR", h / ".cache/omarchy/omatty")),
        "menu": h / ".config/omarchy/extensions/omarchy-menu.jsonc",
        "config": Path(os.environ.get("OMATTY_CONFIG_DIR", h / ".config/omarchy/omatty")),
        "bashrc": Path(os.environ.get("OMATTY_BASHRC", h / ".bashrc")),
        "vconsole": vconsole_path(),
        "consolefonts": consolefonts_dir(),
        "share": plugin_dir() / "share",
    }


def note(msg: str) -> None:
    print(f"omatty: {msg}", file=sys.stderr)


def atomic_write(path: Path, content: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        if isinstance(content, bytes):
            with os.fdopen(fd, "wb") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        else:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
                handle.flush()
                os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def remove_marked(content: str, start: str, end: str) -> str:
    pattern = re.compile(re.escape(start) + r".*?" + re.escape(end) + r"\n?", re.S)
    return pattern.sub("", content)


# ---------------------------------------------------------------------------
# PSF loader — render the real console glyphs into mockups
# ---------------------------------------------------------------------------


@dataclass
class ConsoleFont:
    name: str
    width: int
    height: int
    glyphs: list[bytes]
    unicode_map: dict[int, int]  # codepoint → glyph index

    def glyph_for(self, ch: str) -> bytes | None:
        if not ch:
            return None
        cp = ord(ch)
        index = self.unicode_map.get(cp)
        if index is None and cp < len(self.glyphs):
            index = cp
        if index is None or index >= len(self.glyphs):
            return None
        return self.glyphs[index]


def _read_font_bytes(path: Path) -> bytes:
    raw = path.read_bytes()
    if path.suffix == ".gz" or raw[:2] == b"\x1f\x8b":
        return gzip.decompress(raw)
    return raw


def resolve_font_file(file_stem: str) -> Path | None:
    root = consolefonts_dir()
    candidates = [
        root / f"{file_stem}.psfu.gz",
        root / f"{file_stem}.psf.gz",
        root / f"{file_stem}.psfu",
        root / f"{file_stem}.psf",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def _parse_psf1_unicode(data: bytes, offset: int, length: int) -> dict[int, int]:
    mapping: dict[int, int] = {}
    pos = offset
    for glyph in range(length):
        while pos + 1 < len(data):
            value = data[pos] | (data[pos + 1] << 8)
            pos += 2
            if value == UNICODE_SEPARATOR:
                break
            if value == UNICODE_STARTSEQ:
                # Skip combining sequence until separator.
                while pos + 1 < len(data):
                    seq = data[pos] | (data[pos + 1] << 8)
                    pos += 2
                    if seq == UNICODE_SEPARATOR:
                        break
                break
            mapping.setdefault(value, glyph)
    return mapping


def _parse_psf2_unicode(data: bytes, offset: int, length: int) -> dict[int, int]:
    mapping: dict[int, int] = {}
    pos = offset
    for glyph in range(length):
        while pos < len(data):
            # PSF2 stores UTF-8 code points terminated by 0xFF.
            if data[pos] == 0xFF:
                pos += 1
                break
            if data[pos] == 0xFE:
                # Start of a sequence — skip until 0xFF.
                pos += 1
                while pos < len(data) and data[pos] != 0xFF:
                    pos += 1
                if pos < len(data) and data[pos] == 0xFF:
                    pos += 1
                break
            # Decode one UTF-8 codepoint.
            lead = data[pos]
            if lead < 0x80:
                size = 1
            elif lead < 0xE0:
                size = 2
            elif lead < 0xF0:
                size = 3
            else:
                size = 4
            chunk = data[pos : pos + size]
            pos += size
            try:
                cp = chunk.decode("utf-8")
                if cp:
                    mapping.setdefault(ord(cp[0]), glyph)
            except UnicodeDecodeError:
                continue
    return mapping


def load_console_font(file_stem: str) -> ConsoleFont:
    path = resolve_font_file(file_stem)
    if path is None:
        raise FileNotFoundError(f"console font not installed: {file_stem}")

    data = _read_font_bytes(path)

    if len(data) >= 4 and struct.unpack_from("<I", data)[0] == PSF2_MAGIC:
        magic, version, headersize, flags, length, charsize, height, width = struct.unpack_from(
            "<8I", data
        )
        del magic, version
        glyphs = [
            data[headersize + i * charsize : headersize + (i + 1) * charsize]
            for i in range(length)
        ]
        unicode_map: dict[int, int] = {}
        if flags & PSF2_HAS_UNICODE:
            unicode_map = _parse_psf2_unicode(data, headersize + length * charsize, length)
        return ConsoleFont(path.stem.split(".")[0], width, height, glyphs, unicode_map)

    if data[:2] == PSF1_MAGIC:
        mode = data[2]
        charsize = data[3]
        length = 512 if mode & 0x01 else 256
        has_unicode = bool(mode & 0x02)
        headersize = 4
        height = charsize
        width = 8
        glyphs = [
            data[headersize + i * charsize : headersize + (i + 1) * charsize]
            for i in range(length)
        ]
        unicode_map = {}
        if has_unicode:
            unicode_map = _parse_psf1_unicode(data, headersize + length * charsize, length)
        return ConsoleFont(path.stem.split(".")[0], width, height, glyphs, unicode_map)

    raise ValueError(f"unrecognised PSF font: {path}")


def blit_glyph(
    img: Image.Image,
    font: ConsoleFont,
    ch: str,
    x: int,
    y: int,
    fg: tuple[int, int, int],
    bg: tuple[int, int, int] | None,
    scale: int,
) -> int:
    glyph = font.glyph_for(ch)
    if glyph is None:
        # Missing glyph — draw a small tofu block so gaps are obvious in the mockup.
        w, h = font.width * scale, font.height * scale
        draw = ImageDraw.Draw(img)
        if bg is not None:
            draw.rectangle((x, y, x + w - 1, y + h - 1), fill=bg)
        draw.rectangle((x + scale, y + scale, x + w - scale - 1, y + h - scale - 1), outline=fg)
        return font.width * scale

    row_bytes = (font.width + 7) // 8
    pixels = img.load()
    assert pixels is not None
    for row in range(font.height):
        row_data = glyph[row * row_bytes : (row + 1) * row_bytes]
        for col in range(font.width):
            byte = row_data[col // 8]
            bit = 0x80 >> (col % 8)
            on = bool(byte & bit)
            color = fg if on else bg
            if color is None:
                continue
            px = x + col * scale
            py = y + row * scale
            for dy in range(scale):
                for dx in range(scale):
                    pixels[px + dx, py + dy] = color
    return font.width * scale


def draw_text(
    img: Image.Image,
    font: ConsoleFont,
    text: str,
    x: int,
    y: int,
    fg: tuple[int, int, int],
    bg: tuple[int, int, int] | None,
    scale: int,
) -> None:
    cursor = x
    for ch in text:
        cursor += blit_glyph(img, font, ch, cursor, y, fg, bg, scale)


# ---------------------------------------------------------------------------
# Discovery / state
# ---------------------------------------------------------------------------


def curated_available() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for item in CURATED:
        present = resolve_font_file(item["file"]) is not None
        out.append({**item, "available": present})
    return out


def current_font_id() -> str | None:
    state = paths()["state"] / "current"
    if state.is_file():
        value = state.read_text(encoding="utf-8").strip()
        if value:
            return value
    # Fall back to live vconsole FONT=
    try:
        conf = read_vconsole()
    except Exception:
        return None
    match = re.search(r"^FONT=(.*)$", conf, re.M)
    if not match:
        return None
    raw = match.group(1).strip().strip('"').strip("'")
    # FONT may be a path or a stem; normalise to curated id when possible.
    stem = Path(raw).name
    stem = re.sub(r"\.(psfu?|gz)$", "", stem)
    stem = re.sub(r"\.(psfu?)$", "", stem)
    if stem in CURATED_BY_ID:
        return stem
    return stem or None


def pretty_label(font_id: str) -> str:
    item = CURATED_BY_ID.get(font_id)
    return item["label"] if item else font_id


# ---------------------------------------------------------------------------
# Mockups
# ---------------------------------------------------------------------------


def theme_colors() -> dict[str, str]:
    """Pull a rough palette from the active Omarchy theme when present."""
    name_path = home() / ".local/state/omarchy/current/theme.name"
    slug = ""
    if name_path.is_file():
        slug = name_path.read_text(encoding="utf-8").strip().lower().replace(" ", "-")
    for root in (home() / ".config/omarchy/themes", Path("/usr/share/omarchy/themes")):
        colors = root / slug / "colors.toml" if slug else None
        if colors and colors.is_file():
            data: dict[str, str] = {}
            for line in colors.read_text(encoding="utf-8").splitlines():
                stripped = line.strip()
                if not stripped or stripped.startswith("#") or "=" not in stripped:
                    continue
                key, _, value = stripped.partition("=")
                data[key.strip()] = value.strip().strip('"').strip("'")
            return {
                "bg": data.get("background", "#1a1b26"),
                "fg": data.get("bright_foreground", data.get("foreground", "#c0caf5")),
                "accent": data.get("accent", data.get("cyan", "#7dcfff")),
                "muted": data.get("muted", "#565f89"),
                "green": data.get("green", "#9ece6a"),
                "cyan": data.get("cyan", data.get("accent", "#7dcfff")),
                "red": data.get("red", "#f7768e"),
            }
    return {
        "bg": "#1a1b26",
        "fg": "#c0caf5",
        "accent": "#7dcfff",
        "muted": "#565f89",
        "green": "#9ece6a",
        "cyan": "#7dcfff",
        "red": "#f7768e",
    }


def _hex_rgb(value: str) -> tuple[int, int, int]:
    h = value.lstrip("#")
    if len(h) != 6:
        h = "1a1b26"
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def try_ui_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
        "/usr/share/fonts/TTF/DejaVuSans.ttf",
        "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    ]
    for path in candidates:
        if Path(path).is_file():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def preview_path(font_id: str) -> Path:
    return paths()["cache"] / "previews" / f"{font_id}.png"


def save_png_atomic(img: Image.Image, dest: Path) -> None:
    """Write PNG via rename so the preview directory mtime updates.

    omarchy-menu-images keys its fast rows-cache on the *directory* mtime.
    Pillow's in-place overwrite does not touch that, so after terminus-font
    lands the carousel keeps serving stale "Not installed" thumbnails across
    reboots. A replace() updates the directory entry and busts that cache.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{dest.name}.", suffix=".png", dir=dest.parent)
    try:
        os.close(fd)
        img.save(tmp, format="PNG", optimize=True)
        os.replace(tmp, dest)
    finally:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass


def bust_image_picker_cache(preview_root: Path) -> None:
    """Invalidate omarchy-menu-images rows/thumbnails for our preview dir."""
    try:
        os.utime(preview_root, None)
    except OSError:
        pass

    cache_dir = Path(
        os.environ.get(
            "OMATTY_IMAGE_SELECTOR_CACHE",
            home() / ".cache/omarchy/image-selector",
        )
    )
    if not cache_dir.is_dir():
        return

    needle = str(preview_root.resolve())
    for path in cache_dir.iterdir():
        name = path.name
        if not (
            name.endswith(".rows")
            or name.endswith(".signature")
            or name.endswith(".fast-signature")
            or name.endswith(".rows.lock")
        ):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if needle in text or str(preview_root) in text:
            path.unlink(missing_ok=True)

    # Drop index rows + hashed jpgs that pointed at our preview PNGs so the
    # next open re-thumbnails from the real (post-install) mockups.
    index = cache_dir / "index.tsv"
    if index.is_file():
        try:
            lines = index.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            lines = []
        kept: list[str] = []
        for line in lines:
            parts = line.split("\t")
            if parts and (needle in parts[0] or str(preview_root) in parts[0]):
                if len(parts) >= 3:
                    (cache_dir / f"{parts[2]}.jpg").unlink(missing_ok=True)
                    (cache_dir / f"{parts[2]}.jpg.lock").unlink(missing_ok=True)
                continue
            kept.append(line)
        try:
            atomic_write(index, ("\n".join(kept) + ("\n" if kept else "")))
        except OSError:
            pass


def tty_banner(tty: str = "tty1") -> str:
    """Match getty banner: Omarchy <uname -r> (ttyN). Nested VM often lands on tty1."""
    try:
        release = subprocess.check_output(
            ["uname", "-r"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except (OSError, subprocess.SubprocessError):
        release = "7.2.3-arch1-3"
    return f"Omarchy {release} ({tty})"


def render_mockup(font_id: str, dest: Path | None = None) -> Path:
    """Fake /dev/tty framebuffer painted with the real PSF glyphs.

    Canvas size is fixed (like a monitor). Bigger console fonts fit fewer
    columns/rows, so the sample session gets hilariously cropped the same
    way a real TTY does — not a larger picture with airier letterspacing.

    Session script matches OmaVT (QEMU default-TTY capture): getty on tty1,
    login wolf, single-GPU passthrough starter. Extra glyph rows follow so
    small faces look roomy and fat Terminus still clips.
    """
    item = CURATED_BY_ID.get(font_id)
    if item is None:
        raise FileNotFoundError(f"unknown curated font: {font_id}")
    if resolve_font_file(item["file"]) is None:
        return render_missing_mockup(font_id, dest or preview_path(font_id))

    font = load_console_font(item["file"])
    colors = theme_colors()
    bg = _hex_rgb(colors["bg"])
    fg = _hex_rgb(colors["fg"])
    muted = _hex_rgb(colors["muted"])
    cyan = _hex_rgb(colors["cyan"])

    # Match omarchy-menu-images thumbnail size (1536×864). Real TTY is
    # top-left; no card chrome — the Style tile crop mostly shaves empty sides.
    w, h = 1536, 864
    footer_h = 36

    # Constant zoom so glyph size alone decides how much fits — same as a
    # real framebuffer. (Shrinking scale for big faces would fit *more*
    # cells and defeat the crop.)
    scale = 2
    cell_w = max(1, font.width * scale)
    cell_h = max(1, font.height * scale)
    term_x, term_y = 16, 16
    term_w = w - term_x * 2
    term_h = h - term_y - footer_h
    cols = max(8, term_w // cell_w)
    rows = max(3, term_h // cell_h)

    img = Image.new("RGB", (w, h), bg)
    draw = ImageDraw.Draw(img)
    ui_sm = try_ui_font(18)

    # Keep session lines in sync with OmaVT (sibling Style plugin).
    banner = tty_banner("tty1")
    prompt = "~ > "
    command = "sudo /home/wolf/vm-space/windows-11/single-gpu-start.sh"
    ruler = "".join(str(i % 10) for i in range(160))
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    lower = "abcdefghijklmnopqrstuvwxyz"

    # (text, color) rows — session first, then glyph demo that crops on fat faces.
    lines: list[tuple[str, tuple[int, int, int]]] = [
        (banner, fg),
        ("omarchy login: wolf", fg),
        ("Password:", fg),
        (prompt + command, cyan),  # whole line cyan-ish; split below when drawing
        ("", fg),
        (ruler, muted),
        (alphabet * 3, fg),
        (lower * 3, fg),
        ("0123456789  +-*/=  ()[]{}  box:+-|/=  arrows:^v<>  " * 3, muted),
        ("# bigger face = fewer cells on the same glass", muted),
    ]

    term_layer = Image.new("RGB", (term_w, term_h), bg)
    row_i = 0
    for text, color in lines:
        if row_i >= rows:
            break
        if text == prompt + command:
            # Prompt accent + command — matches the QEMU capture.
            draw_text(term_layer, font, prompt[:cols], 0, row_i * cell_h, cyan, bg, scale)
            rest = command
            # Continue command on same row after prompt width in cells.
            prompt_cells = len(prompt)
            if prompt_cells < cols:
                draw_text(
                    term_layer,
                    font,
                    rest[: cols - prompt_cells],
                    prompt_cells * cell_w,
                    row_i * cell_h,
                    fg,
                    bg,
                    scale,
                )
            row_i += 1
            continue
        draw_text(term_layer, font, text[:cols], 0, row_i * cell_h, color, bg, scale)
        row_i += 1

    img.paste(term_layer, (term_x, term_y))

    badge = f"{item['label']} · {font.width}x{font.height} · {cols}x{rows} cells · {item['file']}"
    draw.text((term_x, h - 28), badge, font=ui_sm, fill=muted)

    dest = dest or preview_path(font_id)
    save_png_atomic(img, dest)
    return dest


def render_missing_mockup(font_id: str, dest: Path) -> Path:
    item = CURATED_BY_ID.get(font_id, {"label": font_id, "blurb": "", "pkg": ""})
    colors = theme_colors()
    bg = _hex_rgb(colors["bg"])
    fg = _hex_rgb(colors["fg"])
    accent = _hex_rgb(colors["accent"])
    muted = _hex_rgb(colors["muted"])
    w, h = 1536, 864
    img = Image.new("RGB", (w, h), bg)
    draw = ImageDraw.Draw(img)
    ui = try_ui_font(28)
    ui_sm = try_ui_font(20)
    draw.text((120, 48), f"TTY · {item.get('label', font_id)}", font=ui, fill=accent)
    draw.text((120, 100), item.get("blurb", ""), font=ui_sm, fill=muted)
    pkg = item.get("pkg") or "terminus-font"
    draw.text((120, 280), "Not installed on this system yet.", font=ui, fill=fg)
    draw.text((120, 340), f"Pick it and OmaTTY will install {pkg},", font=ui_sm, fill=fg)
    draw.text((120, 380), "then set FONT= in /etc/vconsole.conf.", font=ui_sm, fill=fg)
    save_png_atomic(img, dest)
    return dest


def generate_all_previews() -> list[Path]:
    out: list[Path] = []
    preview_root = paths()["cache"] / "previews"
    preview_root.mkdir(parents=True, exist_ok=True)
    wanted = {item["id"] for item in CURATED}
    for existing in preview_root.glob("*.png"):
        if existing.stem not in wanted:
            existing.unlink(missing_ok=True)
    for item in CURATED:
        out.append(render_mockup(item["id"]))
    # Force omarchy-menu-images to rebuild thumbnails (survives reboot otherwise).
    bust_image_picker_cache(preview_root)
    return out


# ---------------------------------------------------------------------------
# vconsole.conf + setfont
# ---------------------------------------------------------------------------


def read_vconsole() -> str:
    path = vconsole_path()
    if path.is_file() and os.access(path, os.R_OK):
        return path.read_text(encoding="utf-8")
    result = subprocess.run(
        ["sudo", "cat", "--", str(path)],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip() or f"exit {result.returncode}"
        raise RuntimeError(f"failed to read {path}: {err}")
    return result.stdout


def write_vconsole(content: str) -> None:
    path = vconsole_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    if os.access(path.parent, os.W_OK) and (not path.exists() or os.access(path, os.W_OK)):
        atomic_write(path, content)
        return

    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        prefix="omatty-vconsole.",
        suffix=".conf",
        delete=False,
    ) as handle:
        handle.write(content)
        handle.flush()
        os.fsync(handle.fileno())
        staged = handle.name

    try:
        script = (
            "set -euo pipefail\n"
            f'dest={json.dumps(str(path))}\n'
            f'src={json.dumps(staged)}\n'
            'tmp=$(mktemp --tmpdir="$(dirname -- "$dest")" ".$(basename -- "$dest").omatty.XXXXXXXX")\n'
            'cp --reflink=never -- "$src" "$tmp"\n'
            'chown root:root -- "$tmp"\n'
            'chmod 644 -- "$tmp"\n'
            'mv -f -- "$tmp" "$dest"\n'
        )
        result = subprocess.run(
            ["sudo", "/bin/bash", "-c", script],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            err = (result.stderr or result.stdout or "").strip() or f"exit {result.returncode}"
            raise RuntimeError(f"failed to write {path}: {err}")
    finally:
        try:
            os.unlink(staged)
        except FileNotFoundError:
            pass


def patch_vconsole(existing: str, font_stem: str) -> str:
    """Set FONT= while preserving KEYMAP / XKB* and dropping prior omatty marks."""
    cleaned = remove_marked(existing, VCONSOLE_START, VCONSOLE_END)
    lines = cleaned.splitlines()
    out: list[str] = []
    saw_font = False
    for line in lines:
        if re.match(r"^FONT=", line):
            if not saw_font:
                out.append(VCONSOLE_START)
                out.append(f"# Console font managed by omatty ({PLUGIN_ID})")
                out.append(f"FONT={font_stem}")
                out.append(VCONSOLE_END)
                saw_font = True
            continue
        out.append(line)
    if not saw_font:
        if out and out[-1].strip():
            out.append("")
        out.append(VCONSOLE_START)
        out.append(f"# Console font managed by omatty ({PLUGIN_ID})")
        out.append(f"FONT={font_stem}")
        out.append(VCONSOLE_END)
    text = "\n".join(out)
    if not text.endswith("\n"):
        text += "\n"
    return text


def ensure_package(pkg: str) -> None:
    if not pkg:
        return
    probe = subprocess.run(
        ["pacman", "-Q", pkg],
        check=False,
        capture_output=True,
        text=True,
    )
    if probe.returncode == 0:
        return
    note(f"installing {pkg}…")
    runners: list[list[str]] = []
    if subprocess.run(["bash", "-lc", "command -v omarchy"], capture_output=True).returncode == 0:
        runners.append(["omarchy", "pkg", "add", pkg])
    runners.append(["sudo", "pacman", "-S", "--needed", "--noconfirm", pkg])
    for cmd in runners:
        result = subprocess.run(cmd, check=False)
        if result.returncode == 0:
            return
    raise RuntimeError(f"failed to install package: {pkg}")

def apply_setfont(font_stem: str) -> None:
    """Push the font to active virtual consoles when possible (best-effort).

    Skipped when OMATTY_VCONSOLE points at a fixture (tests) or
    OMATTY_SKIP_SETFONT is set — so check.sh never trips an interactive sudo.
    """
    if os.environ.get("OMATTY_SKIP_SETFONT") == "1":
        return
    if vconsole_path() != Path("/etc/vconsole.conf"):
        return
    font_path = resolve_font_file(font_stem)
    target = str(font_path) if font_path else font_stem
    # systemd unit re-reads vconsole.conf
    subprocess.run(
        ["sudo", "systemctl", "restart", "systemd-vconsole-setup.service"],
        check=False,
        capture_output=True,
        text=True,
    )
    # Also poke visible TTYs directly — restart alone can miss an open tty.
    subprocess.run(
        ["sudo", "setfont", target],
        check=False,
        capture_output=True,
        text=True,
    )


def set_font(font_id: str, *, quiet: bool = False, dry_run: bool = False) -> int:
    item = CURATED_BY_ID.get(font_id)
    if item is None:
        note(f"unknown font: {font_id}")
        return 1

    if resolve_font_file(item["file"]) is None:
        pkg = item.get("pkg")
        if not pkg:
            note(f"font file missing and no package mapping: {font_id}")
            return 1
        if dry_run:
            note(f"would install {pkg} then set FONT={item['file']}")
            return 0
        ensure_package(pkg)
        if resolve_font_file(item["file"]) is None:
            note(f"font still missing after installing {pkg}: {item['file']}")
            return 1

    existing = read_vconsole()
    patched = patch_vconsole(existing, item["file"])
    if dry_run:
        sys.stdout.write(patched)
        return 0

    write_vconsole(patched)
    apply_setfont(item["file"])

    state = paths()["state"]
    state.mkdir(parents=True, exist_ok=True)
    atomic_write(state / "current", font_id + "\n")

    # Keep the TTY starship profile in place whenever a console font is set.
    install_starship_tty(quiet=True)

    # Refresh mockups + bust image-selector cache so Style → TTY Fonts does not
    # keep showing the pre-install "Not installed" thumbnails.
    try:
        generate_all_previews()
    except Exception as exc:  # noqa: BLE001 — apply already succeeded
        note(f"preview refresh skipped: {exc}")

    if not quiet:
        note(f"vconsole.conf FONT={item['file']}")
        note("switch to a real TTY (Ctrl+Alt+F3) to see it; starship TTY profile armed")
    return 0


# ---------------------------------------------------------------------------
# Starship TTY profile + bashrc snippet
# ---------------------------------------------------------------------------


STARSHIP_TTY = """# TTY-safe Starship profile — managed by omatty ({plugin}).
# Loaded only on real virtual consoles (/dev/tty*) via the bashrc snippet.
# Glyphs that tofu on Terminus / default PSF fonts are swapped for fun ASCII.

add_newline = true
command_timeout = 200
format = "[$directory$git_branch$git_status]($style)$character"

[character]
error_symbol = "[x](bold cyan)"
success_symbol = "[>](bold cyan)"

[directory]
truncation_length = 2
truncation_symbol = ".../"
repo_root_style = "bold cyan"
repo_root_format = "[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style) "

[git_branch]
format = "[$branch]($style) "
style = "italic cyan"

[git_status]
format     = '[$all_status]($style)'
style      = "cyan"
ahead      = "^${{count}} "
diverged   = "<>^${{ahead_count}}v${{behind_count}} "
behind     = "v${{count}} "
conflicted = "! "
up_to_date = "= "
untracked  = "? "
modified   = "* "
stashed    = ""
staged     = ""
renamed    = ""
deleted    = ""
""".format(plugin=PLUGIN_ID)


STARSHIP_SNIPPET = """# Prefer the TTY-safe starship profile on real virtual consoles so Omarchy's
# desktop glyphs (❯ ✗ ⇡  …) do not render as tofu under bitmap console fonts.
if [[ -z ${STARSHIP_CONFIG:-} ]]; then
  _omatty_tty="$(tty 2>/dev/null || true)"
  if [[ ${_omatty_tty} == /dev/tty* ]]; then
    export STARSHIP_CONFIG="${OMATTY_STARSHIP:-__STARSHIP_PATH__}"
  fi
  unset _omatty_tty
fi
"""


def install_starship_tty(*, quiet: bool = False) -> None:
    cfg = paths()["config"]
    cfg.mkdir(parents=True, exist_ok=True)
    starship_path = cfg / "starship-tty.toml"
    atomic_write(starship_path, STARSHIP_TTY)

    snippet = STARSHIP_SNIPPET.replace("__STARSHIP_PATH__", str(starship_path))
    bashrc = paths()["bashrc"]
    existing = bashrc.read_text(encoding="utf-8") if bashrc.is_file() else ""
    existing = remove_marked(existing, BASHRC_START, BASHRC_END)
    block = f"{BASHRC_START}\n{snippet.rstrip()}\n{BASHRC_END}\n"

    # Insert before the interactive rc source when possible so STARSHIP_CONFIG
    # is set before `starship init` — also fine after, since starship reads it
    # at prompt time, but earlier is tidier.
    marker = 'source "$OMARCHY_PATH/default/bash/rc"'
    if marker in existing:
        existing = existing.replace(marker, block + "\n" + marker, 1)
    else:
        if existing and not existing.endswith("\n"):
            existing += "\n"
        existing = existing + "\n" + block

    atomic_write(bashrc, existing)
    if not quiet:
        note(f"starship TTY profile → {starship_path}")
        note(f"bashrc snippet → {bashrc}")


def uninstall_starship_tty() -> None:
    bashrc = paths()["bashrc"]
    if bashrc.is_file():
        content = bashrc.read_text(encoding="utf-8")
        if BASHRC_START in content:
            atomic_write(bashrc, remove_marked(content, BASHRC_START, BASHRC_END))
    # Leave starship-tty.toml in config dir; harmless and reusable.


# ---------------------------------------------------------------------------
# Style menu
# ---------------------------------------------------------------------------


def menu_action() -> str:
    switcher = plugin_dir() / "bin" / "omatty-switcher"
    setter = plugin_dir() / "bin" / "omatty-set"
    return (
        f'font="$({switcher})"; '
        f'[[ -n $font ]] && omarchy-launch-floating-terminal-with-presentation '
        f'"{setter} $(printf %q "$font")"'
    )


def install_menu_entry() -> None:
    path = paths()["menu"]
    content = path.read_text(encoding="utf-8") if path.is_file() else "{\n}\n"
    content = remove_marked(content, MENU_START, MENU_END)
    entries = [
        (
            "style.tty-font",
            {
                "icon": "󰯃",
                "label": "TTY Fonts",
                "aliases": ["tty", "console", "vconsole", "terminus"],
                "description": "Preview console fonts (Terminus + stock) and set FONT= in vconsole.conf (sudo)",
                "action": menu_action(),
            },
        )
    ]
    brace = content.find("{")
    if brace < 0:
        raise RuntimeError(f"menu config has no root object: {path}")
    body = [MENU_START]
    for key, value in entries:
        body.append(f"  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},")
    body.append(MENU_END)
    insertion = "\n".join(body) + "\n"
    atomic_write(path, content[: brace + 1] + "\n" + insertion + content[brace + 1 :])


def uninstall_menu_entry() -> None:
    path = paths()["menu"]
    if not path.is_file():
        return
    content = path.read_text(encoding="utf-8")
    if MENU_START in content:
        atomic_write(path, remove_marked(content, MENU_START, MENU_END))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def cmd_list(_: argparse.Namespace) -> int:
    for item in curated_available():
        flag = " " if item["available"] else "!"
        print(f"{flag} {item['id']}\t{item['label']}\t{item.get('blurb', '')}")
    return 0


def cmd_current(_: argparse.Namespace) -> int:
    font_id = current_font_id()
    if not font_id:
        return 1
    print(font_id)
    return 0


def cmd_preview(args: argparse.Namespace) -> int:
    if args.font:
        if args.font not in CURATED_BY_ID:
            note(f"unknown font: {args.font}")
            return 1
        path = render_mockup(args.font)
        print(path)
        return 0
    written = generate_all_previews()
    print(len(written))
    return 0


def cmd_set(args: argparse.Namespace) -> int:
    return set_font(args.font, quiet=args.quiet, dry_run=args.dry_run)


def cmd_show(args: argparse.Namespace) -> int:
    item = CURATED_BY_ID.get(args.font)
    if item is None:
        note(f"unknown font: {args.font}")
        return 1
    try:
        existing = read_vconsole()
    except Exception:
        existing = "KEYMAP=us\n"
    sys.stdout.write(patch_vconsole(existing, item["file"]))
    return 0


def cmd_switcher(_: argparse.Namespace) -> int:
    generate_all_previews()
    preview_dir = paths()["cache"] / "previews"
    current = current_font_id()
    selected = ""
    if current and (preview_dir / f"{current}.png").is_file():
        selected = str(preview_dir / f"{current}.png")

    cmd = [
        "omarchy-menu-images",
        "--print-name",
        "--show-labels",
        "--filterable",
    ]
    if selected:
        cmd.extend(["--selected", selected])
    cmd.append(str(preview_dir))

    try:
        result = subprocess.run(cmd, check=False, capture_output=True, text=True)
    except FileNotFoundError:
        note("omarchy-menu-images not found")
        return 1

    choice = (result.stdout or "").strip()
    if result.returncode != 0 and not choice:
        return result.returncode or 1
    if choice:
        print(choice)
    return 0


def cmd_install_menu(_: argparse.Namespace) -> int:
    install_menu_entry()
    install_starship_tty()
    note(f"menu entry → {paths()['menu']}")
    return 0


def cmd_uninstall_menu(_: argparse.Namespace) -> int:
    uninstall_menu_entry()
    uninstall_starship_tty()
    return 0


def cmd_install_starship(_: argparse.Namespace) -> int:
    install_starship_tty()
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="omatty", description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List curated console fonts").set_defaults(func=cmd_list)
    sub.add_parser("current", help="Print the active/last-set font id").set_defaults(func=cmd_current)

    preview = sub.add_parser("preview", help="Render TTY mockup PNG(s)")
    preview.add_argument("font", nargs="?", help="Font id; omit for all")
    preview.set_defaults(func=cmd_preview)

    show = sub.add_parser("show", help="Print the patched vconsole.conf for a font")
    show.add_argument("font", help="Font id")
    show.set_defaults(func=cmd_show)

    setter = sub.add_parser("set", help="Set FONT= in vconsole.conf (sudo)")
    setter.add_argument("font", help="Font id")
    setter.add_argument("--quiet", action="store_true")
    setter.add_argument("--dry-run", action="store_true")
    setter.set_defaults(func=cmd_set)

    sub.add_parser("switcher", help="Open image picker; print chosen font id").set_defaults(
        func=cmd_switcher
    )
    sub.add_parser("install-menu", help="Add Style → TTY Fonts + starship TTY profile").set_defaults(
        func=cmd_install_menu
    )
    sub.add_parser("uninstall-menu", help="Remove Style → TTY Fonts + bashrc snippet").set_defaults(
        func=cmd_uninstall_menu
    )
    sub.add_parser("install-starship", help="(Re)write TTY starship profile + bashrc snippet").set_defaults(
        func=cmd_install_starship
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except BrokenPipeError:
        return 0
    except Exception as exc:  # noqa: BLE001 — CLI surface
        note(str(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
