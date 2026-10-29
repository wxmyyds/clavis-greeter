pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Greeter shim for Clavis' SystemIdentityService.
//
// The real service reports the *currently logged in* user (the "greeter"
// account) and probes the machine with `sysmon`. For a login screen we must
// report the *target* account instead, so accountName comes from
// CLAVIS_GREETER_USER. The remaining identity fields are filled from cheap
// local sources so the lock screen's status widgets keep working.
Singleton {
    id: root

    readonly property string targetUser: Quickshell.env("CLAVIS_GREETER_USER") || "user"

    property string hostName: "host"
    property string kernelRelease: "unknown"
    property string distroId: "linux"
    property string distroName: "Linux"
    property string wmName: "niri"
    property string shellName: "clavis"
    property bool uptimeActive: Object.keys(_uptimeConsumers).length > 0
    property real uptimeSeconds: 0
    property bool _uptimeBaseReady: false
    property var _uptimeConsumers: ({})

    readonly property string accountName: root.targetUser
    readonly property string accountIdentity: root.accountName + "@" + root.hostName
    readonly property string uptimeText: root.formatUptime(root.uptimeSeconds)

    function setUptimeConsumer(owner, active) {
        const key = String(owner || "").trim();
        if (key === "")
            return;
        const next = Object.assign({}, root._uptimeConsumers);
        if (active)
            next[key] = true;
        else
            delete next[key];
        root._uptimeConsumers = next;
    }

    function formatUptime(seconds) {
        const total = Math.max(0, Math.floor(Number(seconds) || 0));
        const days = Math.floor(total / 86400);
        const hours = Math.floor((total % 86400) / 3600);
        const minutes = Math.floor((total % 3600) / 60);
        if (days > 0)
            return days + "d " + hours + "h";
        if (hours > 0)
            return hours + "h " + minutes + "m";
        return minutes + "m";
    }

    Component.onCompleted: {
        hostProc.running = true;
        osProc.running = true;
        kernelProc.running = true;
        uptimeProc.running = true;
    }

    Process {
        id: hostProc
        command: ["/bin/cat", "/proc/sys/kernel/hostname"]
        stdout: SplitParser {
            onRead: data => root.hostName = String(data).trim() || "host"
        }
    }
    Process {
        id: osProc
        command: ["/bin/sh", "-c", ". /etc/os-release 2>/dev/null; printf '%s\\n%s\\n' \"$ID\" \"$PRETTY_NAME\""]
        stdout: SplitParser {
            onRead: data => {
                const v = String(data).trim();
                if (v !== "" && root.distroId === "linux")
                    root.distroId = v;
                else if (v !== "")
                    root.distroName = v;
            }
        }
    }
    Process {
        id: kernelProc
        command: ["/usr/bin/uname", "-r"]
        stdout: SplitParser {
            onRead: data => root.kernelRelease = String(data).trim() || "unknown"
        }
    }
    Process {
        id: uptimeProc
        command: ["/bin/sh", "-c", "cut -d' ' -f1 /proc/uptime"]
        stdout: SplitParser {
            onRead: data => {
                root.uptimeSeconds = Number(String(data).trim()) || 0;
                root._uptimeBaseReady = true;
            }
        }
    }
}
