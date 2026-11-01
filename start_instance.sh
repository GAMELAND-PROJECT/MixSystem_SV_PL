#!/bin/bash
# =========================================================
# GameLand CS 1.6 - Multi-instance startup
# Starts one isolated server instance described in instances/<id>.env
# =========================================================
set -uo pipefail

# ─── 0. Mutex Lock to guarantee staggered boot & prevent stampede ──
LOCK_FILE="/tmp/gameland_server_boot.lock"
exec 200>"$LOCK_FILE" 2>/dev/null || true
if command -v flock >/dev/null 2>&1; then
    flock -x -w 40 200 2>/dev/null || echo "[WARN] Boot lock wait timed out; continuing..."
fi

INSTANCE_ID="${1:-}"
MANAGER_ROOT="${MANAGER_ROOT:-$(cd "$(dirname "$(readlink -f "$0")")" && pwd)}"

if [[ -z "$INSTANCE_ID" || ! "$INSTANCE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "[ERROR] Usage: start_instance.sh <instance_id>"
    if command -v flock >/dev/null 2>&1; then flock -u 200 2>/dev/null || true; fi
    exit 1
fi

ENV_FILE="${MANAGER_ROOT}/instances/${INSTANCE_ID}.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "[WARN] Instance config not found: $ENV_FILE. Attempting auto-recovery from servers.json..."
    recovered_json=$(python3 -c '
import json, sys
iid = sys.argv[1]
for p in ["/opt/gameland/server/instances/servers.json", "/opt/gameland/persistent/servers.json"]:
    try:
        with open(p) as f:
            d = json.load(f)
            for s in d.get("servers", []):
                if s.get("id") == iid:
                    print(json.dumps(s))
                    sys.exit(0)
    except Exception: pass
sys.exit(1)
' "$INSTANCE_ID" 2>/dev/null || true)

    if [[ -n "$recovered_json" ]]; then
        r_port=$(echo "$recovered_json" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("port", 27016))')
        r_dir=$(echo "$recovered_json" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("server_dir", "/opt/gameland/instances/'"$INSTANCE_ID"'"))')
        r_slots=$(echo "$recovered_json" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("slots", 10))')
        r_name=$(echo "$recovered_json" | python3 -c 'import json, sys; d=json.load(sys.stdin); print(d.get("hostname") or d.get("name") or "'"$INSTANCE_ID"'")')
        mkdir -p "${MANAGER_ROOT}/instances"
        cat > "$ENV_FILE" <<EOF
INSTANCE_ID="${INSTANCE_ID}"
SERVER_DIR="${r_dir}"
SERVER_IP="0.0.0.0"
SERVER_PORT="${r_port}"
SERVER_NAME="${r_name}"
HOSTNAME="${r_name}"
MAX_PLAYERS="${r_slots}"
MAP="de_dust2"
TMUX_SESSION="gameland_${INSTANCE_ID}"
STEAMCMD_LINUX32="/opt/steamcmd/linux32"
EOF
        echo "[OK] Successfully auto-recovered $ENV_FILE!"
    else
        echo "[ERROR] Instance config not found: $ENV_FILE and could not recover from servers.json"
        exit 1
    fi
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

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

SERVER_DIR="${SERVER_DIR:?SERVER_DIR is required}"
SERVER_PORT="${SERVER_PORT:?SERVER_PORT is required}"
CLIENT_PORT="${CLIENT_PORT:-$((SERVER_PORT == 27015 ? 27005 : SERVER_PORT + 100))}"
SERVER_IP="${SERVER_IP:-0.0.0.0}"
MAX_PLAYERS="${MAX_PLAYERS:-10}"
inst_pini="${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini"
if [ -f "$inst_pini" ]; then
    if grep -Eq '^[[:space:]]*clanwar_system\.amxx' "$inst_pini"; then
        MAX_PLAYERS="10"
    elif grep -Eq '^[[:space:]]*mix_system\.amxx' "$inst_pini"; then
        MAX_PLAYERS="18"
    else
        [ "$MAX_PLAYERS" = "10" ] && MAX_PLAYERS="24"
    fi
fi
MAP="${MAP:-de_dust2}"
TMUX_SESSION="${TMUX_SESSION:-gameland_${INSTANCE_ID}}"
HLTV_SESSION="${HLTV_SESSION:-gameland_hltv_${INSTANCE_ID}}"
COMPRESSOR_SESSION="${COMPRESSOR_SESSION:-demo_compressor_${INSTANCE_ID}}"
STEAMCMD_LINUX32="${STEAMCMD_LINUX32:-/opt/steamcmd/linux32}"

# Dynamic hostname resolution from servers.json / server.cfg if not explicit or generic
if [[ -z "${HOSTNAME:-}" || "${HOSTNAME:-}" == "GAMELAND" ]]; then
    resolved_name=$(python3 -c '
import json, sys, re, os
iid = sys.argv[1]
sdir = sys.argv[2]
# 1. Check servers.json (local and persistent)
for p in ["/opt/gameland/server/instances/servers.json", "/opt/gameland/persistent/servers.json"]:
    try:
        with open(p) as f:
            for s in json.load(f).get("servers", []):
                if s.get("id") == iid:
                    h = s.get("hostname") or s.get("name") or ""
                    if h:
                        print(h)
                        sys.exit(0)
    except Exception: pass

# 2. Check instance server.cfg
cfg = os.path.join(sdir, "cstrike", "server.cfg")
if os.path.isfile(cfg):
    try:
        with open(cfg, "r", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith("cw_base_hostname") or line.startswith("mix_base_hostname"):
                    m = re.search(r"(?:cw|mix)_base_hostname\s+\"([^\"]+)\"", line)
                    if m and m.group(1).strip():
                        print(m.group(1).strip())
                        sys.exit(0)
                elif line.startswith("hostname"):
                    m = re.search(r"hostname\s+\"([^\"]+)\"", line)
                    if m and m.group(1).strip():
                        clean = re.sub(r"\s*\[(CW|Pick|Knife|Live|WarmUp|Overtime|Paused|Final)[^\]]*\]", "", m.group(1), flags=re.I).strip()
                        if clean and clean.lower() not in ["gameland", "counter-strike 1.6 server"]:
                            print(clean)
                            sys.exit(0)
    except Exception: pass

sys.exit(1)
' "$INSTANCE_ID" "$SERVER_DIR" 2>/dev/null || true)
    if [[ -n "$resolved_name" ]]; then
        HOSTNAME="$resolved_name"
        SERVER_NAME="$resolved_name"
    fi
fi
HOSTNAME="${HOSTNAME:-${SERVER_NAME:-${INSTANCE_ID}}}"

cd "$SERVER_DIR"
mkdir -p "${SERVER_DIR}/logs"
LOG_FILE="${SERVER_DIR}/logs/server_${INSTANCE_ID}.log"

echo "================================================="
echo " Starting GameLand instance: ${INSTANCE_ID}"
echo " Hostname: ${HOSTNAME}"
echo " IP: ${SERVER_IP} | Port: ${SERVER_PORT} | Slots: ${MAX_PLAYERS}"
echo " Dir: ${SERVER_DIR}"
echo "================================================="

# Ensure instance server.cfg has its own unique hostname and base hostnames
if [[ -f "${SERVER_DIR}/cstrike/server.cfg" ]]; then
    sed -i -E "s/^[[:space:]]*hostname[[:space:]]+.*/hostname \"${HOSTNAME}\"/" "${SERVER_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q '^[[:space:]]*hostname' "${SERVER_DIR}/cstrike/server.cfg"; then
        echo "hostname \"${HOSTNAME}\"" >> "${SERVER_DIR}/cstrike/server.cfg"
    fi
    sed -i -E "s/^[[:space:]]*cw_base_hostname[[:space:]]+.*/cw_base_hostname \"${HOSTNAME}\"/" "${SERVER_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q '^[[:space:]]*cw_base_hostname' "${SERVER_DIR}/cstrike/server.cfg"; then
        echo "cw_base_hostname \"${HOSTNAME}\"" >> "${SERVER_DIR}/cstrike/server.cfg"
    fi
    sed -i -E "s/^[[:space:]]*mix_base_hostname[[:space:]]+.*/mix_base_hostname \"${HOSTNAME}\"/" "${SERVER_DIR}/cstrike/server.cfg" 2>/dev/null || true
    if ! grep -q '^[[:space:]]*mix_base_hostname' "${SERVER_DIR}/cstrike/server.cfg"; then
        echo "mix_base_hostname \"${HOSTNAME}\"" >> "${SERVER_DIR}/cstrike/server.cfg"
    fi
fi
# Strip any hardcoded hostname from gameland.cfg in instance folder
if [[ -f "${SERVER_DIR}/cstrike/gameland.cfg" ]]; then
    sed -i -E '/^[[:space:]]*(hostname|cw_base_hostname|mix_base_hostname)[[:space:]]+/d' "${SERVER_DIR}/cstrike/gameland.cfg" 2>/dev/null || true
fi

# Clean any existing sessions for this instance
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
screen -X -S "$HLTV_SESSION" quit 2>/dev/null || true
screen -X -S "$COMPRESSOR_SESSION" quit 2>/dev/null || true

# Actively wait for ports to be completely free (eliminates port collision race condition)
for ((p=1; p<=8; p++)); do
    is_busy=false
    if command -v fuser >/dev/null 2>&1; then
        if fuser "${SERVER_PORT}/udp" >/dev/null 2>&1 || fuser "${CLIENT_PORT}/udp" >/dev/null 2>&1; then
            is_busy=true
            fuser -k -9 "${SERVER_PORT}/udp" 2>/dev/null || true
            fuser -k -9 "${SERVER_PORT}/tcp" 2>/dev/null || true
            fuser -k -9 "${CLIENT_PORT}/udp" 2>/dev/null || true
        fi
    fi
    if [ "$is_busy" = "false" ]; then
        break
    fi
    sleep 0.5
done

# Ensure binary permissions are executable
chmod +x "${SERVER_DIR}/hlds_linux" "${SERVER_DIR}/hlds_run" "${SERVER_DIR}"/*.sh 2>/dev/null || true

# Self-healing: ensure custom dense smoke sprite & plugin binary are present before booting
mkdir -p "${SERVER_DIR}/cstrike/sprites" "${SERVER_DIR}/cstrike/addons/amxmodx/plugins" "${SERVER_DIR}/cstrike/addons/amxmodx/configs" 2>/dev/null || true
if [[ -f "${MANAGER_ROOT}/cstrike/sprites/gas_puff_02.spr" && ! -f "${SERVER_DIR}/cstrike/sprites/gas_puff_02.spr" ]]; then
    cp -f "${MANAGER_ROOT}/cstrike/sprites/gas_puff_02.spr" "${SERVER_DIR}/cstrike/sprites/gas_puff_02.spr" 2>/dev/null || true
    chmod 666 "${SERVER_DIR}/cstrike/sprites/gas_puff_02.spr" 2>/dev/null || true
fi
if [[ -f "${MANAGER_ROOT}/cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx" && ! -f "${SERVER_DIR}/cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx" ]]; then
    cp -f "${MANAGER_ROOT}/cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx" "${SERVER_DIR}/cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx" 2>/dev/null || true
    chmod 666 "${SERVER_DIR}/cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx" 2>/dev/null || true
fi
if [[ -f "${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini" ]]; then
    if grep -qE '^[[:space:]]*;+[[:space:]]*gameland_dense_smoke\.amxx([[:space:]]|$)' "${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini"; then
        sed -i -E 's/^[[:space:]]*;+[[:space:]]*(gameland_dense_smoke\.amxx.*)$/\1/' "${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini" 2>/dev/null || true
    elif ! grep -qE '^[[:space:]]*gameland_dense_smoke\.amxx([[:space:]]|$)' "${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini"; then
        echo -e "gameland_dense_smoke.amxx\t; High density opaque smoke grenade (anti-see-through)" >> "${SERVER_DIR}/cstrike/addons/amxmodx/configs/plugins.ini" 2>/dev/null || true
    fi
fi

# Rotate log file if > 10MB
if [[ -f "$LOG_FILE" ]] && [[ "$(stat -c%s "$LOG_FILE")" -gt 10485760 ]]; then
    mv "$LOG_FILE" "${LOG_FILE}.1"
fi

# Create session with retry so transient tmux locks never fail systemd
session_started=false
for attempt in 1 2 3; do
    if tmux new-session -d -s "$TMUX_SESSION" \
        "cd '${SERVER_DIR}' && while true; do \
            chmod +x ./hlds_linux ./hlds_run 2>/dev/null || true; \
            export LD_LIBRARY_PATH='${SERVER_DIR}:${STEAMCMD_LINUX32}:${LD_LIBRARY_PATH:-}'; \
            echo '[START] Launching hlds_linux for ${INSTANCE_ID} (Hostname: ${HOSTNAME}, Port: ${SERVER_PORT}, Slots: ${MAX_PLAYERS})...'; \
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
            echo '[CRASH] ${INSTANCE_ID} stopped. Restarting in 3s...'; \
            sleep 3; \
        done"; then
        session_started=true
        break
    else
        echo "[WARN] Attempt $attempt to create tmux session '$TMUX_SESSION' failed, cleaning up and retrying..."
        tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
        sleep 1.0
    fi
done

if [[ "$session_started" != "true" ]]; then
    echo "[ERROR] Failed to start tmux session '$TMUX_SESSION' after 3 attempts!"
    exit 1
fi

tmux_pid="$(tmux display-message -t "$TMUX_SESSION" -p '#{pane_pid}' 2>/dev/null || true)"
if [[ -n "$tmux_pid" ]]; then
    echo "$tmux_pid" > "${SERVER_DIR}/${INSTANCE_ID}.pid"
fi

# Verify startup health
sleep 1.5
if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
    echo "[SUCCESS] Instance '${INSTANCE_ID}' started in tmux session '${TMUX_SESSION}' on port ${SERVER_PORT}."
else
    echo "[WARN] Instance '${INSTANCE_ID}' session exited prematurely. Check logs at: ${LOG_FILE}"
fi

# Staggered stabilization delay before releasing boot lock to next queued server
sleep 2.0
if command -v flock >/dev/null 2>&1; then
    flock -u 200 2>/dev/null || true
fi


