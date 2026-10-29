#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Build the Clavis Greeter shell tree.
#
# Strategy: reuse Clavis' *real* QML modules (Common, Components, Widgets,
# Modules, assets, scripts) via symlinks so the lock screen is byte-identical.
# Only three services need replacing because they read the *logged-in* user's
# HOME, which the greeter user cannot see:
#
#   Services/SystemIdentityService.qml  -> account name = target user
#   Services/AvatarService.qml          -> avatar       = target user's photo
#   Services/WallpaperService.qml       -> wallpaper    = world-readable copy
#
# Everything is generated into ./src so the project stays reproducible.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAVIS="${CLAVIS_SHELL_DIR:-/etc/xdg/quickshell/clavis}"
OUT="${1:-$HERE/src}"

if [ ! -d "$CLAVIS" ]; then
    echo "error: Clavis shell dir not found: $CLAVIS" >&2
    exit 1
fi

echo "==> Rebuilding $OUT from $CLAVIS"
rm -rf "$OUT"
mkdir -p "$OUT"

# Symlink every top-level entry except shell.qml (ours) and Services (rebuilt).
for entry in "$CLAVIS"/*; do
    name="$(basename "$entry")"
    case "$name" in
        shell.qml|AppShell.qml|Services) continue ;;
    esac
    ln -s "$entry" "$OUT/$name"
done

# Services: copy every real file (Quickshell's module scanner does not
# register per-file symlinks as singletons), then overwrite the three shims.
# Copy *everything* -- .qml, .js and any other assets the services reference.
mkdir -p "$OUT/Services"
for entry in "$CLAVIS"/Services/*; do
    name="$(basename "$entry")"
    case "$name" in
        SystemIdentityService.qml|AvatarService.qml|WallpaperService.qml) continue ;;
    esac
    cp -a "$entry" "$OUT/Services/$name"
done

# Install the shims from ./overrides.
for shim in SystemIdentityService.qml AvatarService.qml WallpaperService.qml; do
    cp "$HERE/overrides/$shim" "$OUT/Services/$shim"
done

# The greeter shell entry point + the one adapted lock wrapper.
cp "$HERE/overrides/shell.qml" "$OUT/shell.qml"
cp "$HERE/overrides/ClavisLock.qml" "$OUT/ClavisLock.qml"

echo "==> Done. Tree:"
ls -la "$OUT" | sed 's/^/    /'
echo "    Services/: $(ls "$OUT/Services" | wc -l) entries"
