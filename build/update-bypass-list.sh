#!/bin/bash
# Regenerate router-files/bypass-v4.txt from RIPE (all IPv4 prefixes registered to a country)
# and optionally push it to the router.
#   COUNTRY=IR ./build/update-bypass-list.sh            # regenerate only
#   COUNTRY=IR ./build/update-bypass-list.sh --deploy   # + copy to router and restart tunnel
# Any ISO country code works (COUNTRY=CN, RU, TR ...). Manual extras: /etc/amneziawg/bypass-extra.txt on the router.
set -e
cd "$(dirname "$0")/.."
COUNTRY=${COUNTRY:-IR}; OUT=router-files/bypass-v4.txt; TMP=$(mktemp)
curl -sf -m 90 "https://stat.ripe.net/data/country-resource-list/data.json?resource=$COUNTRY&v4_format=prefix" -o "$TMP"
python3 - "$TMP" "$OUT" "$COUNTRY" <<'PY'
import json, sys, ipaddress, datetime
d = json.load(open(sys.argv[1]))["data"]["resources"]["ipv4"]
agg = list(ipaddress.collapse_addresses(ipaddress.ip_network(x) for x in d))
assert len(agg) > 20, "RIPE list looks wrong"
with open(sys.argv[2], "w") as f:
    f.write("# IPv4 prefixes that bypass the tunnel (go straight out WAN). One CIDR per line.\n")
    f.write(f"# Source: RIPE country-resource-list {sys.argv[3]} (aggregated). Regenerate: build/update-bypass-list.sh\n")
    f.write(f"# Generated: {datetime.date.today()}  prefixes: {len(agg)}\n")
    f.write("\n".join(map(str, agg)) + "\n")
print(f"{len(agg)} prefixes -> {sys.argv[2]}")
PY
rm -f "$TMP"
[ "$1" = "--deploy" ] || exit 0
[ -f vpnctl.env ] && . ./vpnctl.env
ROUTER=${ROUTER:-root@192.168.1.1}; OPTS=(-o LogLevel=ERROR); [ -n "$SSH_KEY" ] && OPTS+=(-i "${SSH_KEY/#\~/$HOME}")
scp -O "${OPTS[@]}" "$OUT" "$ROUTER:/etc/amneziawg/bypass-v4.txt"
./vpnctl restart
