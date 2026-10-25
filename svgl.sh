#!/bin/bash
# =========================================================
# SVGL - GameLand Server Manager
# Single-server compatible, multi-instance ready.
# =========================================================
set -euo pipefail

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

SVGL_REAL="$(readlink -f "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$SVGL_REAL")"
if [[ "$PROJECT_DIR" == "/usr/local/bin" ]]; then
    PROJECT_DIR="/opt/gameland/server"
fi

LEGACY_SERVICE="gameland.service"
INSTANCE_ROOT_DEFAULT="/opt/gameland/instances"
INSTANCES_DIR="${PROJECT_DIR}/instances"
REGISTRY_FILE="${INSTANCES_DIR}/servers.json"
TEMPLATE_SERVICE_SRC="${PROJECT_DIR}/gameland@.service"
TEMPLATE_SERVICE_DEST="/etc/systemd/system/gameland@.service"

usage() {
    cat <<EOF
SVGL - GameLand Server Manager

Usage:
  svgl                         Interactive menu
  svgl list                    List all servers
  svgl add <id> <port> [name]  Create a new isolated server instance
  svgl remove <id> [--purge]   Disable and remove an instance; --purge also deletes its files
  svgl start [id|main]         Start server
  svgl stop [id|main]          Stop server
  svgl restart [id|main]       Restart server
  svgl restart-all             Safe staggered restart of ALL servers (2.5s delay)
  svgl start-all               Sequentially start any stopped servers
  svgl stop-all                Safely stop all servers cleanly
  svgl status [id|main]        Show service status
  svgl console [id|main]       Attach to tmux console
  svgl logs [id|main]          Follow systemd logs
  svgl tail [id|main]          Follow server log file
  svgl update                  Safely update server from GitHub (Zero data loss)
  svgl build [id|main]         Compile and deploy plugins specifically for one server
  svgl sync-plugins <id>       Copy updated plugins to specific instance (independent)
  svgl backup [note]           Create full atomic VPS checkpoint snapshot
  svgl restore [id|latest]     Restore full VPS state from checkpoint
  svgl checkpoint              Manage VPS checkpoints (create, list, restore, delete)
  svgl recover                 Recover lost admin accounts with chronological filter
  svgl sync                    Recover & auto-sync all created server instances
  svgl capacity                Analyze CPU & RAM to show how many servers can run
  svgl install-template        Install gameland@.service template

The web panel uses the same registry and SVGL commands. No server needs to be
added manually to config.php.

Examples:
  svgl add cs2 27016 "GameLand #2"
  svgl start cs2
  svgl console cs2
EOF
}

ensure_registry() {
    mkdir -p "$INSTANCES_DIR"
    mkdir -p /opt/gameland/persistent 2>/dev/null || true
    if [[ ! -f "$REGISTRY_FILE" ]]; then
        if [[ -f "/opt/gameland/persistent/servers.json" ]]; then
            cp -f "/opt/gameland/persistent/servers.json" "$REGISTRY_FILE"
        else
            printf '{\n  "servers": []\n}\n' > "$REGISTRY_FILE"
        fi
    fi
    for reg_f in "$REGISTRY_FILE" "/opt/gameland/persistent/servers.json"; do
        if [[ -f "$reg_f" ]]; then
            python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: d = json.load(f)
    if isinstance(d.get("servers"), list):
        filtered = [s for s in d["servers"] if s.get("id") and s.get("id") != "main"]
        if len(filtered) != len(d["servers"]):
            d["servers"] = filtered
            with open(sys.argv[1], "w") as f: json.dump(d, f, indent=2)
except Exception: pass
' "$reg_f" 2>/dev/null || true
        fi
    done
    if [[ -d "${PROJECT_DIR}/cstrike/addons/amxmodx/configs" ]]; then
        chmod -R 777 "${PROJECT_DIR}/cstrike/addons/amxmodx/configs" 2>/dev/null || true
        chmod 666 "${PROJECT_DIR}/cstrike/addons/amxmodx/configs/"*.ini 2>/dev/null || true
        chown -R www-data:www-data "${PROJECT_DIR}/cstrike/addons/amxmodx/configs" 2>/dev/null || true
    fi
}

need_root_for_systemd() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        echo -e "${RED}[ERROR] Run this command as root/sudo.${NC}"
        exit 1
    fi
}

install_template() {
    need_root_for_systemd
    if [[ ! -f "$TEMPLATE_SERVICE_SRC" ]]; then
        echo -e "${RED}[ERROR] Missing template: $TEMPLATE_SERVICE_SRC${NC}"
        exit 1
    fi
    sed "s|/opt/gameland/server|${PROJECT_DIR}|g" "$TEMPLATE_SERVICE_SRC" > "$TEMPLATE_SERVICE_DEST"
    chmod 644 "$TEMPLATE_SERVICE_DEST"
    systemctl daemon-reload
    echo -e "${GREEN}[OK] Installed ${TEMPLATE_SERVICE_DEST}${NC}"
}

