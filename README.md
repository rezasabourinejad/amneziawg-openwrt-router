# AmneziaWG 3.1 for OpenWrt routers

**Whole-home AmneziaWG 3.1 VPN on an OpenWrt router, in the kernel, with a zero-overhead split tunnel
(Iranian IPs go direct) and a DNS fix. Prebuilt for Google WiFi, build script for any router.**

[فارسی](README.fa.md)

Every device on your Wi-Fi/LAN (phones, laptops, Xbox/PlayStation, smart TVs) goes through an
[AmneziaWG](https://github.com/amnezia-vpn) tunnel without any app on the device. AmneziaWG is WireGuard
with traffic obfuscation, built to get past DPI (Iran, Russia, China…).

## Why this exists

- **AWG 3.1 packages for OpenWrt did not exist.** Protocol 3.1 (header protection, random padding and
  trailers) needs a matching kernel module; the Amnezia server app speaks 3.1, older router builds don't.
- **Games and calls die on filtered networks.** On an Iranian home line we measured ~30–35 % UDP packet
  loss to game servers (AWS Frankfurt) and SNI-based blocking of the game's login server. Through this
  tunnel: **0 % loss**, login works, ping +~10 ms.
- **The router, not every device.** Consoles and TVs can't run a VPN app.

## Features

| | |
|---|---|
| Kernel-space AWG 3.1 | `kmod-amneziawg` + `awg` tools, built with the official OpenWrt SDK. No firmware changes. |
| Whole LAN via VPN | Policy routing (`ip rule iif br-lan → table 110`). The router itself stays reachable, no lock-out. |
| Split tunnel | All IPv4 prefixes of a country (default **Iran**, from RIPE) go direct via `throw` routes. Pure FIB lookup: no firewall marks, no conntrack; measured **no RTT change**. |
| DNS fix | Router DNS → 1.1.1.1 *through the tunnel*, so filtered domains (X/Twitter, Discord…) resolve correctly. Falls back to direct when the VPN is off. |
| Pinned source port | Some ISPs hash their upstream per flow; a fixed `ListenPort` keeps a good path across restarts. |
| Web page | **LuCI → Services → AmneziaWG VPN**: live status (handshake, tunnel ping, traffic, WAN cable) and On / Off / start-at-boot buttons, from any device, even a phone. |
| `vpnctl` | `on / off / restart / status` from your laptop over SSH (+ a double-click macOS menu). |

## Compatibility

| Router | OpenWrt | Target | Packages |
|---|---|---|---|
| Google WiFi (Gale, AC-1304) | 23.05.4 | `ipq40xx/chromium` | **prebuilt**, tested daily |
| anything else | 23.05.x (and similar) | any | run `build/build-packages.sh` (~10 min in Docker) |

A kernel module only loads on the **exact** kernel it was built for. Find yours with
`cat /etc/openwrt_release` on the router. After a firmware upgrade, rebuild.

## Quick start

**1. Server** – an AmneziaWG 3.1 server (e.g. Amnezia app → self-hosted on a VPS). See
[docs/server-setup.md](docs/server-setup.md).

**2. Client config for the router** – export a *new* client as AmneziaWG `.conf`, then remove the
`Address`, `DNS`, `MTU` lines. Keep the `Address` value, you need it below. Template:
[`router-files/awg1.conf.example`](router-files/awg1.conf.example).

**3. Packages** – Google WiFi on 23.05.4: nothing to do. Other routers:

```sh
./build/build-packages.sh 23.05.5 ramips mt7621     # <version> <target> <subtarget>
```

**4. Install** (from a Mac/Linux machine on the router's LAN, SSH access as root):

```sh
ROUTER=root@192.168.1.1 TUNNEL_ADDR=10.8.1.2/32 ./install.sh ./awg1.conf
# other router:  ... ./install.sh ./awg1.conf ./out/23.05.5-ramips-mt7621
# options: SPLIT_TUNNEL=0 (everything via VPN), SET_DNS=0 (keep your DNS), INSTALL_LUCI=0 (no web page),
#          SSH_KEY=~/.ssh/key
```

**5. Control**

From any device on the LAN: open `http://<router-ip>` → **Services → AmneziaWG VPN**. Turn OFF puts the
whole network back on the plain internet in a second, a handy escape hatch when something is wrong.
The page only runs a tiny read-only status script while it is open (refresh every 10 s); it has no
background process and no effect on tunnel traffic. Its rpcd ACL allows only that script and
start/stop/enable/disable of this one service.

From a laptop:

```sh
cp vpnctl.env.example vpnctl.env    # set ROUTER / SSH_KEY once
./vpnctl status                     # handshake, traffic, bypass routes, your public IP
./vpnctl off                        # whole home goes direct
./vpnctl on
```

macOS: double-click `scripts/VPN.command` for an arrow-key menu.

## How it works

```
LAN device ──► router (br-lan)
                 │  ip rule: iif br-lan → table 110
                 ▼
            table 110:  throw <Iranian prefixes, RFC1918, CGNAT>  ──► main table ──► WAN (direct)
                        default dev awg1  ──► AmneziaWG 3.1 (UDP, obfuscated) ──► VPS ──► internet
```

- `router-files/awg3-up` brings the tunnel up, fills table 110 in one `ip -batch` (~1 s for 1 700 routes)
  and host-routes the DNS servers via `awg1`. Settings: `/etc/amneziawg/awg3.env`.
- The rule is `iif br-lan`, **not** `from 192.168.x.0/24`: the latter also captures the router's own
  replies to the LAN and you lose SSH.
- Only the router's forwarding path is tunneled; traffic from the router itself goes direct.

### Split tunnel

- List: `router-files/bypass-v4.txt`. Refresh or switch country:
  `COUNTRY=IR ./build/update-bypass-list.sh --deploy`.
- Your own additions: `/etc/amneziawg/bypass-extra.txt` on the router (never overwritten), then `vpnctl restart`.
- Limit: a local site hosted behind a foreign CDN has a foreign IP and goes through the VPN (it still works).

### Pinned ListenPort

Some ISPs (seen on Asiatech, Iran) spread international traffic over several upstreams **per flow**, with
the UDP source port in the hash. With a random port the tunnel landed on a ~195 ms path; ports
40001–40008 gave 77–87 ms. So `ListenPort` is fixed in `awg1.conf`. If your tunnel ping jumps, try other
ports live, without dropping the tunnel:

```sh
awg set awg1 listen-port 40011; sleep 2; ping -c 10 10.8.1.0     # server tunnel IP (Amnezia: 10.8.1.0)
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| no internet at all, VPN or not | Check the web page's *Internet cable (WAN)* row. A loose cable or the wrong port (Google WiFi: the one with the globe icon) looks exactly like a VPN outage. |
| no handshake | Obfuscation params must match the server **exactly**; peer present on server (`awg show`)? UDP port open on VPS? |
| ping works, big pages stall | MTU: lower `MTU` in `awg3.env` by 40, `vpnctl restart` (AWG 3.1 padding varies; 1256 is safe). |
| X/Twitter/Discord don't open, Telegram does | Poisoned DNS: `ip route get 1.1.1.1` on the router must show `dev awg1`. Toggle Wi-Fi on the phone (negative DNS cache). |
| `opkg` refuses kmod / "kernel mismatch" | Packages are for another kernel; rebuild with `build/build-packages.sh`. |
| locked out of the router | IPv6 link-local still works: `ping6 ff02::1%en0`, then `ssh root@fe80::…%en0`. Or SSH right after power-on. |

## Warnings

- **Firmware upgrade = rebuild.** The kmod is pinned to the kernel's vermagic.
- Don't blindly `opkg upgrade` on a router with custom packages.
- Everything runs as root on your router; read the scripts first. No warranty.

## Credits & license

- [amnezia-vpn](https://github.com/amnezia-vpn): AmneziaWG kernel module, tools, server.
- [Slava-Shchipunov/awg-openwrt](https://github.com/Slava-Shchipunov/awg-openwrt): OpenWrt package
  definitions this build uses (bumped to 3.1). For AWG 1.x/2.x on many routers, use that project.
- Scripts in this repo: MIT. Prebuilt `.ipk` files are compiled, unmodified from upstream sources, and keep
  their upstream licenses (kernel module: GPL-2.0, tools: GPL-2.0). `build/build-packages.sh` reproduces them
  from source. The bundled dependency kmods (crypto, udptunnel) are built from the same OpenWrt 23.05.4 SDK, for routers that cannot reach the OpenWrt package feeds.
