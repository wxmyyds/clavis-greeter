pragma Singleton
import QtQuick
import Quickshell
import qs.Common

// Greeter shim for Clavis' AvatarService.
//
// The real service reads $HOME/.face, which for the greeter user is not the
// target account's home. The installer copies the target user's avatar to a
// world-readable location and points CLAVIS_GREETER_AVATAR at it.
Singleton {
    id: root

    readonly property string avatarPath: Quickshell.env("CLAVIS_GREETER_AVATAR") || ""

    // Cache-buster; kept for API compatibility with the real service.
    property int revision: 0
    property bool busy: false
    property string pendingSource: ""

    readonly property string avatarUrl: root.avatarPath !== ""
        ? Paths.fileUrl(root.avatarPath) + "?revision=" + root.revision
        : ""

    signal updateFinished(bool success, string message)

    function setAvatar(path) {
        // Avatars are managed by the target user's session, not the greeter.
        root.updateFinished(false, qsTr("Avatar cannot be changed from the login screen"));
    }
}