service_name_for() {
    local id="${1:-main}"
    if [[ "$id" == "main" || -z "$id" ]]; then
        echo "$LEGACY_SERVICE"
    else
        echo "gameland@${id}.service"
    fi
}

tmux_name_for() {
    local id="${1:-main}"
    if [[ "$id" == "main" || -z "$id" ]]; then
        echo "gameland_server"
    else
        echo "gameland_${id}"
    fi
}

log_file_for() {
    local id="${1:-main}"
    if [[ "$id" == "main" || -z "$id" ]]; then
        echo "${PROJECT_DIR}/logs/server.log"
        return
    fi
    local env_file="${INSTANCES_DIR}/${id}.env"
    local server_dir="${INSTANCE_ROOT_DEFAULT}/${id}"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
        server_dir="${SERVER_DIR:-$server_dir}"
    fi
    echo "${server_dir}/logs/server_${id}.log"
}

is_running() {
    local id="${1:-main}"
    local svc tmux_name
    svc="$(service_name_for "$id")"
    tmux_name="$(tmux_name_for "$id")"

    command -v systemctl >/dev/null 2>&1 || return 1
    systemctl is-active --quiet "$svc" 2>/dev/null || return 1
    tmux has-session -t "$tmux_name" 2>/dev/null || return 1
    return 0
}

control_server() {
    local action="$1"
    local id="${2:-main}"
    local svc
    svc="$(service_name_for "$id")"
    if [[ "$id" != "main" && ! -f "$TEMPLATE_SERVICE_DEST" ]]; then
        install_template
    fi
    systemctl "$action" "$svc"
}

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

