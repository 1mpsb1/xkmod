#!/data/data/com.termux/files/usr/bin/bash
set -e

# Data directory
XK_DIR="$HOME/.xray-knife"
mkdir -p "$XK_DIR"
cd "$XK_DIR" || exit 1

# Target dir for short commands
BIN_DIR="${PREFIX:-$HOME/.local}/bin"
mkdir -p "$BIN_DIR"

# Dependencies
for pkg in wget unzip curl; do
    command -v "$pkg" >/dev/null 2>&1 || pkg install -y "$pkg"
done

# Download and unpack xray-knife
echo "Downloading Xray-Knife..."
wget -O Xray-knife-android-arm64-v8a.zip \
    https://github.com/lilendian0x00/xray-knife/releases/latest/download/Xray-knife-android-arm64-v8a.zip

echo "Unpacking Xray-Knife..."
unzip -o Xray-knife-android-arm64-v8a.zip
chmod +x xray-knife
rm -f Xray-knife-android-arm64-v8a.zip

# update.sh
echo "[0/4] Writing scripts..."
cat <<'EOF' > update.sh
#!/data/data/com.termux/files/usr/bin/bash

XK_DIR="$HOME/.xray-knife"
URLS_FILE="$XK_DIR/urls.txt"
CONFIGS_FILE="$XK_DIR/configs_filtered.txt"
CONFIGS_OLD="$XK_DIR/configs_filtered.old"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

if [ ! -f "$URLS_FILE" ]; then
    log "ERROR: $URLS_FILE not found."
    exit 1
fi

log "=== Update started ==="
log "Sources: $URLS_FILE"
echo ""

> "$CONFIGS_FILE"
TOTAL_URLS=0
SUCCESS_URLS=0

while IFS= read -r url; do
    [ -z "$url" ] && continue
    case "$url" in \#*) continue ;; esac

    TOTAL_URLS=$((TOTAL_URLS + 1))
    before=$(wc -l < "$CONFIGS_FILE" 2>/dev/null || echo 0)

    echo "[$(date '+%H:%M:%S')]  $url"

    curl -s --max-time 30 -L "$url" \
        | grep -a -oE 'vless://[a-zA-Z0-9._~:/?#@!$&()*+,;=%-]+' \
        >> "$CONFIGS_FILE"

    after=$(wc -l < "$CONFIGS_FILE" 2>/dev/null || echo 0)
    got=$((after - before))

    if [ "$got" -gt 0 ]; then
        echo "           +$got configs"
        SUCCESS_URLS=$((SUCCESS_URLS + 1))
    else
        echo "           (empty or unreachable)"
    fi
done < "$URLS_FILE"

echo ""
log "Fetched from $SUCCESS_URLS / $TOTAL_URLS sources"
log "Raw lines: $(wc -l < "$CONFIGS_FILE")"

log "Filtering..."

sort -u "$CONFIGS_FILE" \
    | grep -a -E '^vless://[^@]+@[a-zA-Z0-9.-]+:[0-9]+' \
    | grep -a -E 'security=(reality|tls)' \
    > "${CONFIGS_FILE}.tmp" 2>/dev/null || true

if [ "$(wc -l < "${CONFIGS_FILE}.tmp")" -lt 50 ]; then
    log "Not enough reality/tls, using all valid"
    sort -u "$CONFIGS_FILE" \
        | grep -a -E '^vless://[^@]+@[a-zA-Z0-9.-]+:[0-9]+' \
        > "${CONFIGS_FILE}.tmp" 2>/dev/null || true
fi

[ -s "${CONFIGS_FILE}.tmp" ] && mv "${CONFIGS_FILE}.tmp" "$CONFIGS_FILE"

FINAL_COUNT=$(wc -l < "$CONFIGS_FILE")

if [ "$FINAL_COUNT" -lt 1 ]; then
    log "ERROR: pool is empty. $CONFIGS_FILE not updated."
    exit 1
fi

log "Final pool: $FINAL_COUNT configs"
echo ""

if [ -f "$CONFIGS_OLD" ] && cmp -s "$CONFIGS_FILE" "$CONFIGS_OLD"; then
    log "Configs unchanged since last run."
