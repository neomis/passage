#!/bin/bash
# Removes the Passage privileged helper. Must run as root.
set -uo pipefail

LABEL="io.github.neomis.passage.helper"
SOCKET="/var/run/passage.sock"

[[ $EUID -eq 0 ]] || { echo "error: run as root (sudo)" >&2; exit 1; }

# Disconnect first if connected.
if [[ -S "$SOCKET" ]]; then
  printf 'cmd=down\n\n' | nc -U "$SOCKET" >/dev/null 2>&1 || true
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$LABEL.plist" "/Library/PrivilegedHelperTools/$LABEL" "$SOCKET"
rm -rf "/Library/PrivilegedHelperTools/$LABEL.strongswan"
rm -rf /var/log/passage /var/run/passage /var/run/passage.status /var/run/passage.lock
echo "Passage helper removed"