registry_append() {
    local id="$1" name="$2" port="$3" dir="$4" rcon="$5" mode="${6:-clanwar}" slots="${7:-10}"
    ensure_registry

    php -r '
        $file = $argv[1];
        $id = $argv[2];
        $data = json_decode(@file_get_contents($file), true);
        if (!is_array($data)) $data = ["servers" => []];
        if (!isset($data["servers"]) || !is_array($data["servers"])) $data["servers"] = [];
        foreach ($data["servers"] as &$server) {
            if (($server["id"] ?? "") === $id) {
                $server["name"] = $argv[3];
                $server["hostname"] = $argv[3];
                $server["mode"] = $argv[7] ?? "clanwar";
                $server["slots"] = (int)($argv[8] ?? 10);
                file_put_contents($file, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
                @mkdir("/opt/gameland/persistent", 0777, true);
                @file_put_contents("/opt/gameland/persistent/servers.json", json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
                exit(0);
            }
        }
        $data["servers"][] = [
            "id" => $id,
            "name" => $argv[3],
            "hostname" => $argv[3],
            "ip" => "127.0.0.1",
            "port" => (int)$argv[4],
            "rcon_password" => $argv[5],
            "service_name" => "gameland@" . $id . ".service",
            "server_dir" => $argv[6],
            "mode" => $argv[7] ?? "clanwar",
            "slots" => (int)($argv[8] ?? 10),
        ];
        $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
        file_put_contents($file, $json);
        @mkdir("/opt/gameland/persistent", 0777, true);
        @file_put_contents("/opt/gameland/persistent/servers.json", $json);
    ' "$REGISTRY_FILE" "$id" "$name" "$port" "$rcon" "$dir" "$mode" "$slots"
}

registry_remove() {
    local id="$1"
    ensure_registry
    php -r '
        $file = $argv[1];
        $id = $argv[2];
        $data = json_decode(@file_get_contents($file), true);
        if (!is_array($data)) $data = ["servers" => []];
        $data["servers"] = array_values(array_filter($data["servers"] ?? [], fn($s) => ($s["id"] ?? "") !== $id));
        $json = json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n";
        file_put_contents($file, $json);
        @mkdir("/opt/gameland/persistent", 0777, true);
        @file_put_contents("/opt/gameland/persistent/servers.json", $json);
    ' "$REGISTRY_FILE" "$id"
}

read_rcon_password() {
    local cfg="$1/cstrike/server.cfg"
    if [[ -f "$cfg" ]]; then
        local value
        value="$(grep -E '^[[:space:]]*rcon_password[[:space:]]+' "$cfg" | tail -n 1 | sed -E 's/^[[:space:]]*rcon_password[[:space:]]+"?([^"]+)"?.*/\1/' || true)"
        if [[ -n "$value" ]]; then
            echo "$value"
            return
        fi
    fi
    echo "GameLand@Rcon2026"
}

create_instance() {
    need_root_for_systemd
    local id="${1:-}" port="${2:-}" name="${3:-}" slots="${4:-}" mode="${5:-clanwar}"
    if [[ -z "$id" || -z "$port" ]]; then
        echo -e "${RED}[ERROR] Usage: svgl add <id> <port> [name] [slots] [mode]${NC}"
        exit 1
    fi
    if [[ ! "$id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo -e "${RED}[ERROR] Instance id may contain only letters, numbers, underscore and dash.${NC}"
        exit 1
    fi
    if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1024 || "$port" -gt 65535 ]]; then
        echo -e "${RED}[ERROR] Invalid port: $port${NC}"
        exit 1
    fi
    name="${name:-GameLand CS 1.6 ${id}}"

    if [[ -z "$slots" || "$slots" -lt 1 ]]; then
        if [[ "$mode" == "clanwar" ]]; then
            slots="10"
        elif [[ "$mode" == "mix5v5" ]]; then
            slots="18"
        elif [[ "$mode" == "public" ]]; then
            slots="24"
        else
            slots="10"
        fi
    fi

    ensure_registry
    if php -r '
        $j = json_decode(@file_get_contents($argv[1]), true);
        foreach (($j["servers"] ?? []) as $s) {
            if ((int)($s["port"] ?? 0) === (int)$argv[2]) exit(0);
        }
        exit(1);
    ' "$REGISTRY_FILE" "$port"; then
        echo -e "${RED}[ERROR] Port ${port} is already assigned to another registered server.${NC}"
        exit 1
    fi
    install_template

    local target="${INSTANCE_ROOT_DEFAULT}/${id}"
    if [[ -e "$target" ]]; then
        echo -e "${RED}[ERROR] Instance directory already exists: $target${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Creating instance '${id}' on port ${port} (Mode: ${mode}, Slots: ${slots})...${NC}"
    mkdir -p "$INSTANCE_ROOT_DEFAULT"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a \
            --exclude='.git' \
            --exclude='logs/*' \
            --exclude='*.pid' \
            --exclude='panel' \
            --exclude='instances/*.env' \
            "$PROJECT_DIR/" "$target/"
    else
        cp -a "$PROJECT_DIR" "$target"
        rm -rf "$target/.git" "$target/logs" "$target/panel" "$target/instances"
        mkdir -p "$target/logs"
    fi

    mkdir -p "$target/logs"
    local rcon
    rcon="$(read_rcon_password "$target")"

    cat > "${INSTANCES_DIR}/${id}.env" <<EOF
INSTANCE_ID="${id}"
SERVER_DIR="${target}"
SERVER_IP="0.0.0.0"
SERVER_PORT="${port}"
SERVER_NAME="${name}"
HOSTNAME="${name}"
MAX_PLAYERS="${slots}"
MAP="de_dust2"
TMUX_SESSION="gameland_${id}"
STEAMCMD_LINUX32="/opt/steamcmd/linux32"
EOF

    # Configure server.cfg
    if [[ -f "$target/cstrike/server.cfg" ]]; then
        sed -i -E "s/^[[:space:]]*sv_visiblemaxplayers[[:space:]]+[0-9]+/sv_visiblemaxplayers $slots/" "$target/cstrike/server.cfg" 2>/dev/null || true
        if ! grep -q 'sv_visiblemaxplayers' "$target/cstrike/server.cfg"; then
            echo "sv_visiblemaxplayers $slots" >> "$target/cstrike/server.cfg"
        fi
        sed -i -E "s/^[[:space:]]*hostname[[:space:]]+.*/hostname \"${name}\"/" "$target/cstrike/server.cfg" 2>/dev/null || true
        sed -i -E "s/^[[:space:]]*cw_base_hostname[[:space:]]+.*/cw_base_hostname \"${name}\"/" "$target/cstrike/server.cfg" 2>/dev/null || true
        if ! grep -q 'cw_base_hostname' "$target/cstrike/server.cfg"; then
            echo "cw_base_hostname \"${name}\"" >> "$target/cstrike/server.cfg"
        fi
        sed -i -E "s/^[[:space:]]*mix_base_hostname[[:space:]]+.*/mix_base_hostname \"${name}\"/" "$target/cstrike/server.cfg" 2>/dev/null || true
        if ! grep -q 'mix_base_hostname' "$target/cstrike/server.cfg"; then
            echo "mix_base_hostname \"${name}\"" >> "$target/cstrike/server.cfg"
        fi
    fi

    # Configure plugins.ini for the selected mode
    local plugins_ini="$target/cstrike/addons/amxmodx/configs/plugins.ini"
    if [[ -f "$plugins_ini" ]]; then
        if [[ "$mode" == "clanwar" ]]; then
            sed -i -E 's/^[[:space:]]*;?[[:space:]]*clanwar_system\.amxx([[:space:]].*)?$/clanwar_system.amxx/' "$plugins_ini" 2>/dev/null || true
            if ! grep -q 'clanwar_system\.amxx' "$plugins_ini"; then
                echo "clanwar_system.amxx" >> "$plugins_ini"
            fi
            sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$plugins_ini" 2>/dev/null || true
        elif [[ "$mode" == "mix5v5" ]]; then
            sed -i -E 's/^[[:space:]]*;?[[:space:]]*mix_system\.amxx([[:space:]].*)?$/mix_system.amxx/' "$plugins_ini" 2>/dev/null || true
            if ! grep -q 'mix_system\.amxx' "$plugins_ini"; then
                echo "mix_system.amxx" >> "$plugins_ini"
            fi
            sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$plugins_ini" 2>/dev/null || true
        elif [[ "$mode" == "public" ]]; then
            sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$plugins_ini" 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$plugins_ini" 2>/dev/null || true
        fi
    fi

    registry_append "$id" "$name" "$port" "$target" "$rcon" "$mode" "$slots"
    chmod +x "${PROJECT_DIR}/start_instance.sh" "${PROJECT_DIR}/stop_instance.sh" "${PROJECT_DIR}/svgl.sh"
    chmod 775 "$INSTANCES_DIR" "$REGISTRY_FILE" "${INSTANCES_DIR}/${id}.env" 2>/dev/null || true
    if id www-data >/dev/null 2>&1; then
        chown -R www-data:www-data "$target" 2>/dev/null || true
        chown -R www-data:www-data "$INSTANCES_DIR" 2>/dev/null || true
    fi
    if [[ -f "$TEMPLATE_SERVICE_SRC" ]]; then
        cp -f "$TEMPLATE_SERVICE_SRC" "$TEMPLATE_SERVICE_DEST" 2>/dev/null || true
        chmod 644 "$TEMPLATE_SERVICE_DEST" 2>/dev/null || true
    fi
    systemctl daemon-reload
    systemctl enable "gameland@${id}.service"

    echo -e "${GREEN}[OK] Instance created with mode '${mode}' and ${slots} slots.${NC}"
    echo "  Service : gameland@${id}.service"
    echo "  Dir     : $target"
    echo "  Port    : $port"
    echo "  Start   : svgl start $id"
}

remove_instance() {
    need_root_for_systemd
    local id="${1:-}"
    local purge="${2:-}"
    if [[ -z "$id" || "$id" == "main" ]]; then
        echo -e "${RED}[ERROR] Usage: svgl remove <id> [--purge]${NC}"
        exit 1
    fi
    local env_file="${INSTANCES_DIR}/${id}.env"
    local server_dir="${INSTANCE_ROOT_DEFAULT}/${id}"
    if [[ -f "$env_file" ]]; then
        # shellcheck disable=SC1090
        source "$env_file"
        server_dir="${SERVER_DIR:-$server_dir}"
    fi

    systemctl disable --now "gameland@${id}.service" 2>/dev/null || true
    "${PROJECT_DIR}/stop_instance.sh" "$id" 2>/dev/null || true
    registry_remove "$id"
    rm -f "$env_file"
    systemctl daemon-reload

    if [[ "$purge" == "--purge" ]]; then
        local resolved_root resolved_target
        resolved_root="$(readlink -f "$INSTANCE_ROOT_DEFAULT" 2>/dev/null || true)"
        resolved_target="$(readlink -f "$server_dir" 2>/dev/null || true)"
        if [[ -z "$resolved_root" || -z "$resolved_target" || "$resolved_target" != "$resolved_root/$id" ]]; then
            echo -e "${RED}[ERROR] Refusing to purge unsafe path: ${server_dir}${NC}"
            echo -e "${YELLOW}Registry/env were removed, but files were kept for safety.${NC}"
            exit 1
        fi
        rm -rf -- "$resolved_target"
        echo -e "${GREEN}[OK] Instance '${id}' removed and files purged from ${resolved_target}.${NC}"
        return
    fi

    echo -e "${GREEN}[OK] Instance '${id}' removed from systemd and panel registry.${NC}"
    echo -e "${YELLOW}Note: server files were kept under ${server_dir}. Use: svgl remove ${id} --purge to delete them too.${NC}"
}

list_servers() {
    ensure_registry
    printf "%-14s %-28s %-8s %-28s %-10s\n" "ID" "SERVICE" "PORT" "TMUX" "STATUS"
    printf "%-14s %-28s %-8s %-28s %-10s\n" "main" "$LEGACY_SERVICE" "27015" "gameland_server" "$(is_running main && echo running || echo stopped)"

    if command -v php >/dev/null 2>&1; then
        php -r '
            $f = $argv[1];
            $j = json_decode(@file_get_contents($f), true);
            foreach (($j["servers"] ?? []) as $s) {
                $id = $s["id"] ?? "";
                if ($id === "" || $id === "main") continue;
                $tmux = "gameland_$id";
                $svc = $s["service_name"] ?? ("gameland@$id.service");
                printf("%-14s %-28s %-8s %-28s ", $id, $svc, $s["port"] ?? "-", $tmux);
                $status = "stopped";
                $res = @exec("systemctl is-active --quiet " . escapeshellarg($svc) . " 2>/dev/null && tmux has-session -t " . escapeshellarg($tmux) . " 2>/dev/null && echo running || echo stopped");
                if (trim((string)$res) === "running") {
                    $status = "running";
                }
                echo $status . "\n";
            }
        ' "$REGISTRY_FILE"
    else
        grep -E '"id"|"port"|"service_name"' "$REGISTRY_FILE" || true
    fi
}

attach_console() {
    local id="${1:-main}"
    local tmux_name
    tmux_name="$(tmux_name_for "$id")"
    if tmux has-session -t "$tmux_name" 2>/dev/null; then
        tmux attach -t "$tmux_name"
    else
        echo -e "${RED}tmux session not found: ${tmux_name}${NC}"
        exit 1
    fi
}

pause_menu() {
    read -r -p "  Press Enter to continue..."
}

server_rows() {
    ensure_registry
    echo "main|GameLand Main|27015|$LEGACY_SERVICE|gameland_server|$(is_running main && echo running || echo stopped)"
    if command -v php >/dev/null 2>&1; then
        php -r '
            $f = $argv[1];
            $j = json_decode(@file_get_contents($f), true);
            foreach (($j["servers"] ?? []) as $s) {
                $id = $s["id"] ?? "";
                if ($id === "" || $id === "main") continue;
                $service = $s["service_name"] ?? ("gameland@$id.service");
                $status = trim(shell_exec("systemctl is-active " . escapeshellarg($service) . " 2>/dev/null")) === "active" ? "running" : "stopped";
                echo $id . "|" . ($s["name"] ?? $id) . "|" . ($s["port"] ?? "-") . "|" . $service . "|gameland_" . $id . "|" . $status . "\n";
            }
        ' "$REGISTRY_FILE"
    fi
}

print_numbered_servers() {
    local index=1 row id name port svc tmux_name status color
    while IFS='|' read -r id name port svc tmux_name status; do
        [[ -z "$id" ]] && continue
        color="$RED"
        [[ "$status" == "running" ]] && color="$GREEN"
        printf "  %2d) %-14s %-28s port:%-6s ${color}%-8s${NC} service:%s\n" \
            "$index" "$id" "$name" "$port" "$status" "$svc"
        index=$((index + 1))
    done < <(server_rows)
}

select_server_id() {
    local prompt="${1:-Select server number}"
    local rows=()
    local row choice
    while IFS= read -r row; do
        [[ -n "$row" ]] && rows+=("$row")
    done < <(server_rows)

    if [[ "${#rows[@]}" -eq 0 ]]; then
        echo ""
        return
    fi

    print_numbered_servers >&2
    echo -e "   0) Back" >&2
    read -r -p "  ${prompt}: " choice >&2
    if [[ "$choice" == "0" || -z "$choice" ]]; then
        echo ""
        return
    fi
    if [[ ! "$choice" =~ ^[0-9]+$ || "$choice" -lt 1 || "$choice" -gt "${#rows[@]}" ]]; then
        echo ""
        return
    fi
    IFS='|' read -r selected_id _ <<< "${rows[$((choice - 1))]}"
    echo "$selected_id"
}

set_cfg_value() {
    local cfg="$1" key="$2" value="$3"
    mkdir -p "$(dirname "$cfg")"
    touch "$cfg"
    if grep -Eq "^[[:space:]]*${key}[[:space:]]+" "$cfg"; then
        sed -i -E "s|^[[:space:]]*${key}[[:space:]]+.*|${key} \"${value//\"/}\"|" "$cfg"
    else
        echo "${key} \"${value//\"/}\"" >> "$cfg"
    fi
}

set_env_value() {
    local env_file="$1" key="$2" value="$3"
    touch "$env_file"
    if grep -Eq "^${key}=" "$env_file"; then
        sed -i -E "s|^${key}=.*|${key}=\"${value//\"/}\"|" "$env_file"
    else
        echo "${key}=\"${value//\"/}\"" >> "$env_file"
    fi
}

set_start_value() {
    local start_file="$1" key="$2" value="$3"
    if [[ ! -f "$start_file" ]]; then
        echo -e "${RED}[ERROR] start.sh not found: ${start_file}${NC}"
        return 1
    fi
    if grep -Eq "^${key}=" "$start_file"; then
        sed -i -E "s|^${key}=.*|${key}=\"${value//\"/}\"|" "$start_file"
    else
        echo "${key}=\"${value//\"/}\"" >> "$start_file"
    fi
}

update_registry_field() {
    local id="$1" field="$2" value="$3"
    php -r '
        $file = $argv[1]; $id = $argv[2]; $field = $argv[3]; $value = $argv[4];
        $data = json_decode(@file_get_contents($file), true);
        if (!is_array($data)) exit(1);
        foreach ($data["servers"] ?? [] as &$s) {
            if (($s["id"] ?? "") === $id) {
                $s[$field] = ($field === "port") ? (int)$value : $value;
                break;
            }
        }
        file_put_contents($file, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
    ' "$REGISTRY_FILE" "$id" "$field" "$value"
}

edit_server_settings() {
    local id="$1" env_file server_dir current_port current_slots current_map current_name
    if [[ "$id" == "main" ]]; then
        server_dir="$PROJECT_DIR"
        current_name="GameLand Main"
    else
        env_file="${INSTANCES_DIR}/${id}.env"
        if [[ ! -f "$env_file" ]]; then
            echo -e "${RED}[ERROR] Instance env not found: ${env_file}${NC}"
            pause_menu
            return
        fi
        # shellcheck disable=SC1090
        source "$env_file"
        server_dir="${SERVER_DIR:-${INSTANCE_ROOT_DEFAULT}/${id}}"
        current_name="$id"
    fi

    echo -e "${CYAN}Editing server: ${BOLD}${id}${NC}"
    read -r -p "  Panel name (empty = keep): " new_name
    read -r -p "  In-game hostname (empty = keep): " new_hostname
    read -r -p "  Port (empty = keep): " new_port
    read -r -p "  Slots 1-32 (empty = keep): " new_slots
    read -r -p "  Start map (empty = keep): " new_map

    if [[ -n "$new_port" && ! "$new_port" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[ERROR] Invalid port.${NC}"
        pause_menu
        return
    fi
    if [[ -n "$new_slots" && ( ! "$new_slots" =~ ^[0-9]+$ || "$new_slots" -lt 1 || "$new_slots" -gt 32 ) ]]; then
        echo -e "${RED}[ERROR] Invalid slots. Use 1-32.${NC}"
        pause_menu
        return
    fi

    local effective_host="${new_hostname:-$new_name}"
    if [[ -n "$effective_host" ]]; then
        set_cfg_value "${server_dir}/cstrike/server.cfg" "hostname" "$effective_host"
        set_cfg_value "${server_dir}/cstrike/server.cfg" "cw_base_hostname" "$effective_host"
        set_cfg_value "${server_dir}/cstrike/server.cfg" "mix_base_hostname" "$effective_host"
    fi

    if [[ "$id" == "main" ]]; then
        [[ -n "$new_port" ]] && set_start_value "${server_dir}/start.sh" "SERVER_PORT" "$new_port"
        [[ -n "$new_slots" ]] && set_start_value "${server_dir}/start.sh" "MAX_PLAYERS" "$new_slots"
        [[ -n "$new_map" ]] && set_start_value "${server_dir}/start.sh" "MAP" "$new_map"
        [[ -n "$new_name" ]] && set_start_value "${server_dir}/start.sh" "SERVER_NAME" "$new_name"
        [[ -n "$effective_host" ]] && set_start_value "${server_dir}/start.sh" "HOSTNAME" "$effective_host"
    else
        [[ -n "$new_name" ]] && { update_registry_field "$id" "name" "$new_name"; set_env_value "$env_file" "SERVER_NAME" "$new_name"; }
        [[ -n "$effective_host" ]] && { update_registry_field "$id" "hostname" "$effective_host"; set_env_value "$env_file" "HOSTNAME" "$effective_host"; }
        [[ -n "$new_port" ]] && { set_env_value "$env_file" "SERVER_PORT" "$new_port"; update_registry_field "$id" "port" "$new_port"; }
        [[ -n "$new_slots" ]] && set_env_value "$env_file" "MAX_PLAYERS" "$new_slots"
        [[ -n "$new_map" ]] && set_env_value "$env_file" "MAP" "$new_map"
    fi

    echo -e "${GREEN}[OK] Settings saved. Restart the server to apply runtime launch changes.${NC}"
    pause_menu
}

server_action_menu() {
    local id="$1"
    [[ -z "$id" ]] && return
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${BOLD}${GREEN}       Server Operations: ${id}       ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        list_servers | awk -v id="$id" 'NR==1 || $1==id { print }'
        echo -e "${CYAN}------------------------------------------${NC}"
        echo -e "  1) ${GREEN}Start${NC}"
        echo -e "  2) ${RED}Stop${NC}"
        echo -e "  3) ${YELLOW}Restart${NC}"
        echo -e "  4) Open ${CYAN}Live Console${NC}"
        echo -e "  5) View ${CYAN}systemd Logs${NC}"
        echo -e "  6) View ${CYAN}Server Log File${NC}"
        echo -e "  7) Edit Name / Hostname / Port / Slots / Map"
        if [[ "$id" != "main" ]]; then
            echo -e "  8) ${YELLOW}Remove from Manager${NC} (keep files)"
            echo -e "  9) ${RED}Purge Completely${NC} (delete files)"
        fi
        echo -e "  0) Back"
        echo -e "${CYAN}==========================================${NC}"
        read -r -p "  Select: " act
        case "$act" in
            1) control_server start "$id"; pause_menu ;;
            2) control_server stop "$id"; pause_menu ;;
            3) control_server restart "$id"; pause_menu ;;
            4) attach_console "$id" ;;
            5) journalctl -u "$(service_name_for "$id")" -f ;;
            6) tail -f "$(log_file_for "$id")" ;;
            7) edit_server_settings "$id" ;;
            8)
                [[ "$id" == "main" ]] && continue
                read -r -p "  Remove '${id}' from manager but keep files? [yes/NO]: " ok
                [[ "$ok" == "yes" ]] && remove_instance "$id" && return
                ;;
            9)
                [[ "$id" == "main" ]] && continue
                read -r -p "  PURGE '${id}' and delete its files? Type PURGE: " ok
                [[ "$ok" == "PURGE" ]] && remove_instance "$id" "--purge" && return
                ;;
            0) return ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

