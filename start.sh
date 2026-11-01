#!/bin/bash
# =========================================================
# GameLand CS 1.6 - Startup Script
# 18 Slots Dedicated Server | Persistent Admins & Servers
# Zero HLTV / Zero Demo Recording
# =========================================================
set -e

# ─── 0. Mutex Lock to guarantee staggered boot & prevent stampede ──
LOCK_FILE="/tmp/gameland_server_boot.lock"
exec 200>"$LOCK_FILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
    flock -x -w 40 200 2>/dev/null || echo "[WARN] Boot lock wait timed out; continuing..."
fi

# Auto-sanitize systemd service files to guarantee 100% decoupling
needs_reload=0
rm -rf /etc/systemd/system/gameland*.service.d 2>/dev/null || true
if [ -f "/etc/systemd/system/gameland.service" ] && [ -f "${SCRIPT_DIR:-/opt/gameland/server}/gameland.service" ]; then
    if ! cmp -s "${SCRIPT_DIR:-/opt/gameland/server}/gameland.service" "/etc/systemd/system/gameland.service" 2>/dev/null; then
        cp -f "${SCRIPT_DIR:-/opt/gameland/server}/gameland.service" "/etc/systemd/system/gameland.service" 2>/dev/null || true
        chmod 644 "/etc/systemd/system/gameland.service" 2>/dev/null || true
        needs_reload=1
    fi
fi
if [ -f "/etc/systemd/system/gameland@.service" ] && [ -f "${SCRIPT_DIR:-/opt/gameland/server}/gameland@.service" ]; then
    if ! cmp -s "${SCRIPT_DIR:-/opt/gameland/server}/gameland@.service" "/etc/systemd/system/gameland@.service" 2>/dev/null; then
        cp -f "${SCRIPT_DIR:-/opt/gameland/server}/gameland@.service" "/etc/systemd/system/gameland@.service" 2>/dev/null || true
        chmod 644 "/etc/systemd/system/gameland@.service" 2>/dev/null || true
        needs_reload=1
    fi
fi
if [ "$needs_reload" -eq 1 ]; then
    systemctl daemon-reload 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# ─── Linux Kernel & Network Socket Tuning (1000 FPS Hitreg) ───
ulimit -n 65535 2>/dev/null || true
if command -v sysctl >/dev/null 2>&1; then
    sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1 || true
    sysctl -w net.core.rmem_default=1048576 >/dev/null 2>&1 || true
    sysctl -w net.core.wmem_default=1048576 >/dev/null 2>&1 || true
    sysctl -w net.core.netdev_max_backlog=10000 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_rmem_min=16384 >/dev/null 2>&1 || true
    sysctl -w net.ipv4.udp_wmem_min=16384 >/dev/null 2>&1 || true
fi

# ─── تنظیمات سرور ─────────────────────────────
SERVER_PORT="27015"
CLIENT_PORT="${CLIENT_PORT:-27005}"
MAX_PLAYERS="10"
MAP="de_dust2"
SERVER_IP="0.0.0.0"

if [ -f "${SCRIPT_DIR}/.env" ]; then
    # shellcheck disable=SC1090
    source "${SCRIPT_DIR}/.env"
fi

# تشخیص هوشمند اسلات و مد فعال (بررسی دقیق plugins.ini، main_mode.txt و modes.json)
PLUGINS_INI="${SCRIPT_DIR}/cstrike/addons/amxmodx/configs/plugins.ini"
SAVED_MAIN_MODE=""

# اگر در plugins.ini پلاگین میکس فعال باشد، مد قطعاً mix5v5 و ۱۸ اسلات است
if [ -f "$PLUGINS_INI" ] && grep -Eq '^[[:space:]]*mix_system\.amxx([[:space:]]|$)' "$PLUGINS_INI"; then
    SAVED_MAIN_MODE="mix5v5"
elif [ -f "$PLUGINS_INI" ] && grep -Eq '^[[:space:]]*clanwar_system\.amxx([[:space:]]|$)' "$PLUGINS_INI"; then
    SAVED_MAIN_MODE="clanwar"
elif [ -f "/opt/gameland/persistent/main_mode.txt" ]; then
    SAVED_MAIN_MODE=$(cat "/opt/gameland/persistent/main_mode.txt" 2>/dev/null | tr -d '[:space:]')
fi

if [ "$SAVED_MAIN_MODE" = "mix5v5" ]; then
    MAX_PLAYERS="18"
elif [ "$SAVED_MAIN_MODE" = "public" ]; then
    MAX_PLAYERS="24"
