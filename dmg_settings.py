# dmgbuild settings for the Heidrun release DMG.
#
# Invoked from the repo root via:
#   .venv/bin/dmgbuild \
#       -s dmg_settings.py \
#       -D app=<path/to/Heidrun.app> \
#       Heidrun <output.dmg>
#
# dmgbuild writes the .DS_Store directly via the `ds_store` Python
# library — no AppleScript, no Finder automation. This sidesteps the
# macOS 26 Tahoe regressions that made create-dmg drop our background.
# After this produces an unsigned DMG, the surrounding shell pipeline
# does codesign + notarytool + stapler.

import os
import shutil

# CLI flag: -D app=<path>. Defaults to the path the CLAUDE.md flow
# leaves the freshly-archived .app at.
application = defines.get(
    'app',
    'build/Heidrun.xcarchive/Products/Applications/Heidrun.app',
)
appname = os.path.basename(application)

# --- Documentation folder ---
# Assembled at build time from the repo-root docs so the canonical
# files (LICENSE, NOTICE.md, README.md, CHANGELOG.md,
# THIRD_PARTY_LICENSES.md) stay in one place. The mounted DMG then
# shows a single "Documentation" folder beside the Applications
# symlink, which keeps the install surface clean while still meeting
# GPL-2.0 / Apache-2.0 attribution requirements (license texts ship
# alongside the binary).
# dmgbuild exec()s this script, so `__file__` isn't defined. The
# CLAUDE.md flow always invokes dmgbuild from the repo root, so the
# current working directory is the right anchor.
repo_root = os.getcwd()
docs_staging = os.path.join(repo_root, 'build', 'dmg-docs')
docs_folder = os.path.join(docs_staging, 'Documentation')
shutil.rmtree(docs_staging, ignore_errors=True)
os.makedirs(docs_folder, exist_ok=True)
for source_name in (
    'LICENSE',
    'NOTICE.md',
    'README.md',
    'CHANGELOG.md',
    'THIRD_PARTY_LICENSES.md',
):
    shutil.copy(
        os.path.join(repo_root, source_name),
        os.path.join(docs_folder, source_name),
    )

# --- Disk image container ---
format = 'UDZO'          # compressed read-only
filesystem = 'HFS+'

# --- Window geometry ---
# 512x512 — matches the multi-res TIFF background (1x 512, 2x 1024).
window_rect = ((140, 140), (512, 512))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False

# --- Icon view options ---
# 90pt icons sit comfortably inside the 512x512 window without
# crowding the centred Heidrun logo painted on the background.
icon_size = 90
text_size = 11

# --- Background image ---
# Multi-resolution TIFF (1x 512 + 2x 1024, 8-bit sRGB) checked into the
# repo so the packaging step is a one-liner. Regenerate when the app
# icon changes via `tiffutil -cathidpicheck <1x.png> <2x.png> -out
# _IconWerk/dmg-background.tif` against the AppIcon source PNGs.
background = '_IconWerk/dmg-background.tif'

# --- Volume icon shown when DMG is mounted ---
icon = 'Heidrun/Resources/Bookmark.icns'

# --- Content + layout ---
# Three items: the install pair (Heidrun + Applications) on the upper
# row, the Documentation folder centred on the lower row. Both rows
# clear the centred Heidrun glyph that lives in the 512x512 background
# TIFF (visible band runs roughly y=120-400).
files = [
    application,
    docs_folder,
]
symlinks = {'Applications': '/Applications'}
icon_locations = {
    appname:         (128, 180),
    'Applications':  (384, 180),
    'Documentation': (256, 400),
}