servers_browser_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${CYAN}==========================================${NC}"
        echo -e "${BOLD}${GREEN}              SVGL Servers               ${NC}"
        echo -e "${CYAN}==========================================${NC}"
        local id
        id="$(select_server_id "Select server number")"
        if [[ -z "$id" ]]; then
            return
        fi
        server_action_menu "$id"
    done
}

sync_plugins_to_instance() {
    local id="${1:-}"
    if [[ -z "$id" ]]; then
        echo -e "${RED}[ERROR] Usage: svgl sync-plugins <id|all>${NC}"
        return 1
    fi
    if [[ "$id" == "all" ]]; then
        bash "${PROJECT_DIR}/install_mix.sh" --sync-all
        return 0
    fi
    bash "${PROJECT_DIR}/install_mix.sh" --instance "$id"
}

build_server_plugins() {
    local id="${1:-main}"
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${BOLD}${GREEN}  Compiling Plugins Exclusively for: ${id}  ${NC}"
    echo -e "${CYAN}==========================================${NC}"

    if [[ "$id" == "main" || -z "$id" ]]; then
        bash "${PROJECT_DIR}/install_mix.sh"
    else
        bash "${PROJECT_DIR}/install_mix.sh" --instance "$id"
    fi
    echo -e "${GREEN}[DONE] Server '${id}' compiled and updated with zero impact on other servers!${NC}"
}

