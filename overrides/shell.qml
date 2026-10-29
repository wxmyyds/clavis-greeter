// Clavis Greeter -- greetd login screen that reuses Clavis' real lock screen.
//
// The lock UI is Clavis' own `qs.Modules.Lock.DefaultLock` (giant clock, avatar,
// capsule password field, disc-reveal entrance, status row) loaded unmodified
// from the installed Clavis shell. This file only supplies:
//   * a stub `lock` object (DefaultLock talks to a WlSessionLock),
//   * a `context` object with the same interface as Clavis' LockContext,
//   * a backend process that performs greetd authentication.
//
//@ pragma UseQApplication
//@ pragma Env QT_WAYLAND_DISABLE_WINDOWDECORATION=1

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Modules.Lock

ShellRoot {
    id: shell

    readonly property string backendPath: Quickshell.env("CLAVIS_GREETER_BACKEND")
        || "/usr/lib/clavis-greeter/greeter-backend.py"
    readonly property string targetUser: Quickshell.env("CLAVIS_GREETER_USER") || ""

    // The account the session will be started for. Prefer the explicit env set
    // by the greetd command; otherwise fall back to what the backend detected.
    property string loginUser: shell.targetUser
    property bool ready: false

    // ── DefaultLock expects a WlSessionLock; give it a minimal stand-in. ──
    QtObject {
        id: stubLock
        signal unlock()
        property bool locked: true
        property bool secure: true
    }

    // ── Context interface shared with Clavis' LockContext. ────────────────
    QtObject {
        id: ctx
        property bool authRevealed: false
        property string currentText: ""
        property bool showFailure: false
        property bool unlockInProgress: false

        signal unlockFailed()

        function tryUnlock() {
            if (unlockInProgress)
                return;
            if (currentText.length === 0)
                return;
            unlockInProgress = true;
            showFailure = false;
            backend.write(JSON.stringify({
                cmd: "login",
                username: shell.loginUser,
                password: currentText
            }) + "\n");
        }

        function finishUnlock() {
            // DefaultLock finished its exit animation after greetd accepted the
            // session; quitting lets greetd start it.
            Qt.quit();
        }
    }

    function handleEvent(line) {
        let ev;
        try { ev = JSON.parse(line); } catch (e) { return; }
        switch (ev.event) {
        case "ready":
            if (!shell.targetUser && ev.defaultUser)
                shell.loginUser = ev.defaultUser;
            shell.ready = true;
            if ((ev.startupMode || "clock") === "auth") {
                ctx.authRevealed = true;
            }
            break;
        case "auth_error":
            ctx.unlockInProgress = false;
            ctx.currentText = "";
            ctx.showFailure = true;
            ctx.unlockFailed();
            break;
        case "fatal":
            ctx.unlockInProgress = false;
            ctx.showFailure = true;
            break;
        case "success":
            // Ask DefaultLock to play its exit animation; it will call
            // ctx.finishUnlock() when done.
            stubLock.unlock();
            break;
        }
    }

    Process {
        id: backend
        running: true
        stdinEnabled: true
        command: [shell.backendPath]
        environment: ({
            GREETD_SOCK: Quickshell.env("GREETD_SOCK") || "",
            HOME: Quickshell.env("HOME") || "",
            CLAVIS_GREETER_USER: shell.targetUser,
            CLAVIS_GREETER_STARTUP: Quickshell.env("CLAVIS_GREETER_STARTUP") || "clock",
            CLAVIS_GREETER_OK_FILE: Quickshell.env("CLAVIS_GREETER_OK_FILE") || ""
        })
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                const t = String(data).trim();
                if (t !== "")
                    shell.handleEvent(t);
            }
        }
        stderr: SplitParser {
            splitMarker: "\n"
            onRead: data => console.warn("[greeter-backend]", String(data))
        }
    }

    PanelWindow {
        id: win
        visible: true
        color: "#15191D"
        screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        focusable: true
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        WlrLayershell.namespace: "clavis-greeter"
        WlrLayershell.layer: WlrLayer.Overlay

        ClavisLock {
            anchors.fill: parent
            lock: stubLock
            context: ctx
            screen: win.screen
            snapshotProvider: null
        }
    }
}