elif [ "$SAVED_MAIN_MODE" = "clanwar" ]; then
    MAX_PLAYERS="10"
else
    MAX_PLAYERS="18"
fi

# بروزرسانی دائمی اسلات در main_mode.txt
mkdir -p /opt/gameland/persistent "${SCRIPT_DIR}/instances" 2>/dev/null || true
echo "${SAVED_MAIN_MODE:-mix5v5}" > "/opt/gameland/persistent/main_mode.txt" 2>/dev/null || true
echo "${SAVED_MAIN_MODE:-mix5v5}" > "${SCRIPT_DIR}/instances/main_mode.txt" 2>/dev/null || true

# Dynamic hostname resolution
HOSTNAME="${HOSTNAME:-${SERVER_NAME:-}}"
if [ -z "$HOSTNAME" ] && [ -f "${SCRIPT_DIR}/cstrike/server.cfg" ]; then
    HOSTNAME=$(grep -E '^[[:space:]]*(cw_base_hostname|mix_base_hostname|hostname)[[:space:]]+"' "${SCRIPT_DIR}/cstrike/server.cfg" | head -n 1 | sed -E 's/^[[:space:]]*[a-zA-Z0-9_]+[[:space:]]+"([^"]+)".*/\1/' || true)
fi
HOSTNAME="${HOSTNAME:-GameLand CS 1.6 #1 (Competitive)}"

if [ -f "${SCRIPT_DIR}/cstrike/server.cfg" ]; then
    sed -i -E "s/^[[:space:]]*cw_base_hostname[[:space:]]+.*/cw_base_hostname \"${HOSTNAME}\"/" "${SCRIPT_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q 'cw_base_hostname' "${SCRIPT_DIR}/cstrike/server.cfg"; then
        echo "cw_base_hostname \"${HOSTNAME}\"" >> "${SCRIPT_DIR}/cstrike/server.cfg"
    fi
    sed -i -E "s/^[[:space:]]*mix_base_hostname[[:space:]]+.*/mix_base_hostname \"${HOSTNAME}\"/" "${SCRIPT_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q 'mix_base_hostname' "${SCRIPT_DIR}/cstrike/server.cfg"; then
        echo "mix_base_hostname \"${HOSTNAME}\"" >> "${SCRIPT_DIR}/cstrike/server.cfg"
    fi
    # همگام‌سازی sv_visiblemaxplayers با اسلات واقعی در server.cfg
    sed -i -E "s/^[[:space:]]*sv_visiblemaxplayers[[:space:]]+[0-9]+/sv_visiblemaxplayers ${MAX_PLAYERS}/" "${SCRIPT_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q '^[[:space:]]*sv_visiblemaxplayers' "${SCRIPT_DIR}/cstrike/server.cfg"; then
        echo "sv_visiblemaxplayers ${MAX_PLAYERS}" >> "${SCRIPT_DIR}/cstrike/server.cfg"
    fi
fi

STEAMCMD_LINUX32="/opt/steamcmd/linux32"
export LD_LIBRARY_PATH="${SCRIPT_DIR}:${STEAMCMD_LINUX32}:${LD_LIBRARY_PATH:-}"

echo "================================================="
echo " Starting GameLand CS 1.6 Server...              "
echo " Hostname: $HOSTNAME"
echo " IP: $SERVER_IP | Port: $SERVER_PORT | Slots: $MAX_PLAYERS"
echo " Dir: $SCRIPT_DIR                                "
echo " HLTV: Completely DISABLED                       "
echo "================================================="

# ─── 1. حفاظت دائمی از ادمین‌ها و سرورها ──────────────────────
mkdir -p /opt/gameland/persistent

# بازیابی خودکار ادمین‌ها (users.ini)
if [ -f "/opt/gameland/persistent/users.ini" ]; then
    PERSIST_COUNT=$(grep -cE '^[[:space:]]*"[^"]+"' /opt/gameland/persistent/users.ini 2>/dev/null || echo 0)
    LOCAL_COUNT=$(grep -cE '^[[:space:]]*"[^"]+"' "${SCRIPT_DIR}/cstrike/addons/amxmodx/configs/users.ini" 2>/dev/null || echo 0)
    if [ "$PERSIST_COUNT" -gt "$LOCAL_COUNT" ]; then
        cp -f /opt/gameland/persistent/users.ini "${SCRIPT_DIR}/cstrike/addons/amxmodx/configs/users.ini"
        echo "[*] Restored $PERSIST_COUNT admin accounts from persistent storage."
    fi