check_server_capacity() {
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${BOLD}${GREEN}   GameLand Server Hardware & Capacity   ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    local cores
    cores=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1)
    local model
    model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^[ \t]*//' || echo "Unknown CPU")
    local mem_total
    mem_total=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo 1024)
    local mem_avail
    mem_avail=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}' || echo 512)
    local load
    load=$(uptime 2>/dev/null | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//' || echo "N/A")

    echo -e "  ${BOLD}CPU Model:${NC}     $model"
    echo -e "  ${BOLD}CPU Cores:${NC}     $cores Cores / Threads"
    echo -e "  ${BOLD}Total RAM:${NC}     $((mem_total / 1024)) GB ($mem_total MB)"
    echo -e "  ${BOLD}Available RAM:${NC} $((mem_avail / 1024)) GB ($mem_avail MB)"
    echo -e "  ${BOLD}Current Load:${NC}  $load"
    echo -e "${CYAN}------------------------------------------${NC}"
    
    local max_by_cpu=$((cores * 2))
    local max_by_ram=$((mem_total / 250))
    local recommended=$max_by_cpu
    if [ "$max_by_ram" -lt "$recommended" ]; then
        recommended=$max_by_ram
    fi
    if [ "$recommended" -lt 1 ]; then
        recommended=1
    fi

    echo -e "  ${YELLOW}💡 Capacity Analysis for CS 1.6 (1000 FPS / 18 Slots):${NC}"
    echo -e "  - Each instance uses ~150-250 MB RAM and ~20-35% of a CPU core."
    echo -e "  - ${GREEN}${BOLD}Recommended Active Servers:${NC} ${GREEN}${recommended} servers${NC} simultaneously"
    echo -e "  - Maximum servers under light/mix load: ${YELLOW}$((recommended + 2)) servers${NC}"
    echo -e "${CYAN}==========================================${NC}"
}

