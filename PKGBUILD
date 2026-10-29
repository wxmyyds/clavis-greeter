# Maintainer: wxmyyds <wxmyyds@users.noreply.github.com>
pkgname=clavis-greeter
pkgver=1.0.0
pkgrel=1
pkgdesc='Clavis-styled graphical greeter for greetd, running on niri + quickshell'
arch=('any')
url="https://github.com/wxmyyds/clavis-greeter"
license=('MIT')
depends=('bash' 'python' 'niri' 'quickshell' 'greetd')
provides=('greetd-greeter')
backup=('etc/clavis-greeter.conf')
options=('!strip')

source=(
    'build.sh'
    'setup.sh'
    'backend/greeter-backend.py'
    'session/clavis-greeter-session'
    'overrides/shell.qml'
    'overrides/ClavisLock.qml'
    'overrides/SystemIdentityService.qml'
    'overrides/AvatarService.qml'
    'overrides/WallpaperService.qml'
)
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP' 'SKIP')

package() {
    install -d "$pkgdir/usr/lib/clavis-greeter/overrides" \
               "$pkgdir/usr/lib/clavis-greeter/backend" \
               "$pkgdir/usr/lib/clavis-greeter/session" \
               "$pkgdir/usr/bin" \
               "$pkgdir/etc"

    # Greeter sources (the shell tree itself is generated at setup time from the
    # installed Clavis shell, so it is not shipped in the package).
    install -m755 "$srcdir/build.sh" "$pkgdir/usr/lib/clavis-greeter/build.sh"
    install -m755 "$srcdir/greeter-backend.py" "$pkgdir/usr/lib/clavis-greeter/backend/"
    install -m755 "$srcdir/clavis-greeter-session" "$pkgdir/usr/lib/clavis-greeter/session/"
    install -m644 "$srcdir"/*.qml "$pkgdir/usr/lib/clavis-greeter/overrides/"

    # Commands.
    install -m755 "$srcdir/clavis-greeter-session" "$pkgdir/usr/bin/clavis-greeter-session"
    install -m755 "$srcdir/setup.sh" "$pkgdir/usr/bin/clavis-greeter-setup"

    cat > "$pkgdir/usr/bin/clavis-greeter-build" <<'EOF'
#!/bin/bash
exec /usr/lib/clavis-greeter/build.sh /usr/lib/clavis-greeter/shell
EOF
    chmod 755 "$pkgdir/usr/bin/clavis-greeter-build"

    cat > "$pkgdir/etc/clavis-greeter.conf" <<'EOF'
# Account the greeter logs in as (single-user desktop).
# Run `sudo clavis-greeter-setup <user>` to fill this in.
CLAVIS_GREETER_USER=
EOF
    chmod 644 "$pkgdir/etc/clavis-greeter.conf"
}