else
    log "Configs changed — saving copy to $CONFIGS_OLD"
    cp "$CONFIGS_FILE" "$CONFIGS_OLD"
fi

echo ""
log "=== Update finished ==="
log "Pool file: $CONFIGS_FILE"
log "Compare copy: $CONFIGS_OLD"
EOF

# check-configs.sh
echo "[1/4] Writing scripts..."
cat <<'EOF' > check-configs.sh
#!/data/data/com.termux/files/usr/bin/bash

XK_DIR="$HOME/.xray-knife"
INPUT_FILE="$XK_DIR/configs_filtered.txt"
OUTPUT_FILE="$XK_DIR/valid_configs.txt"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

if [ ! -f "$INPUT_FILE" ]; then
    log "ERROR: $INPUT_FILE not found. Run 'uxk' first to fetch configs."
    exit 1
fi

log "=== Config check started ==="
log "Input:  $INPUT_FILE"
log "Output: $OUTPUT_FILE"
echo ""

"$XK_DIR/xray-knife" http -f "$INPUT_FILE" \
    --prescan \
    --prescan-timeout 2000 \
    --prescan-workers 256 \
    -t 25 \
    --check-preset global \
    --url-success-threshold 0.5 \
    --dedup-semantic \
    --max-passed 50 \
    -o "$OUTPUT_FILE"

RESULT=$?

if [ $RESULT -ne 0 ]; then
    log "ERROR: xray-knife http exited with code $RESULT"
    exit 1
fi

if [ ! -s "$OUTPUT_FILE" ]; then
    log "WARNING: output file is empty — no configs passed the check."
    exit 1
fi

VALID_COUNT=$(wc -l < "$OUTPUT_FILE")
log "=== Check finished ==="
log "Valid configs: $VALID_COUNT"
log "Saved to: $OUTPUT_FILE"
EOF

# proxyw.sh
echo "[2/4] Writing scripts..."
cat <<'EOF' > proxyw.sh
#!/data/data/com.termux/files/usr/bin/bash

PROXY_USER="user"
PROXY_PASS="pass"
PROXY_HOST="127.0.0.1"
PROXY_PORT="9999"

PROXY_URL="socks5://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}"

export http_proxy="$PROXY_URL"
export https_proxy="$PROXY_URL"
export all_proxy="$PROXY_URL"
export HTTP_PROXY="$PROXY_URL"
export HTTPS_PROXY="$PROXY_URL"
export ALL_PROXY="$PROXY_URL"

echo "[+] Proxy set for session:"
echo "    $PROXY_URL"
echo ""

exec $SHELL
EOF

# xray-start.sh
echo "[3/4] Writing scripts..."
cat <<'EOF' > xray-start.sh
#!/data/data/com.termux/files/usr/bin/bash

XK_DIR="$HOME/.xray-knife"

PROXY_USER="user"
PROXY_PASS="pass"
PROXY_HOST="127.0.0.1"
PROXY_PORT="9999"

INBOUND_URL="socks://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}"
CONFIGS_FILE="$XK_DIR/valid_configs.txt"
ROTATE_SECONDS=7200

cd "$XK_DIR" || exit 1

if [ ! -s "$CONFIGS_FILE" ]; then
    echo "ERROR: $CONFIGS_FILE is missing or empty. Run 'xkmod-c' first."
    exit 1
fi

./xray-knife proxy inbound -f "$CONFIGS_FILE" \
  --inbound-config "$INBOUND_URL" \
  --rotate "$ROTATE_SECONDS"
EOF

echo "[4/4] Writing scripts..."
chmod +x update.sh check-configs.sh proxyw.sh xray-start.sh

# Data files
touch configs_filtered.txt configs_filtered.old

if [ ! -f urls.txt ]; then
    echo "[0/1] Writing default urls list..."
    cat <<'EOF' > urls.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_SS%2BAll_RUS.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Vless-Reality-White-Lists-Rus-Mobile.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE-CIDR-RU-all.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Export/Base64/PROXIES_ONLY/BLACK_VLESS_RUS_mobile_base64.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Export/Base64/PROXIES_ONLY/BLACK_VLESS_RUS_base64.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Export/v2rayN_PC/BLACK_VLESS_RUS_mobile_v2rayN.txt
