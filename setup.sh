#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
# Configure clavis-greeter as the greetd login screen.
#
# Run once after installing the package (or from install-local.sh):
#     sudo clavis-greeter-setup [target-user]
#
# It backs up the current greetd configuration, points greetd at this greeter,
# copies the target user's wallpaper/avatar to a world-readable location, and
# enables an emergency text console on tty2.
set -euo pipefail

TARGET_USER="${1:-${SUDO_USER:-$(logname 2>/dev/null || true)}}"

if [ "$(id -u)" -ne 0 ]; then
    echo "error: run this with sudo" >&2
    exit 1
fi
if [ -z "$TARGET_USER" ] || ! id "$TARGET_USER" >/dev/null 2>&1; then
    echo "error: unknown target user: '${TARGET_USER}'" >&2
    echo "usage: sudo clavis-greeter-setup <user>" >&2
    exit 1
fi

TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
PAM_FILE=/etc/pam.d/greetd
PAM_BACKUP_PATH=""
if [ -r /etc/clavis-greeter.conf ]; then
    PAM_BACKUP_PATH="$(awk -F= '$1 == "CLAVIS_GREETER_PAM_BACKUP" { print substr($0, index($0, "=") + 1); exit }' /etc/clavis-greeter.conf)"
fi
case "$PAM_BACKUP_PATH" in
    /etc/pam.d/greetd.pre-clavis.*) ;;
    *) PAM_BACKUP_PATH="" ;;
esac
echo "==> Configuring clavis-greeter for '$TARGET_USER' (home $TARGET_HOME)"

# 1. Ensure the greeter account exists.
if ! id greeter >/dev/null 2>&1; then
    useradd -r -s /usr/bin/nologin -d /var/lib/clavis-greeter/home -M greeter
    echo "    created system user 'greeter'"
fi
usermod -aG video greeter 2>/dev/null || true

# 2. Target user configuration.
cat > /etc/clavis-greeter.conf <<EOF
# Target account the greeter logs in as (single-user desktop).
CLAVIS_GREETER_USER=$TARGET_USER
CLAVIS_GREETER_PAM_BACKUP=$PAM_BACKUP_PATH
EOF
chmod 644 /etc/clavis-greeter.conf

# 3. World-readable wallpaper + avatar (the greeter cannot read the user's home).
mkdir -p /var/lib/clavis-greeter
WP="$(python3 - "$TARGET_HOME" <<'PY'
import json, os, sys
home = sys.argv[1]
cfg = os.path.join(home, ".config/clavis/config.json")
try:
    data = json.load(open(cfg))
    path = (data.get("wallpaper") or {}).get("path") or ""
except Exception:
    path = ""
print(path if path and os.path.isfile(path) else "")
PY
)"
if [ -n "$WP" ]; then
    install -Dm644 "$WP" /var/lib/clavis-greeter/wallpaper.jpg
    echo "    wallpaper <- $WP"
else
    rm -f /var/lib/clavis-greeter/wallpaper.jpg
    echo "    warning: no wallpaper found; the greeter uses a flat background"
fi
if [ -f "$TARGET_HOME/.face" ]; then
    install -Dm644 "$TARGET_HOME/.face" /var/lib/clavis-greeter/avatar
    echo "    avatar    <- $TARGET_HOME/.face"
else
    rm -f /var/lib/clavis-greeter/avatar
fi

# 4. Writable home for the greeter account (Qt cache/config).
install -d -o greeter -g greeter -m 755 /var/lib/clavis-greeter/home

# 5. Mirror the desktop's font preferences into the greeter's own config so the
#    login screen renders with the fonts the user actually has installed.
GREETER_HOME=/var/lib/clavis-greeter/home
install -d -o greeter -g greeter -m 755 "$GREETER_HOME/.config/clavis"
python3 - "$TARGET_HOME" "$GREETER_HOME" <<'PY'
import json, os, sys

user_home, greeter_home = sys.argv[1], sys.argv[2]
src = os.path.join(user_home, ".config/clavis/config.json")
dst = os.path.join(greeter_home, ".config/clavis/config.json")

