#!/bin/bash
# Install AmneziaWG 3.1 on an OpenWrt router and route the whole LAN through it.
#
#   ./install.sh <path-to-awg1.conf> [packages-dir]
#
# Environment:
#   ROUTER=root@192.168.1.1        router SSH address (default)
#   SSH_KEY=~/.ssh/id_ed25519      key for the router (optional; else password prompts)
#   TUNNEL_ADDR=10.8.1.2/32        your tunnel IP, "Address =" from the server's client config (required)
#   SPLIT_TUNNEL=1                 1 = Iranian destinations go direct (default), 0 = everything via VPN
#   SET_DNS=1                      1 = router DNS -> 1.1.1.1 via the tunnel (default), 0 = leave DNS alone
#   INSTALL_LUCI=1                 1 = add the web page Services -> AmneziaWG VPN (default), 0 = skip
#
# packages-dir defaults to the prebuilt folder matching the router's kernel, if one exists here;
# otherwise build your own with ./build/build-packages.sh and pass ./out/<...>.
set -e
cd "$(dirname "$0")"
CONF=$1; PKG=$2
ROUTER=${ROUTER:-root@192.168.1.1}
SPLIT_TUNNEL=${SPLIT_TUNNEL:-1}; SET_DNS=${SET_DNS:-1}; INSTALL_LUCI=${INSTALL_LUCI:-1}
[ -f "$CONF" ] || { sed -n '2,18p' "$0"; exit 1; }
[ -n "$TUNNEL_ADDR" ] || { echo "Set TUNNEL_ADDR (the 'Address =' of your client config), e.g. TUNNEL_ADDR=10.8.1.2/32"; exit 1; }
grep -qiE '^\s*(Address|DNS|MTU)\s*=' "$CONF" && { echo "Remove Address/DNS/MTU lines from $CONF (awg setconf rejects them; see awg1.conf.example)"; exit 1; }

