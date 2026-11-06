#!/bin/bash
# Installs the Passage privileged helper. Must run as root.
#   install-helper.sh <uid>
# <uid> is the user allowed to talk to the helper (the socket is theirs, mode 0600).
# The Passage app runs this for you with an administrator prompt.
set -euo pipefail

LABEL="io.github.neomis.passage.helper"
HELPER_DST="/Library/PrivilegedHelperTools/$LABEL"
SS_DST="/Library/PrivilegedHelperTools/$LABEL.strongswan"   # Passage's own strongSwan
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SOCKET="/var/run/passage.sock"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

[[ $EUID -eq 0 ]] || { echo "error: run as root (sudo)" >&2; exit 1; }
USER_ID="${1:-}"
[[ "$USER_ID" =~ ^[0-9]+$ && "$USER_ID" -ne 0 ]] || { echo "usage: $0 <uid of the user who will use Passage>" >&2; exit 1; }
id -u "$USER_ID" >/dev/null 2>&1 || dscl . -search /Users UniqueID "$USER_ID" | grep -q . || { echo "error: no user with uid $USER_ID" >&2; exit 1; }

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$SOCKET"

install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$SRC_DIR/passage-helper" "$HELPER_DST"
# The helper runs these as root, so they must be root-owned and not writable by anyone else.
rm -rf "$SS_DST"
install -d -o root -g wheel -m 755 "$SS_DST"
install -o root -g wheel -m 755 "$SRC_DIR/strongswan/charon" "$SRC_DIR/strongswan/swanctl" "$SS_DST/"
# A downloaded app carries the quarantine mark; the installed copies are trusted by the admin prompt.
xattr -cr "$HELPER_DST" "$SS_DST" 2>/dev/null || true
install -d -o root -g wheel -m 755 /var/log/passage

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>$HELPER_DST</string></array>
  <key>inetdCompatibility</key>
  <dict><key>Wait</key><false/></dict>
  <key>Sockets</key>
  <dict>
    <key>Listeners</key>
    <dict>
      <key>SockPathName</key><string>$SOCKET</string>
      <key>SockPathMode</key><integer>384</integer>
      <key>SockPathOwner</key><integer>$USER_ID</integer>
    </dict>
  </dict>
  <!-- Keep strongSwan and pppd running after the helper replies. -->
  <key>AbandonProcessGroup</key><true/>
  <key>StandardErrorPath</key><string>/var/log/passage/helper.log</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST"

for _ in 1 2 3 4 5 6 7 8 9 10; do [[ -S "$SOCKET" ]] && break; sleep 0.3; done
[[ -S "$SOCKET" ]] || { echo "error: helper socket did not appear" >&2; exit 1; }
owner="$(stat -f %u "$SOCKET")"; mode="$(stat -f %Lp "$SOCKET")"
if [[ "$owner" != "$USER_ID" || "$mode" != "600" ]]; then
  echo "error: socket has owner $owner mode $mode (expected $USER_ID, 600); uninstalling" >&2
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$HELPER_DST" "$SOCKET"
  rm -rf "$SS_DST"
  exit 1
fi
echo "Passage helper installed"
