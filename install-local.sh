#!/bin/bash
# Local installer for clavis-greeter (mirrors what the package installs).
#
#   sudo ./install-local.sh [target-user]
#
# Layout installed:
#   /usr/lib/clavis-greeter/{build.sh,overrides/,backend/,session/}
#   /usr/lib/clavis-greeter/shell/            (generated, symlinks to Clavis)
#   /usr/bin/clavis-greeter-build             (regenerate shell tree)
#   /usr/bin/clavis-greeter-session           (greetd wrapper)
#   /usr/bin/clavis-greeter-setup             (configure greetd)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${1:-${SUDO_USER:-$(logname 2>/dev/null || true)}}"
if [ -z "$TARGET_USER" ]; then
    echo "error: pass the target desktop user, e.g. sudo ./install-local.sh alice" >&2
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run this with sudo" >&2
    exit 1
fi

LIB=/usr/lib/clavis-greeter

echo "==> Installing sources to $LIB"
install -d -m 755 "$LIB"
install -m 755 "$HERE/build.sh" "$LIB/build.sh"
install -d -m 755 "$LIB/overrides" "$LIB/backend" "$LIB/session"
install -m 644 "$HERE"/overrides/*.qml "$LIB/overrides/"
install -m 755 "$HERE/backend/greeter-backend.py" "$LIB/backend/"
install -m 755 "$HERE/session/clavis-greeter-session" "$LIB/session/"

echo "==> Installing commands"
cat > /usr/bin/clavis-greeter-build <<'EOF'
#!/bin/bash
exec /usr/lib/clavis-greeter/build.sh /usr/lib/clavis-greeter/shell
EOF
chmod 755 /usr/bin/clavis-greeter-build

install -m 755 "$HERE/session/clavis-greeter-session" /usr/bin/clavis-greeter-session
install -m 755 "$HERE/setup.sh" /usr/bin/clavis-greeter-setup

echo "==> Building shell tree"
/usr/bin/clavis-greeter-build

echo "==> Running setup"
/usr/bin/clavis-greeter-setup "$TARGET_USER"
