#!/bin/bash
# Checks what Passage has left on this Mac. Needs no root.
#
#   scripts/check-state.sh installed       helper installed and answering
#   scripts/check-state.sh uninstalled     no helper files, service or socket left
#   scripts/check-state.sh connected [full|split]
#                                          tunnel up, routes and DNS in place
#   scripts/check-state.sh disconnected    no tunnel, routes, DNS or secrets left
#
# Prints PASS/FAIL per check and exits non-zero if anything failed.

LABEL=io.github.neomis.passage.helper
HELPER=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
SOCK=/var/run/passage.sock
STATUS=/var/run/passage.status
RUN_DIR=/var/run/passage
LOCK_DIR=/var/run/passage.lock
SC_KEY=State:/Network/Service/passage
EXPECTED_VERSION=4

failures=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; failures=$((failures + 1)); }
info() { printf '  ---- %s\n' "$1"; }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi; }
check_not() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi; }

status_value() { sed -n "s/^$1=//p" "$STATUS" 2>/dev/null; }
sc_has() { printf 'show %s\n' "$1" | scutil | grep -qv 'No such key'; }
charon_running() { pgrep -f 'libexec/ipsec/charon' ; }
pppd_running() { pgrep -f "pppd file $RUN_DIR/ppp.options"; }
helper_version() { printf 'cmd=version\n\n' | nc -U -w 5 "$SOCK" 2>/dev/null | sed -n 's/^ok: //p'; }
route_via() { netstat -rn -f inet | awk -v d="$1" -v i="$2" '$1 == d && $NF == i { found = 1 } END { exit !found }'; }
any_route_via_ppp() { netstat -rn -f inet | awk '$NF ~ /^ppp/ { found = 1 } END { exit !found }'; }
socket_ok() {
  [[ -S "$SOCK" ]] || return 1
  [[ "$(stat -f '%u %Lp' "$SOCK")" == "$(id -u) 600" ]]
}

check_installed() {
  echo "Helper installed"
  check "helper binary at $HELPER" test -x "$HELPER"
  check "launchd plist at $PLIST" test -f "$PLIST"
  check "launchd service loaded" launchctl print "system/$LABEL"
  check "socket $SOCK is yours with mode 600" socket_ok
  local v; v="$(helper_version)"
  if [[ "$v" == "$EXPECTED_VERSION" ]]; then pass "helper answers, version $v"
  else fail "helper answers with version $EXPECTED_VERSION (got '${v:-nothing}')"; fi
}

check_uninstalled() {
  echo "Helper removed"
  check_not "no helper binary" test -e "$HELPER"
  check_not "no launchd plist" test -e "$PLIST"
  check_not "launchd service not loaded" launchctl print "system/$LABEL"
  check_not "no socket" test -e "$SOCK"
  check_disconnected
}

check_connected() {
  local mode="$1"
  echo "Connected"
  check "status file $STATUS" test -s "$STATUS"
  local id ifname ip
  id="$(status_value id)"; ifname="$(status_value ifname)"; ip="$(status_value ip)"
  info "profile id: ${id:-?}, interface: ${ifname:-?}, address: ${ip:-?}"
  if [[ -n "$ifname" ]] && ifconfig "$ifname" 2>/dev/null | grep -q "inet $ip "; then
    pass "$ifname is up with $ip"
  else
    fail "tunnel interface is up with the address in the status file"
  fi
  check "secrets directory $RUN_DIR exists while connected" test -d "$RUN_DIR"
  check "strongSwan (charon) running" charon_running
  check "pppd running" pppd_running
  check "IPv4 settings published to scutil" sc_has "$SC_KEY/IPv4"

  local full=no
  route_via 0/1 "$ifname" && route_via 128.0/1 "$ifname" && full=yes
  case "$mode" in
    full)  [[ $full == yes ]] && pass "all traffic routed through $ifname" || fail "all traffic routed through $ifname (0/1 and 128.0/1)";;
    split) [[ $full == no ]] && pass "default traffic stays off the VPN" || fail "default traffic stays off the VPN";;
    *)     info "send all traffic: $full";;
  esac

  local pub
  pub="$(curl -s -m 8 https://api.ipify.org 2>/dev/null)"
  info "public IP now: ${pub:-unknown}"
  printf 'show %s/DNS\n' "$SC_KEY" | scutil | sed -n 's/^ *[0-9]* : /  ---- DNS: /p'
}

check_disconnected() {
  echo "Disconnected and cleaned up"
  check_not "no status file" test -e "$STATUS"
  check_not "no secrets directory $RUN_DIR" test -e "$RUN_DIR"
  check_not "no lock left behind" test -e "$LOCK_DIR"
  check_not "strongSwan (charon) stopped" charon_running
  check_not "pppd stopped" pppd_running
  check_not "no routes through a ppp interface" any_route_via_ppp
  check_not "no Passage IPv4 settings in scutil" sc_has "$SC_KEY/IPv4"
  check_not "no Passage DNS settings in scutil" sc_has "$SC_KEY/DNS"
}

case "${1:-}" in
  installed)    check_installed ;;
  uninstalled)  check_uninstalled ;;
  connected)    check_connected "${2:-}" ;;
  disconnected) check_disconnected ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

echo
if (( failures )); then echo "$failures check(s) failed"; exit 1; fi
echo "All checks passed"