elif [ -f "${SCRIPT_DIR}/cstrike/addons/amxmodx/configs/users.ini" ]; then
    cp -f "${SCRIPT_DIR}/cstrike/addons/amxmodx/configs/users.ini" /opt/gameland/persistent/users.ini
fi

# بازیابی خودکار سرورهای ثبت‌شده (servers.json)
if [ -f "/opt/gameland/persistent/servers.json" ]; then
    if [ ! -f "${SCRIPT_DIR}/instances/servers.json" ] || [ "$(stat -c%s "${SCRIPT_DIR}/instances/servers.json" 2>/dev/null || echo 0)" -lt 20 ]; then
        mkdir -p "${SCRIPT_DIR}/instances"
        cp -f /opt/gameland/persistent/servers.json "${SCRIPT_DIR}/instances/servers.json"
        echo "[*] Restored server instances registry from persistent storage."
    fi
elif [ -f "${SCRIPT_DIR}/instances/servers.json" ]; then
    cp -f "${SCRIPT_DIR}/instances/servers.json" /opt/gameland/persistent/servers.json
fi

# ─── 2. بستن پروسس‌های متناظر با این سرور (ایزوله و بدون اثر روی سایر سرورها) ────
if command -v fuser >/dev/null 2>&1; then
    fuser -k "${SERVER_PORT}/udp" 2>/dev/null || true
    fuser -k "${SERVER_PORT}/tcp" 2>/dev/null || true
    fuser -k "${CLIENT_PORT}/udp" 2>/dev/null || true
fi
rm -f "${SCRIPT_DIR}/gameland.pid" 2>/dev/null || true
screen -X -S gameland_hltv quit 2>/dev/null || true
screen -X -S demo_compressor quit 2>/dev/null || true

# ─── 3. پاکسازی نشست قبلی tmux این سرور ──────────────────────────
if tmux has-session -t gameland_server 2>/dev/null; then
    echo "[*] Killing old tmux session..."
    tmux kill-session -t gameland_server 2>/dev/null || true
    sleep 0.5
fi

# پوشه لاگ و چرخش
mkdir -p "${SCRIPT_DIR}/logs"
LOG_FILE="${SCRIPT_DIR}/logs/server.log"
if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -gt 10485760 ]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
    echo "[*] Log rotated to server.log.1"
fi

# اطمینان قطعی از دسترسی اجرایی باینری‌ها
chmod +x "${SCRIPT_DIR}/hlds_linux" "${SCRIPT_DIR}/hlds_run" "${SCRIPT_DIR}"/*.sh 2>/dev/null || true

# ─── 4. راه‌اندازی سرور داخل tmux با حلقه auto-restart ────────
tmux new-session -d -s gameland_server \
    "cd '${SCRIPT_DIR}' && while true; do \
        chmod +x ./hlds_linux ./hlds_run 2>/dev/null || true; \
        echo '[START] Launching hlds_linux (Slots: ${MAX_PLAYERS})...'; \
        ./hlds_linux -game cstrike -console \
            -ip ${SERVER_IP} \
            +port ${SERVER_PORT} \
            +clientport ${CLIENT_PORT} \
            +hostname \"${HOSTNAME}\" \
            +cw_base_hostname \"${HOSTNAME}\" \
            +mix_base_hostname \"${HOSTNAME}\" \
            +map ${MAP} \
            +maxplayers ${MAX_PLAYERS} \
            +sv_lan 0 \
            +sys_ticrate 1100 \
            -pingboost 3 \
            -num_edicts 2048 \
            -noipx \
            2>&1 | tee -a '${LOG_FILE}'; \
        echo '[CRASH] Server stopped! Restarting in 3s...'; \
        sleep 3; \
    done"

tmux_pid=$(tmux display-message -t gameland_server -p '#{pane_pid}' 2>/dev/null || echo "")
if [ -n "$tmux_pid" ]; then
    echo "$tmux_pid" > "${SCRIPT_DIR}/gameland.pid"
    echo "[*] Pane PID $tmux_pid saved to gameland.pid"
fi

# Staggered stabilization delay before releasing boot lock
sleep 2.0
if command -v flock >/dev/null 2>&1; then
    flock -u 200 2>/dev/null || true
fi

echo "[SUCCESS] GameLand Server (${MAX_PLAYERS} Slots) started in tmux session 'gameland_server'!"
echo "-> Live console : tmux attach -t gameland_server"
echo "-> Detach       : Ctrl+B then D"
echo "-> Logs         : tail -f ${LOG_FILE}"
