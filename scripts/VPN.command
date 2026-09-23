#!/bin/bash
# macOS menu: double-click, pick with ↑↓, Enter. Reads ROUTER / SSH_KEY from ../vpnctl.env if present.
cd "$(dirname "$0")" || exit 1

OPTS=("✅  روشن کردن VPN" "⛔️  خاموش کردن VPN" "📊  وضعیت" "🚪  خروج")
SEL=0
LAST=""

draw() {
    clear
    echo "┌──────────────────────────────────────┐"
    echo "│       VPN روتر — AmneziaWG 3.1       │"
    echo "└──────────────────────────────────────┘"
    [ -n "$LAST" ] && { echo "$LAST"; echo; }
    echo "  با ↑ ↓ انتخاب کن و Enter بزن (q = خروج)"
    echo
    for i in "${!OPTS[@]}"; do
        if [ "$i" -eq "$SEL" ]; then
            printf '   \e[7m %s \e[0m\n' "${OPTS[$i]}"
        else
            printf '    %s\n' "${OPTS[$i]}"
        fi
    done
}

run_action() {
    clear; echo
    case $1 in
        0) ../vpnctl on ;;
        1) ../vpnctl off ;;
        2) ../vpnctl status ;;
    esac
    LAST="── آخرین نتیجه بالا 👆 ($(date '+%H:%M:%S')) ──"
    echo
    read -rsn1 -p "هر کلیدی → برگشت به منو " _
}

while true; do
    draw
    IFS= read -rsn1 key || { clear; exit 0; }
    if [ "$key" = $'\e' ]; then
        read -rsn2 -t 1 rest
        key="$key$rest"
    fi
    case "$key" in
        $'\e[A') SEL=$(( (SEL + ${#OPTS[@]} - 1) % ${#OPTS[@]} )) ;;
        $'\e[B') SEL=$(( (SEL + 1) % ${#OPTS[@]} )) ;;
        ""|$'\n')
            if [ "$SEL" -eq 3 ]; then clear; echo "خداحافظ 👋  (این پنجره را ببند)"; exit 0; fi
            run_action "$SEL"
            ;;
        q|Q) clear; echo "خداحافظ 👋  (این پنجره را ببند)"; exit 0 ;;
    esac
done
