#!/bin/bash
# Build kmod-amneziawg + amneziawg-tools (AmneziaWG 3.1) for ANY OpenWrt target, inside Docker.
# Runs on any x86_64 Linux/macOS machine with Docker (a cheap VPS works well; ~10 min, ~3 GB disk).
#
#   ./build/build-packages.sh <openwrt-version> <target> <subtarget>
#   ./build/build-packages.sh 23.05.4 ipq40xx chromium        # Google WiFi (Gale)
#   ./build/build-packages.sh 23.05.5 ramips mt7621           # e.g. many Xiaomi / TP-Link MT7621 routers
#   ./build/build-packages.sh 23.05.5 mediatek filogic        # e.g. Cudy / GL.iNet MT798x
#
# Find your values on the router:   cat /etc/openwrt_release   (DISTRIB_RELEASE, DISTRIB_TARGET)
# Output: ./out/<version>-<target>-<subtarget>/*.ipk  (kmod-amneziawg, amneziawg-tools, needed kmod deps)
#
# Versions of the AmneziaWG sources can be overridden:
#   KMOD_VERSION=3.1.20260906 TOOLS_VERSION=3.1.20260812 ./build/build-packages.sh ...
# Upstream tags that are not valid opkg versions (e.g. v3.1.20261113-02) go in KMOD_SRC_TAG:
#   KMOD_VERSION=3.1.20261113.2 KMOD_SRC_TAG=v3.1.20261113-02 ./build/build-packages.sh ...
set -e
[ $# -eq 3 ] || { sed -n '2,15p' "$0"; exit 1; }
VER=$1; TARGET=$2; SUB=$3
KMOD_VERSION=${KMOD_VERSION:-3.1.20261113.2}
KMOD_SRC_TAG=${KMOD_SRC_TAG:-v3.1.20261113-02}
TOOLS_VERSION=${TOOLS_VERSION:-3.1.20260812}
cd "$(dirname "$0")/.."
OUT="$PWD/out/$VER-$TARGET-$SUB"; mkdir -p "$OUT" "$PWD/out/cache"

docker run --rm --platform linux/amd64 \
  -e VER="$VER" -e TARGET="$TARGET" -e SUB="$SUB" \
  -e KMOD_VERSION="$KMOD_VERSION" -e KMOD_SRC_TAG="$KMOD_SRC_TAG" -e TOOLS_VERSION="$TOOLS_VERSION" \
  -v "$OUT":/out -v "$PWD/out/cache":/cache \
  debian:bookworm-slim bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential python3 python3-setuptools \
  python3-pyelftools git wget xz-utils zstd file rsync unzip gawk perl ca-certificates procps \
  curl libncurses-dev >/dev/null
BASE="https://downloads.openwrt.org/releases/$VER/targets/$TARGET/$SUB"
SDK=$(curl -fsSL "$BASE/" | grep -oE "openwrt-sdk-[^\"<>]+\.tar\.(xz|zst)" | head -1)
[ -n "$SDK" ] || { echo "SDK not found at $BASE"; exit 1; }
cd /cache
[ -f "$SDK" ] || { echo "downloading $SDK"; wget -q "$BASE/$SDK"; }
DIR=${SDK%.tar.*}; [ -d "$DIR" ] || tar -xf "$SDK"
cd "$DIR"
rm -rf /tmp/awg && git clone -q --depth 1 https://github.com/Slava-Shchipunov/awg-openwrt.git /tmp/awg
rm -rf package/kmod-amneziawg package/amneziawg-tools
cp -r /tmp/awg/kmod-amneziawg /tmp/awg/amneziawg-tools package/
rm -rf package/kmod-amneziawg/patches package/amneziawg-tools/patches
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$KMOD_VERSION/" package/kmod-amneziawg/Makefile
[ -n "$KMOD_SRC_TAG" ] && sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=$KMOD_SRC_TAG/" package/kmod-amneziawg/Makefile
grep -E "^PKG_(VERSION|SOURCE_VERSION)" package/kmod-amneziawg/Makefile
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$TOOLS_VERSION/" package/amneziawg-tools/Makefile
sed -i "s/^PKG_SOURCE_VERSION:=.*/PKG_SOURCE_VERSION:=v\$(PKG_VERSION)/" package/amneziawg-tools/Makefile
printf "CONFIG_PACKAGE_kmod-amneziawg=m\nCONFIG_PACKAGE_amneziawg-tools=y\n" > .config
make defconfig >/dev/null
for p in amneziawg-tools kmod-amneziawg; do
  echo "== building $p"
  make package/$p/{download,prepare} >/dev/null
  make package/$p/compile -j"$(nproc)" >/tmp/$p.log 2>&1 || { tail -40 /tmp/$p.log; exit 1; }
done
find bin -name "*.ipk" \( -name "kmod-amneziawg_*" -o -name "amneziawg-tools_*" -o -name "kmod-crypto-*" \
  -o -name "kmod-udptunnel*" \) -exec cp {} /out/ \;
ls -la /out
'
echo "done -> $OUT"