try:
    data = json.load(open(src, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    sys.exit(0)

fonts = (data.get("theme") or {}).get("fonts") or {}
fonts = {k: v for k, v in fonts.items() if isinstance(v, str) and v.strip()}
if not fonts:
    sys.exit(0)

try:
    target = json.load(open(dst, encoding="utf-8"))
except (OSError, json.JSONDecodeError):
    target = {}

theme = target.setdefault("theme", {})
merged = theme.get("fonts") if isinstance(theme.get("fonts"), dict) else {}
merged.update(fonts)
theme["fonts"] = merged

with open(dst, "w", encoding="utf-8") as fh:
    json.dump(target, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print("    fonts     <- " + ", ".join(f"{k}={v}" for k, v in sorted(fonts.items())))
PY
chown greeter:greeter "$GREETER_HOME/.config/clavis/config.json" 2>/dev/null || true

# 6. Build the shell tree from the installed Clavis shell.
if [ -x /usr/bin/clavis-greeter-build ]; then
    /usr/bin/clavis-greeter-build
fi

# 7. Greeter compositor config: reuse the desktop's output blocks so the login
#    screen has the same scale/resolution as the session.
python3 - "$TARGET_HOME" > /usr/lib/clavis-greeter/niri-greeter.kdl <<'PYEOF'
import os, re, sys

home = sys.argv[1]
cfg = os.path.join(home, ".config/niri/config.kdl")
blocks = []
if os.path.isfile(cfg):
    text = open(cfg, encoding="utf-8").read()
    for match in re.finditer(r'^output\s+"[^"]+"\s*\{', text, re.M):
        start = match.start()
        depth = 0
        end = start
        for i in range(text.find("{", start), len(text)):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        blocks.append(text[start:end])

header = "// Generated by clavis-greeter-setup. Mirrors the desktop output config.\n"
extra = (
    "\nprefer-no-csd\n"
    "hotkey-overlay {\n    skip-at-startup\n}\n"
    "layout {\n    gaps 0\n    background-color \"#000000\"\n}\n"
)
sys.stdout.write(header + "\n".join(blocks) + "\n" + extra)
PYEOF

if ! niri validate -c /usr/lib/clavis-greeter/niri-greeter.kdl >/dev/null 2>&1; then
    echo "    warning: generated niri config failed validation:" >&2
    niri validate -c /usr/lib/clavis-greeter/niri-greeter.kdl 2>&1 | sed 's/^/      /' >&2
fi

# 8. Add oo7's optional hooks to the greetd-only PAM stack. Authentication
# stores PAM_AUTHTOK, then the session hook sends it to oo7 after pam_systemd
# has prepared the user's runtime directory. Existing local PAM policy remains
# intact; back up the file before the first change so rollback can restore it.
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ ! -f "$PAM_FILE" ]; then
    echo "error: $PAM_FILE is missing; install greetd before configuring clavis-greeter" >&2
    exit 1
fi

HAS_OO7_AUTH=0
HAS_OO7_SESSION=0
grep -Eq '^[[:space:]]*auth[[:space:]]+optional[[:space:]]+pam_oo7[.]so([[:space:]]|$)' "$PAM_FILE" && HAS_OO7_AUTH=1
grep -Eq '^[[:space:]]*session[[:space:]]+optional[[:space:]]+pam_oo7[.]so[[:space:]]+auto_start([[:space:]]|$)' "$PAM_FILE" && HAS_OO7_SESSION=1

if [ "$HAS_OO7_AUTH" -eq 0 ] || [ "$HAS_OO7_SESSION" -eq 0 ]; then
    if [ -z "$PAM_BACKUP_PATH" ] || [ ! -f "$PAM_BACKUP_PATH" ]; then
        PAM_BACKUP_PATH="$PAM_FILE.pre-clavis.$STAMP"
        cp -a "$PAM_FILE" "$PAM_BACKUP_PATH"
        CONFIG_TMP="$(mktemp /etc/clavis-greeter.conf.XXXXXX)"
        awk -F= '$1 != "CLAVIS_GREETER_PAM_BACKUP"' /etc/clavis-greeter.conf > "$CONFIG_TMP"
        printf 'CLAVIS_GREETER_PAM_BACKUP=%s\n' "$PAM_BACKUP_PATH" >> "$CONFIG_TMP"
        chmod 644 "$CONFIG_TMP"
        mv "$CONFIG_TMP" /etc/clavis-greeter.conf
        echo "    greetd PAM config backed up to $PAM_BACKUP_PATH"
    fi
    if [ "$HAS_OO7_AUTH" -eq 0 ]; then
        printf '\nauth       optional     pam_oo7.so\n' >> "$PAM_FILE"
    fi
    if [ "$HAS_OO7_SESSION" -eq 0 ]; then
        printf 'session    optional     pam_oo7.so auto_start\n' >> "$PAM_FILE"
    fi
    echo "    enabled optional oo7 PAM hooks for greetd"
else
    echo "    oo7 PAM hooks are already present"
fi

# 9. greetd configuration (backup + replace).
mkdir -p /etc/greetd

[ -f /etc/greetd/config.toml ] && cp -a /etc/greetd/config.toml "/etc/greetd/config.toml.pre-clavis.$STAMP"
cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 1

[default_session]
command = "/usr/bin/clavis-greeter-session"
user = "greeter"
EOF
echo "    greetd config backed up to /etc/greetd/config.toml.pre-clavis.$STAMP"

# 10. Emergency text console on tty2 (immune to greeter problems).
systemctl enable getty@tty2.service >/dev/null 2>&1 || true

# 11. Rollback helper: plain text login.
#    agreety ships as a hard dependency of greetd, so this fallback keeps
#    working even if the graphical greeter (or any other greeter) is removed.
cat > /etc/greetd/config.toml.agreety-fallback <<'EOF2'
[terminal]
vt = 1

[default_session]
command = "/usr/bin/agreety --cmd /usr/bin/niri-session"
user = "greeter"
EOF2
chmod 644 /etc/greetd/config.toml.agreety-fallback

cat > /usr/bin/clavis-greeter-rollback <<'EOF'
#!/bin/bash
# Replace the graphical greeter with a plain text login that always works.
set -e
F=/etc/greetd/config.toml.agreety-fallback
if [ ! -f "$F" ]; then
    echo "error: $F is missing" >&2
    exit 1
fi
cp -a "$F" /etc/greetd/config.toml
echo "restored text login: $F -> /etc/greetd/config.toml"
PAM_BACKUP="$(awk -F= '$1 == "CLAVIS_GREETER_PAM_BACKUP" { print substr($0, index($0, "=") + 1); exit }' /etc/clavis-greeter.conf 2>/dev/null || true)"
case "$PAM_BACKUP" in
    /etc/pam.d/greetd.pre-clavis.*)
        if [ -f "$PAM_BACKUP" ]; then
            cp -a "$PAM_BACKUP" /etc/pam.d/greetd
            echo "restored greetd PAM config: $PAM_BACKUP -> /etc/pam.d/greetd"
        fi
        ;;
esac
echo "run: systemctl restart greetd   (or reboot)"
EOF
chmod 755 /usr/bin/clavis-greeter-rollback

echo "==> Done. Graphical greeter installed; rollback -> text login (agreety)."
