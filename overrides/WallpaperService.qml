// SPDX-License-Identifier: GPL-3.0-only
pragma Singleton
import QtQuick
import Quickshell

// Greeter shim for Clavis' WallpaperService.
//
// The real service resolves the wallpaper from the target user's personalisation
// config under $HOME, which the greeter user cannot read. The installer copies
// the wallpaper to a world-readable path and sets CLAVIS_GREETER_WALLPAPER.
Singleton {
    id: root

    readonly property string wallpaperPath: Quickshell.env("CLAVIS_GREETER_WALLPAPER") || ""
    readonly property string fillMode: Quickshell.env("CLAVIS_GREETER_WALLPAPER_FILLMODE") || "Fill"

    property int revision: 0
    property int settingsRevision: 0
    property bool quickshellContentVisible: false

    function wallpaperForScreen(screenName) {
        return root.wallpaperPath;
    }

    function fillModeForScreen(screenName) {
        return root.fillMode;
    }

    function qtFillMode(modeName) {
        switch (modeName) {
        case "Stretch":
            return Image.Stretch;
        case "Fit":
        case "PreserveAspectFit":
            return Image.PreserveAspectFit;
        case "Tile":
            return Image.Tile;
        case "TileVertically":
            return Image.TileVertically;
        case "TileHorizontally":
            return Image.TileHorizontally;
        case "Pad":
            return Image.Pad;
        default:
            return Image.PreserveAspectCrop;
        }
    }

    // ── API surface kept for the real components that may reference it ────
    function overviewWallpaperForScreen(screenName) {
        return "";
    }

    function overviewFillModeForScreen(screenName) {
        return root.fillMode;
    }

    function shaderFillMode(modeName) {
        return root.qtFillMode(modeName);
    }

    function reportDesktopError(message) {
        console.warn("[greeter-wallpaper]", message);
    }

    function reportOverviewSurface(surface) {
    }
}
