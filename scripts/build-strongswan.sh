#!/bin/bash
# Builds the strongSwan that Passage bundles: two self-contained programs,
# charon and swanctl, with only the features Passage uses and OpenSSL compiled in.
# Both target macOS 14+ and depend only on macOS itself.
# Output: build/strongswan/{charon,swanctl}. Skips work already done.
#
# Needs: Xcode Command Line Tools and pkg-config (brew install pkgconf).
# Downloads are pinned by SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."

SS_VERSION=6.1.0
SS_SHA256=fe6c97481298767213cfc2e9a1da29fdd8018d481ff4cb9cf0283099654f20d4
OSSL_VERSION=3.5.9   # LTS
OSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
MACOS_MIN=14.0
OUT=build/strongswan
WORK=build/strongswan-work
STAMP="$OUT/.built-$SS_VERSION-$OSSL_VERSION"

[[ -f "$STAMP" && -x "$OUT/charon" && -x "$OUT/swanctl" ]] && { echo "strongSwan $SS_VERSION already built"; exit 0; }
command -v pkg-config >/dev/null || { echo "error: pkg-config not found. Run: brew install pkgconf" >&2; exit 1; }

JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$WORK"
WORK_ABS="$(cd "$WORK" && pwd)"

fetch() {  # url file sha256
  if [[ ! -f "$2" ]]; then
    echo "Downloading $(basename "$2")"
    curl -sSfL -o "$2.part" "$1" && mv "$2.part" "$2"
  fi
  echo "$3  $2" | shasum -a 256 -c --quiet
}

# 1) OpenSSL's libcrypto, static, for macOS $MACOS_MIN+
OSSL="$WORK/openssl-$OSSL_VERSION"
if [[ ! -f "$OSSL/libcrypto.a" ]]; then
  fetch "https://github.com/openssl/openssl/releases/download/openssl-$OSSL_VERSION/openssl-$OSSL_VERSION.tar.gz" \
    "$WORK/openssl-$OSSL_VERSION.tar.gz" "$OSSL_SHA256"
  rm -rf "$OSSL" && tar xzf "$WORK/openssl-$OSSL_VERSION.tar.gz" -C "$WORK"
  echo "Building OpenSSL $OSSL_VERSION (a few minutes, once)"
  (
    cd "$OSSL"
    ./Configure "darwin64-$(uname -m)-cc" no-shared no-tests no-docs no-apps \
      -mmacosx-version-min=$MACOS_MIN >/dev/null
    make -s -j"$JOBS" build_libs >/dev/null 2>&1
  )
fi
OSSL_ABS="$WORK_ABS/openssl-$OSSL_VERSION"

# 2) strongSwan
fetch "https://download.strongswan.org/strongswan-$SS_VERSION.tar.bz2" \
  "$WORK/strongswan-$SS_VERSION.tar.bz2" "$SS_SHA256"
SRC="$WORK/strongswan-$SS_VERSION"
rm -rf "$SRC" && tar xjf "$WORK/strongswan-$SS_VERSION.tar.bz2" -C "$WORK"

# A directory holding only the static libcrypto, so the linker can't pick a dylib.
mkdir -p "$WORK/openssl-static"
ln -sf "$OSSL_ABS/libcrypto.a" "$WORK/openssl-static/libcrypto.a"

STAGE="$(pwd)/$WORK/stage"
rm -rf "$STAGE"
echo "Building strongSwan $SS_VERSION"
(
  cd "$SRC"
  ./configure --quiet \
    --prefix="$STAGE" \
    --disable-defaults --disable-shared --enable-static --enable-monolithic \
    --enable-charon --enable-swanctl --enable-ikev1 --enable-ikev2 \
    --enable-vici --enable-nonce --enable-openssl --enable-kdf \
    --enable-kernel-pfkey --enable-kernel-pfroute --enable-socket-default \
    --with-piddir=/var/run/passage \
    CFLAGS="-O2 -mmacosx-version-min=$MACOS_MIN -I$OSSL_ABS/include" \
    LDFLAGS="-mmacosx-version-min=$MACOS_MIN -L$WORK_ABS/openssl-static"
  make -s -j"$JOBS" >/dev/null
  make -s install >/dev/null
)

rm -rf "$OUT" && mkdir -p "$OUT"
cp "$STAGE/libexec/ipsec/charon" "$STAGE/sbin/swanctl" "$OUT/"
strip -x "$OUT/charon" "$OUT/swanctl" 2>/dev/null || true
touch "$STAMP"
echo "Built $OUT (strongSwan $SS_VERSION)"