show_menu() {
    clear 2>/dev/null || true
    echo -e "${CYAN}==========================================${NC}"
    echo -e "${BOLD}${GREEN}      SVGL - GameLand Server Manager      ${NC}"
    echo -e "${CYAN}==========================================${NC}"
    printf "  Main: "
    if is_running main; then
        echo -e "${GREEN}[ RUNNING ]${NC}"
    else
        echo -e "${RED}[ STOPPED ]${NC}"
    fi
    echo -e "${CYAN}------------------------------------------${NC}"
    echo -e "  1) ${CYAN}Servers${NC} (select and manage)"
    echo -e "  2) ${GREEN}Add New Server Instance${NC}"
    echo -e "  3) ${YELLOW}Update from GitHub (Safe Update)${NC}"
    echo -e "  4) List Servers"
    echo -e "  5) ${CYAN}Recover Admin Accounts${NC} (Smart Filter)"
    echo -e "  6) ${CYAN}Recover / Sync Server Instances${NC} (Rebuild servers.json)"
    echo -e "  7) ${PURPLE}Check Server Capacity & Hardware Specs${NC}"
    echo -e "  8) ${YELLOW}⚡ Restart All Servers (Safe Staggered)${NC}"
    echo -e "  9) ${GREEN}▶ Start All Offline Servers${NC}"
    echo -e "  10) ${YELLOW}💾 VPS Checkpoints / Backups${NC}"
    echo -e "  0) Exit"
    echo -e "${CYAN}==========================================${NC}"
}

