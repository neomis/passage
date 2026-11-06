# Passage

A macOS menu bar app for **L2TP/IPsec VPNs that the built-in macOS VPN can't connect to**, for example Cisco Meraki Client VPN servers that only accept AES128/SHA1/DH group 14.

The built-in macOS L2TP client doesn't let you choose IPsec algorithms. Linux users solve this with NetworkManager-l2tp's advanced IPsec options. Passage brings the same options to the Mac:

- **strongSwan**, bundled with the app, handles IPsec, using exactly the algorithms you configure
- macOS's own **pppd + L2TP plugin** handles L2TP and the login
- a small **privileged helper** applies the network changes, so connecting never asks for your password

## Features

- Menu bar status, connect/disconnect, connection timer
- Multiple connections, each with the same options as NetworkManager-l2tp:
  - **General:** gateway, username, password (saved or asked each time), NT domain
  - **IPsec:** pre-shared key, remote/local ID, phase 1 and 2 algorithms and lifetimes, legacy proposals, enforce UDP encapsulation, IP compression, disable PFS
  - **PPP:** allowed auth methods (PAP, CHAP, MSCHAP, MSCHAPv2, EAP), MPPE, BSD/Deflate/TCP header/protocol field/address-control compression, echo packets, MTU/MRU
  - **IPv4:** send all traffic or split tunnel with routes, DNS servers, search domains
- One-click **Cisco Meraki preset**
- Optional **Touch ID** check before connecting
- Open at login

Not supported yet: certificate (TLS) authentication for the user or machine, IPv6.

## Requirements

- macOS 14 or later, Apple silicon (Intel builds aren't available yet; building from source on Intel should work but is untested)
- Nothing else. Passage includes its own strongSwan.

## Install

### Homebrew

```bash
brew install --cask neomis/tap/passage
```

### Download

Get `Passage-<version>-arm64.zip` from [Releases](https://github.com/neomis/passage/releases), unzip it, and move **Passage** to Applications.

Passage isn't notarized by Apple yet, so macOS blocks the first launch. Open **System Settings → Privacy & Security** and click **Open Anyway** next to the message about Passage.

### Build from source

```bash
git clone https://github.com/neomis/passage.git
cd passage
./build.sh --install
```

This needs the Xcode Command Line Tools (`xcode-select --install`) and pkg-config (`brew install pkgconf`). The first build also downloads and compiles strongSwan and OpenSSL, which takes about a minute (`scripts/build-strongswan.sh`, with pinned checksums). Later builds reuse that.

Optional: `scripts/make-signing-cert.sh` creates a local signing certificate, which `build.sh` then uses, so every build you make has the same signing identity. Builds are ad-hoc signed without it.

### First run

Open **Passage** from Applications. Click the lamp in the menu bar and choose **Install Helper…** (one administrator prompt). Then open **Settings…**, add a connection, and connect.

## Setting up a connection

Copy the values from your VPN provider or a working Linux NetworkManager connection. On Linux you can list them with:

```bash
nmcli -g vpn.data connection show "<connection name>" | tr ',' '\n'
```

| NetworkManager (`vpn.data`) | Passage |
|---|---|
| `gateway` | General → Gateway |
| `user` | General → Username |
| `ipsec-psk` | IPsec → Pre-shared key |
| `ipsec-ike` | IPsec → Phase 1 algorithms |
| `ipsec-esp` | IPsec → Phase 2 algorithms |
| `ipsec-pfs = no` | IPsec → Disable PFS |
| `ipsec-forceencaps = yes` | IPsec → Enforce UDP encapsulation |
| `refuse-chap = yes` etc. | PPP → untick CHAP etc. |
| `mtu`, `mru` | PPP → MTU, MRU |

Algorithms use strongSwan's format, e.g. `aes128-sha1-modp2048` for phase 1 and `aes128-sha1` for phase 2.

**Cisco Meraki:** enter the gateway (`*.dynamic-m.com`), your Meraki username and password, and the shared secret, then click **Apply Cisco Meraki preset**.

## How it works

```
Passage.app ──(Unix socket, your user only)──▶ passage-helper (root, launchd)
                                                 ├─ strongSwan charon: IKEv1 + ESP transport mode
                                                 ├─ pppd + macOS L2TP plugin: L2TP, PPP login
                                                 └─ routes and DNS (route, scutil)
```

- The helper is installed at `/Library/PrivilegedHelperTools/io.github.neomis.passage.helper` and started on demand by launchd (`/Library/LaunchDaemons/io.github.neomis.passage.helper.plist`).
- Its socket, `/var/run/passage.sock`, is owned by the installing user with mode `0600`, so only that user can send it commands.
- Every value the app sends is checked against a strict pattern before it reaches a config file.
- Passwords and pre-shared keys are kept by the helper in root-only files under `/Library/Application Support/io.github.neomis.passage.helper/secrets`, as Linux NetworkManager does. The app hands a secret over when you save it and never reads it back.
- Each saved secret is tied to the gateway and username it was saved with, and the helper only uses it for that server. Change either and Passage asks for the password again. This keeps other programs running as you from sending your password to a different server through the helper.
- Why not the Keychain: for apps without an Apple developer Team ID, macOS ties Keychain access to each exact build, so every update would ask for your password again.
- While connected, the secrets are also in root-only files under `/var/run/passage`, which are deleted when you disconnect.
- Logs: `/var/log/passage/` (Settings → Logs).

## Testing

`scripts/check-state.sh` checks what Passage has left on the system, with no root needed:

```bash
scripts/check-state.sh installed       # helper installed and answering
scripts/check-state.sh connected full  # tunnel, routes and DNS in place (or: split)
scripts/check-state.sh disconnected    # nothing left behind after disconnecting
scripts/check-state.sh uninstalled     # helper fully removed
```

The app icon is drawn by `scripts/make-icon.swift`. Run `swift scripts/make-icon.swift` to regenerate `Resources/AppIcon.icns`.

## Security notes

- Passage bundles strongSwan 6.1.0 with OpenSSL 3.5 (LTS), built with only the features it uses. Installing the helper copies it to `/Library/PrivilegedHelperTools/io.github.neomis.passage.helper.strongswan`, owned by root, so nothing running as your user can change what the helper runs as root.
- L2TP/IPsec with a pre-shared key and SHA1 is an old protocol. Use Passage when it's what your network requires, not as a first choice.

## Uninstall

In Settings, use the helper menu (bottom left) → **Remove Helper…**, then delete `/Applications/Passage.app`. To remove saved data:

```bash
rm -rf ~/Library/Application\ Support/Passage
```

Removing the helper also deletes the saved passwords and pre-shared keys.

## License

MIT