OPTS=(-o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
[ -n "$SSH_KEY" ] && OPTS+=(-i "$SSH_KEY")
r()  { ssh "${OPTS[@]}" "$ROUTER" "$@"; }
cp_() { scp -O "${OPTS[@]}" "$@"; }

echo "[1/9] Checking router..."
KREL=$(r 'uname -r'); REL=$(r '. /etc/openwrt_release; echo "$DISTRIB_RELEASE $DISTRIB_TARGET"')
echo "      OpenWrt $REL, kernel $KREL"
if [ -z "$PKG" ]; then
  VER=${REL% *}; TGT=${REL#* }; PKG="packages/openwrt-$VER-${TGT%/*}-${TGT#*/}"
  [ -d "$PKG" ] || { echo "No prebuilt packages for this router ($PKG). Build them:"; echo "  ./build/build-packages.sh $VER ${TGT%/*} ${TGT#*/}"; echo "then: ./install.sh $CONF ./out/$VER-${TGT%/*}-${TGT#*/}"; exit 1; }
fi
KMOD=$(ls "$PKG"/kmod-amneziawg_*.ipk "$PKG"/*/kmod-amneziawg_*.ipk 2>/dev/null | head -1)
[ -n "$KMOD" ] || { echo "kmod-amneziawg ipk not found in $PKG"; exit 1; }
case "$(basename "$KMOD")" in kmod-amneziawg_"$KREL"+*) ;; *) echo "Kernel mismatch: router runs $KREL but package is $(basename "$KMOD"). Rebuild for your firmware."; exit 1;; esac

echo "[2/9] Copying packages and files..."
r 'mkdir -p /tmp/awg-pkg /etc/amneziawg && chmod 700 /etc/amneziawg'
cp_ $(find "$PKG" -name '*.ipk') "$ROUTER:/tmp/awg-pkg/"
cp_ router-files/awg3-up "$ROUTER:/usr/sbin/awg3-up"
cp_ router-files/amneziawg3.init "$ROUTER:/etc/init.d/amneziawg3"
cp_ "$CONF" "$ROUTER:/etc/amneziawg/awg1.conf"
if [ "$SPLIT_TUNNEL" = 1 ]; then cp_ router-files/bypass-v4.txt "$ROUTER:/etc/amneziawg/bypass-v4.txt"; else r 'rm -f /etc/amneziawg/bypass-v4.txt'; fi
NET=$(python3 -c "import ipaddress,sys;print(ipaddress.ip_interface(sys.argv[1]).network.supernet(new_prefix=24) if ipaddress.ip_interface(sys.argv[1]).network.prefixlen>24 else ipaddress.ip_interface(sys.argv[1]).network)" "$TUNNEL_ADDR")
r "printf 'ADDR=%s\nTUNNEL_NET=%s\n' '$TUNNEL_ADDR' '$NET' > /etc/amneziawg/awg3.env"

echo "[3/9] Installing packages..."
r 'cd /tmp/awg-pkg
   for d in kmod-crypto-hash kmod-crypto-kpp kmod-crypto-lib-chacha20 kmod-crypto-lib-poly1305 kmod-crypto-lib-chacha20poly1305 kmod-crypto-lib-curve25519 kmod-udptunnel4 kmod-udptunnel6; do
     opkg list-installed | grep -q "^$d " || { ls ${d}_*.ipk >/dev/null 2>&1 && opkg install --nodeps ${d}_*.ipk >/dev/null; }
   done
   opkg install kmod-amneziawg_*.ipk amneziawg-tools_*.ipk
   chmod 600 /etc/amneziawg/awg1.conf; chmod 755 /usr/sbin/awg3-up /etc/init.d/amneziawg3
   rm -rf /tmp/awg-pkg'

echo "[4/9] Firewall zone awgvpn (masquerade + MSS clamp, LAN -> awgvpn forwarding)..."
r 'if ! uci show firewall | grep -q "name=.awgvpn."; then
     Z=$(uci add firewall zone)
     uci set firewall.$Z.name=awgvpn; uci set firewall.$Z.input=REJECT
     uci set firewall.$Z.output=ACCEPT; uci set firewall.$Z.forward=REJECT
     uci set firewall.$Z.masq=1; uci set firewall.$Z.mtu_fix=1
     uci add_list firewall.$Z.device=awg1
     F=$(uci add firewall forwarding); uci set firewall.$F.src=lan; uci set firewall.$F.dest=awgvpn
     uci commit firewall; /etc/init.d/firewall reload >/dev/null 2>&1
   fi'

if [ "$SET_DNS" = 1 ]; then
  echo "[5/9] Router DNS -> 1.1.1.1 / 1.0.0.1 (routed through the tunnel by awg3-up)..."
  r 'uci set dhcp.@dnsmasq[0].noresolv=1; uci -q delete dhcp.@dnsmasq[0].server
     uci add_list dhcp.@dnsmasq[0].server=1.1.1.1; uci add_list dhcp.@dnsmasq[0].server=1.0.0.1
     uci commit dhcp; /etc/init.d/dnsmasq restart >/dev/null 2>&1'
else
  echo "[5/9] DNS left unchanged"; r 'echo DNS_SERVERS= >> /etc/amneziawg/awg3.env'
fi

if [ "$INSTALL_LUCI" = 1 ] && r 'test -d /www/luci-static/resources/view'; then
  echo "[6/9] Web page: LuCI -> Services -> AmneziaWG VPN..."
  cp_ router-files/luci/amneziawg3-status "$ROUTER:/usr/libexec/amneziawg3-status"
  cp_ router-files/luci/amneziawg3.js "$ROUTER:/www/luci-static/resources/view/amneziawg3.js"
  cp_ router-files/luci/luci-app-amneziawg3.menu.json "$ROUTER:/usr/share/luci/menu.d/luci-app-amneziawg3.json"
  cp_ router-files/luci/luci-app-amneziawg3.acl.json "$ROUTER:/usr/share/rpcd/acl.d/luci-app-amneziawg3.json"
  r 'chmod 755 /usr/libexec/amneziawg3-status; rm -f /tmp/luci-indexcache*; rm -rf /tmp/luci-modulecache; /etc/init.d/rpcd reload'
else
  echo "[6/9] Web page skipped (INSTALL_LUCI=0 or no LuCI on the router)"
fi

echo "[7/9] Router clock: NTP by IP first (no DNS needed) + tunnel restart after clock step..."
cp_ router-files/20-amneziawg-ntp "$ROUTER:/etc/hotplug.d/ntp/20-amneziawg-ntp"
r 'chmod 755 /etc/hotplug.d/ntp/20-amneziawg-ntp
   uci -q delete system.ntp.server
   for s in 162.159.200.1 162.159.200.123 0.openwrt.pool.ntp.org 1.openwrt.pool.ntp.org; do uci add_list system.ntp.server=$s; done
   uci set system.ntp.enabled=1; uci commit system; /etc/init.d/sysntpd restart'

echo "[8/9] Enabling and starting..."
r '/etc/init.d/amneziawg3 enable; /etc/init.d/amneziawg3 restart'
sleep 4
echo "[9/9] Status:"
r 'HS=$(awg show awg1 latest-handshakes | awk "{print \$2}"); [ -n "$HS" ] && [ "$HS" != 0 ] && echo "      handshake $(( $(date +%s) - HS ))s ago - tunnel is UP" || echo "      no handshake yet - check server peer / obfuscation params"'
echo "Done. Web: http://${ROUTER#*@} -> Services -> AmneziaWG VPN   CLI: ROUTER=$ROUTER ./vpnctl status"