interactive_loop() {
    while true; do
        show_menu
        read -r -p "  Select [0-10]: " choice
        case "$choice" in
            1) servers_browser_menu ;;
            2)
                read -r -p "  Instance id (example: cs2): " id
                read -r -p "  Port (example: 27016): " port
                read -r -p "  Display name: " name
                create_instance "$id" "$port" "$name"
                sleep 3
                ;;
            3) bash "${PROJECT_DIR}/update.sh"; pause_menu ;;
            4) list_servers; pause_menu ;;
            5) bash "${PROJECT_DIR}/recover_admins.sh"; pause_menu ;;
            6) bash "${PROJECT_DIR}/recover_servers.sh"; pause_menu ;;
            7) check_server_capacity; pause_menu ;;
            8) bash "${PROJECT_DIR}/restart_all.sh"; pause_menu ;;
            9) bash "${PROJECT_DIR}/start_all.sh"; pause_menu ;;
            10)
                echo -e "\n  1) Create New Checkpoint"
                echo -e "  2) List Checkpoints"
                echo -e "  3) Restore Latest Checkpoint"
                read -r -p "  Select [1-3]: " cp_choice
                case "$cp_choice" in
                    1) read -r -p "  Checkpoint label/note: " cp_note; bash "${PROJECT_DIR}/checkpoint.sh" create "$cp_note" ;;
                    2) bash "${PROJECT_DIR}/checkpoint.sh" list ;;
                    3) bash "${PROJECT_DIR}/checkpoint.sh" restore latest ;;
                esac
                pause_menu
                ;;
            0) exit 0 ;;
            *) echo -e "${RED}Invalid option.${NC}"; sleep 1 ;;
        esac
    done
}