https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/Vless-Reality-Black-Lists-Rus-Cable.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_Sub.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/All_Configs_base64_Sub.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vmess.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ss.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/ssr.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/trojan.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub1.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub2.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub3.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub4.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub5.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub6.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub7.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub8.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub9.txt
https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Sub10.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10000.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10059.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_1007.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10086.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_1010.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10103.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10136.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_10265.txt
https://raw.githubusercontent.com/hamedcode/port-based-v2ray-configs/main/sub/port_1080.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha-All-Type.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/V2Ray-Config-By-EbraSha.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/all_extracted_configs.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/vmess_configs.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/vless_configs.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/trojan_configs.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/ssr_configs.txt
https://raw.githubusercontent.com/ebrasha/free-v2ray-public-list/main/ss_configs.txt
https://raw.githubusercontent.com/liMilCo/v2r/main/sub/1.txt
https://raw.githubusercontent.com/liMilCo/v2r/main/best.txt
https://raw.githubusercontent.com/liMilCo/v2r/main/all_configs.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-1.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-2.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-3.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-4.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-5.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-6.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-7.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-8.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-9.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-10.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-11.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-12.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-13.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-14.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-15.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-16.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-17.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-18.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-19.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/subscriptions/subscription-20.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/separated_by_protocol/vmess.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/separated_by_protocol/vless.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/separated_by_protocol/trojan.txt
https://raw.githubusercontent.com/Firmfox/proxify/main/v2ray_configs/separated_by_protocol/ss.txt
https://raw.githubusercontent.com/Farid-Karimi/Config-Collector/main/mixed_iran.txt
https://raw.githubusercontent.com/xiaoji235/airport-free/main/v2ray.txt
https://raw.githubusercontent.com/Ruk1ng001/freeSub/main/v2ray
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/1.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/2.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/3.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/4.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/5.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/6.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/7.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/8.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/9.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/10.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/11.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/12.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/13.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/14.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/15.txt
https://raw.githubusercontent.com/histeenn/VLESS-PO-GRIBI/main/deploy/subscriptions/16.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/1.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/2.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/3.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/4.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/5.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/6.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/7.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/8.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/9.txt
https://raw.githubusercontent.com/nikita29a/FreeProxyList/main/mirror/10.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/Config_jo.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/Config_jo_Light.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/Config_no_cf.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/conf-week.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-US.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-DE.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-NL.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-UK.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-FR.txt
https://raw.githubusercontent.com/r3zarahimi/tg-v2ray-configs-every2h/main/regions/conf-FI.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/all.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/light.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/vless.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/vmess.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/shadowsocks.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/trojan.txt
https://raw.githubusercontent.com/ShatakVPN/ConfigForge-V2Ray/main/configs/unknown.txt
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/reality
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/vless
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/vmess
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/trojan
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/shadowsocks
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/hysteria
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/tuic
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/channels/protocols/juicity
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/reality
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vless
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/vmess
https://raw.githubusercontent.com/soroushmirzaei/telegram-configs-collector/main/protocols/trojan
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vless.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/vmess.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/trojan.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/ss.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/filtered/subs/hysteria2.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/all_sub.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub1.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub2.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub3.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub4.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub5.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub6.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub7.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub8.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub9.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub10.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub11.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub12.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub13.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub14.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub15.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub16.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub17.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub18.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub19.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub20.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub21.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub22.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub23.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub24.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub25.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub26.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub27.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub28.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub29.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub30.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub31.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub32.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub33.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub34.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub35.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub36.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub37.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub38.txt
https://raw.githubusercontent.com/MatinGhanbari/v2ray-configs/main/subscriptions/v2ray/subs/sub39.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/all_configs.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/protocols/vless.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/protocols/vmess.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/protocols/trojan.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/protocols/ss.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/protocols/hy2.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_001.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_002.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_003.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_004.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_005.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_006.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_007.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_008.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_009.txt
https://raw.githubusercontent.com/Delta-Kronecker/V2ray-Config/main/config/batches/v2ray/batch_010.txt
https://raw.githubusercontent.com/electron-v2ray/Telegram-Config-Dumpr/main/config.txt
https://raw.githubusercontent.com/jafarm83/ConfigV2Ray/main/jafar.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/All_Configs_Sub.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/All_Configs_base64_Sub.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub1.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub2.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub3.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub4.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub5.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub6.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub7.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub8.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub9.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub10.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub11.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub12.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub13.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub14.txt
https://raw.githubusercontent.com/Mahdi0024/ProxyCollector/main/Sub15.txt
https://raw.githubusercontent.com/Thordata/awesome-free-proxy-list/main/proxies/all.txt
https://raw.githubusercontent.com/Thordata/awesome-free-proxy-list/main/proxies/top-trusted.txt
https://raw.githubusercontent.com/Thordata/awesome-free-proxy-list/main/proxies/v2ray/all.txt
https://raw.githubusercontent.com/Thordata/awesome-free-proxy-list/main/proxies/v2ray/top-trusted.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/vless.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/vmess.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/trojan.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/ss.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/hysteria2.txt
https://raw.githubusercontent.com/gfpcom/free-proxy-list/main/lists/tuic.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/all.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/light.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/vless.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/vmess.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/trojan.txt
https://raw.githubusercontent.com/ninjastrikers/Nexus-nodes/main/configs/shadowsocks.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/all.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/top.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/verified.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/vless.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/vmess.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/trojan.txt
https://raw.githubusercontent.com/rtwo2/FastNodes/main/configs/ss.txt
https://raw.githubusercontent.com/rom5n/whitelist-download/main/configs.txt
https://raw.githubusercontent.com/hans-thomas/v2ray-subscription/master/servers.txt
https://raw.githubusercontent.com/hans-thomas/v2ray-subscription/refs/heads/master/servers.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/protocols/vl.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/protocols/vm.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/protocols/tr.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/protocols/ss.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-1.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-2.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-3.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-4.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-5.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-6.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-7.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-8.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-9.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-10.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-11.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-12.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-13.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-14.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-15.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-16.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-17.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-18.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-19.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-20.txt
https://raw.githubusercontent.com/sevcator/5ubscrpt10n/main/mini/m1n1-5ub-21.txt
https://raw.githubusercontent.com/lanopivijo93782-ops/hiddify-vless-xhttp-parser/main/sub/subscription.txt
https://raw.githubusercontent.com/a2470982985/getNode/main/v2ray.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/one_file_vpn.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/two_file_vpn.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/githubmirror/1.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/githubmirror/2.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/githubmirror/3.txt
https://raw.githubusercontent.com/AvenCores/goida-vpn-configs/main/githubmirror/26.txt
https://raw.githubusercontent.com/itsyebekhe/PSG/main/lite/subscriptions/xray/base64/mix
https://raw.githubusercontent.com/itsyebekhe/PSG/main/normal/subscriptions/xray/normal/mix
https://raw.githubusercontent.com/itsyebekhe/PSG/main/lite/subscriptions/xray/normal/mix
https://raw.githubusercontent.com/V2RayRoot/V2RayConfig/main/Config/vless.txt
https://raw.githubusercontent.com/Argh94/Proxy-List/main/All_Config.txt
https://raw.githubusercontent.com/MhdiTaheri/V2rayCollector/main/sub/mix
https://raw.githubusercontent.com/longlon/v2ray-config/main/configs.txt
https://raw.githubusercontent.com/miladtahanian/Config-Collector/main/mixed_iran.txt
https://raw.githubusercontent.com/miladtahanian/Config-Collector/main/vmess_iran.txt
https://raw.githubusercontent.com/miladtahanian/Config-Collector/main/vless_iran.txt
https://raw.githubusercontent.com/MohammadBahemmat/V2ray-Collector/main/servers/all_servers.txt
https://raw.githubusercontent.com/mrvcoder/V2rayCollector/main/mixed_iran.txt
https://raw.githubusercontent.com/Stinsonysm/GO_V2rayCollector/main/vmess_iran.txt
https://raw.githubusercontent.com/liketolivefree/kobabi/main/sub.txt
https://raw.githubusercontent.com/ALIILAPRO/v2rayNG-Config/main/sub.txt
https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/Eternity
https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/splitted/vmess.txt
https://raw.githubusercontent.com/mahdibland/V2RayAggregator/master/sub/splitted/trojan.txt
https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.txt
https://raw.githubusercontent.com/ssrsub/ssr/master/v2ray
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/splitted/mixed
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/splitted/vless
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/splitted/vmess
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/splitted/trojan
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/splitted/ss
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/python/socks
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/python/hysteria2
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/python/hysteria
https://raw.githubusercontent.com/Surfboardv2ray/TGParse/main/python/hy2
https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/configs.txt
https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/sub/vless.txt
https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/sub/vmess.txt
https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/sub/trojan.txt
https://raw.githubusercontent.com/mohammadaz2/v2rayConfigsForYou/main/sub/ss.txt
https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/mix.txt
https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/vless.txt
https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/vmess.txt
https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/trojan.txt
https://raw.githubusercontent.com/MahanKenway/Freedom-V2Ray/main/configs/ss.txt
https://raw.githubusercontent.com/roosterkid/openproxylist/main/V2RAY_RAW.txt
https://raw.githubusercontent.com/roosterkid/openproxylist/refs/heads/main/V2RAY_RAW.txt
https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/All_Configs_Sub.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/All_Configs_base64_Sub.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub1.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub2.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub3.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub4.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub5.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub6.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub7.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub8.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub9.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub10.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub11.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub12.txt
https://raw.githubusercontent.com/barry-far/V2ray-Configs/main/Sub13.txt
https://raw.githubusercontent.com/Arefgh72/v2ray-proxy-pars-tester/main/output/github_all.txt
https://raw.githubusercontent.com/Arefgh72/v2ray-proxy-pars-tester/main/output/github_top_500.txt
https://raw.githubusercontent.com/Arefgh72/v2ray-proxy-pars-tester/main/output/github_top_100.txt
https://raw.githubusercontent.com/vAHiD55555/vLess/main/README.md
https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub
https://raw.githubusercontent.com/rpg-dev420/Onix-V2Ray-Collector/main/subscriptions/all_subscription.txt
https://raw.githubusercontent.com/rpg-dev420/Onix-V2Ray-Collector/main/subscriptions/all_subscription_base64.txt
https://raw.githubusercontent.com/rpg-dev420/Onix-V2Ray-Collector/main/subscriptions/vless_subscription.txt
https://raw.githubusercontent.com/rpg-dev420/Onix-V2Ray-Collector/main/subscriptions/vmess_subscription.txt
https://raw.githubusercontent.com/MrEndi777709/Endi-VPN/main/mrendi-vpn-all.txt
https://raw.githubusercontent.com/FLAT447/v2ray-lists/main/BLACK_LTE.txt
https://raw.githubusercontent.com/FLAT447/v2ray-lists/main/WHITE_FULL.txt
https://raw.githubusercontent.com/DukeMehdi/FreeList-V2ray-Configs/refs/heads/main/Configs/All-DukeMehdi-Configs.txt
https://raw.githubusercontent.com/bridgerzan/v2ray-config/refs/heads/main/configs.txt
https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/top100.txt
https://raw.githubusercontent.com/0xRadikal/Free-v2ray-Configs/main/verified/configs.txt
https://raw.githubusercontent.com/awesome-vpn/awesome-vpn/master/all
https://raw.githubusercontent.com/SoliSpirit/v2ray-configs/refs/heads/main/all_configs.txt
EOF
fi

# Short commands in PATH
echo "Installing short commands into $BIN_DIR..."
ln -sf "$XK_DIR/update.sh"        "$BIN_DIR/xkmod-u"
ln -sf "$XK_DIR/check-configs.sh" "$BIN_DIR/xkmod-c"
ln -sf "$XK_DIR/xray-start.sh"    "$BIN_DIR/xkmod-s"
ln -sf "$XK_DIR/proxyw.sh"        "$BIN_DIR/xkmod-pw"
chmod +x "$XK_DIR/update.sh" "$XK_DIR/check-configs.sh" "$XK_DIR/xray-start.sh" "$XK_DIR/proxyw.sh"

# Ensure BIN_DIR is in PATH for non-Termux
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Note: add $BIN_DIR to PATH:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo "Install finished."
