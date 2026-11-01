#!/bin/bash
# =========================================================
# GameLand CS 1.6 - Safe Staggered Multi-Server Restart
# Reboots all servers strictly ONE BY ONE with 2.5s delay
# Eliminates CPU/RAM spikes, socket contention, and port collisions!
# =========================================================
set -u

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$PROJECT_DIR"

echo -e "${CYAN}======================================================${NC}"
echo -e "${BOLD}${GREEN}   GameLand CS 1.6 - Safe Staggered Multi-Server Restart   ${NC}"
echo -e "${CYAN}======================================================${NC}"

# 0. Linux Kernel & Socket Buffer Tuning (1000 FPS Hitreg)
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

# 1. Sanitize systemd service files if old dangerous directives exist
if [ -f "/etc/systemd/system/gameland.service" ]; then
    if grep -qE 'pkill -9 -f hlds_linux|killall -9 hlds_linux' "/etc/systemd/system/gameland.service" 2>/dev/null; then
        echo -e "${YELLOW}[*] Sanitizing /etc/systemd/system/gameland.service (removing legacy global pkill)...${NC}"
        sed -i -E 's/pkill -9 -f hlds_linux 2>\/dev\/null;//g' "/etc/systemd/system/gameland.service" 2>/dev/null || true
        sed -i -E 's/killall -9 hlds_linux 2>\/dev\/null;//g' "/etc/systemd/system/gameland.service" 2>/dev/null || true
        systemctl daemon-reload 2>/dev/null || true
    fi
fi

# Ensure gameland@.service is updated and enabled
if [ -f "${PROJECT_DIR}/gameland@.service" ] && [ -d "/etc/systemd/system" ]; then
    sed "s|/opt/gameland/server|${PROJECT_DIR}|g" "${PROJECT_DIR}/gameland@.service" > /etc/systemd/system/gameland@.service 2>/dev/null || true
    chmod 644 /etc/systemd/system/gameland@.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
fi

# 2. Collect all configured servers
servers=()
# Always start with 'main'
servers+=("main:27015:GameLand Main (27015):gameland.service:gameland_server")

# Discover from servers.json (local and persistent)
reg_json=""
for reg_path in "${PROJECT_DIR}/instances/servers.json" "/opt/gameland/persistent/servers.json"; do
    if [ -f "$reg_path" ] && [ -s "$reg_path" ]; then
        reg_json="$reg_path"
        break
    fi
done

if [ -n "$reg_json" ]; then
    while IFS='|' read -r i_id i_port i_name; do
        if [[ -n "$i_id" && "$i_id" != "main" ]]; then
            servers+=("${i_id}:${i_port}:${i_name}:gameland@${i_id}.service:gameland_${i_id}")
        fi
    done < <(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
        for s in d.get("servers", []):
            sid = s.get("id")
            if sid and sid != "main":
                port = s.get("port", 27016)
                name = s.get("hostname") or s.get("name") or sid
                print(f"{sid}|{port}|{name}")
except Exception: pass
' "$reg_json" 2>/dev/null || true)
fi

total_count="${#servers[@]}"
echo -e "${CYAN}[*] Found ${total_count} server(s) to restart sequentially:${NC}"
for entry in "${servers[@]}"; do
    IFS=':' read -r s_id s_port s_name s_svc s_tmux <<< "$entry"
    echo -e "    - ${BOLD}${s_id}${NC} (Port: ${s_port}) -> ${s_name}"
done
echo -e "${CYAN}------------------------------------------------------${NC}"

# 3. Sequential Staggered Restart
step=1
success_count=0
fail_count=0

for entry in "${servers[@]}"; do
    IFS=':' read -r s_id s_port s_name s_svc s_tmux <<< "$entry"
    echo -e "\n${YELLOW}[${step}/${total_count}] Restarting '${s_id}' (Port: ${s_port})...${NC}"

    # Pre-clean this server's specific port and tmux session only
    tmux kill-session -t "$s_tmux" 2>/dev/null || true
    if command -v fuser >/dev/null 2>&1 && [ -n "$s_port" ]; then
        fuser -k "${s_port}/udp" 2>/dev/null || true
        client_p=$((s_port == 27015 ? 27005 : s_port + 100))
        fuser -k "${client_p}/udp" 2>/dev/null || true
    fi

    # Trigger isolated systemd restart
    if [ "$s_id" != "main" ]; then
        systemctl enable "$s_svc" 2>/dev/null || true
    fi
    systemctl restart "$s_svc" 2>/dev/null || true

    # Stagger delay: wait 2.5s for HLDS engine to initialize and bind UDP socket
    echo -e "    [*] Waiting 2.5s for socket binding and startup stabilization..."
    sleep 2.5

    # Check health
    is_live=false
    if tmux has-session -t "$s_tmux" 2>/dev/null; then
        is_live=true
    fi
    if [ "$is_live" = false ] && command -v fuser >/dev/null 2>&1; then
        if fuser "${s_port}/udp" >/dev/null 2>&1; then
            is_live=true
        fi
    fi

    if [ "$is_live" = true ]; then
        echo -e "    ${GREEN}✔ [ONLINE] '${s_id}' (Port ${s_port}) is RUNNING perfectly!${NC}"
        success_count=$((success_count + 1))
    else
        echo -e "    ${RED}✖ [WARN] '${s_id}' session exited or taking longer to load.${NC}"
        fail_count=$((fail_count + 1))
    fi

    step=$((step + 1))
done

echo -e "\n${CYAN}======================================================${NC}"
if [ "$fail_count" -eq 0 ]; then
    echo -e "${BOLD}${GREEN}  [SUCCESS] All ${total_count} servers restarted cleanly with 0 collisions!  ${NC}"
else
    echo -e "${BOLD}${YELLOW}  [COMPLETED] ${success_count}/${total_count} servers online. (${fail_count} had warnings)  ${NC}"
fi
echo -e "${CYAN}======================================================${NC}"