cmd="${1:-menu}"
case "$cmd" in
    menu) interactive_loop ;;
    help|-h|--help) usage ;;
    list) list_servers ;;
    add) shift; create_instance "$@" ;;
    remove|rm) shift; remove_instance "$@" ;;
    restart-all|restart_all) bash "${PROJECT_DIR}/restart_all.sh" ;;
    start-all|start_all) bash "${PROJECT_DIR}/start_all.sh" ;;
    stop-all|stop_all) bash "${PROJECT_DIR}/stop_all.sh" ;;
    start|stop|restart|status)
        action="$cmd"
        id="${2:-main}"
        if [[ "$id" == "all" ]]; then
            if [[ "$action" == "restart" ]]; then
                bash "${PROJECT_DIR}/restart_all.sh"
            elif [[ "$action" == "start" ]]; then
                bash "${PROJECT_DIR}/start_all.sh"
            elif [[ "$action" == "stop" ]]; then
                bash "${PROJECT_DIR}/stop_all.sh"
            fi
        elif [[ "$action" == "status" ]]; then
            systemctl status "$(service_name_for "$id")" --no-pager
        else
            control_server "$action" "$id"
        fi
        ;;
    console) attach_console "${2:-main}" ;;
    logs)
        lfile="$(log_file_for "${2:-main}")"
        if [[ -f "$lfile" ]]; then
            tail -n 50 -f "$lfile"
        else
            journalctl -u "$(service_name_for "${2:-main}")" -f
        fi
        ;;
    tail) tail -f "$(log_file_for "${2:-main}")" ;;
    update) bash "${PROJECT_DIR}/update.sh" ;;
    build|compile) shift; build_server_plugins "$@" ;;
    checkpoint) shift; bash "${PROJECT_DIR}/checkpoint.sh" "$@" ;;
    backup) shift; bash "${PROJECT_DIR}/checkpoint.sh" create "$@" ;;
    restore) shift; bash "${PROJECT_DIR}/checkpoint.sh" restore "$@" ;;
    recover|recover-admins) bash "${PROJECT_DIR}/recover_admins.sh" ;;
    sync|recover-servers) bash "${PROJECT_DIR}/recover_servers.sh" ;;
    sync-plugins) shift; sync_plugins_to_instance "$@" ;;
    capacity|specs) check_server_capacity ;;
    install-template) install_template ;;
    *) usage; exit 1 ;;
esac
