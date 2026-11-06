#!/bin/bash
# Creates a self-signed code signing certificate, "Passage Local Signing", in your
# login keychain. build.sh uses it when present.
#
# Why: ad-hoc signed builds get a new identity on every rebuild, so macOS forgets
# "Always Allow" for the app's Keychain items and asks for your password again.
# Signing every build with the same certificate keeps that permission.
#
# This certificate only identifies builds made on this Mac. It isn't trusted by
# other Macs and doesn't replace an Apple Developer ID for distribution.
set -euo pipefail

NAME="Passage Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists"; exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS="$(openssl rand -hex 16)"   # only protects the temporary .p12 file

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

# macOS's importer needs the older .p12 encryption algorithms.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$PASS" -out "$TMP/cert.p12"

# -T lets codesign use the key without asking each time.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in your login keychain"
