#!/bin/bash
# =========================================================
# GameLand CS 1.6 - Match Server 5v5 Installer & Compiler
# =========================================================

set -e

if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Please run as root: sudo bash install_mix.sh"
  exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
CONFIGS_DIR="${PROJECT_DIR}/cstrike/addons/amxmodx/configs"
SCRIPTING_DIR="${PROJECT_DIR}/cstrike/addons/amxmodx/scripting"
PLUGINS_DIR="${PROJECT_DIR}/cstrike/addons/amxmodx/plugins"
PLUGINS_INI="${CONFIGS_DIR}/plugins.ini"

# Ensure configs and *.ini are always world-writable
chmod -R 777 "${CONFIGS_DIR}" 2>/dev/null || true
chmod 666 "${CONFIGS_DIR}"/*.ini 2>/dev/null || true
chown -R www-data:www-data "${CONFIGS_DIR}" 2>/dev/null || true

# Auto-sanitize gameland.service and gameland@.service to guarantee 100% decoupling
needs_reload=0
rm -rf /etc/systemd/system/gameland*.service.d 2>/dev/null || true
if [ -f "${PROJECT_DIR}/gameland.service" ]; then
    if [ ! -f "/etc/systemd/system/gameland.service" ] || ! cmp -s "${PROJECT_DIR}/gameland.service" "/etc/systemd/system/gameland.service" 2>/dev/null; then
        cp -f "${PROJECT_DIR}/gameland.service" "/etc/systemd/system/gameland.service" 2>/dev/null || true
        chmod 644 "/etc/systemd/system/gameland.service" 2>/dev/null || true
        needs_reload=1
    fi
fi
if [ -f "${PROJECT_DIR}/gameland@.service" ]; then
    if [ ! -f "/etc/systemd/system/gameland@.service" ] || ! cmp -s "${PROJECT_DIR}/gameland@.service" "/etc/systemd/system/gameland@.service" 2>/dev/null; then
        cp -f "${PROJECT_DIR}/gameland@.service" "/etc/systemd/system/gameland@.service" 2>/dev/null || true
        chmod 644 "/etc/systemd/system/gameland@.service" 2>/dev/null || true
        needs_reload=1
    fi
fi
if [ "$needs_reload" -eq 1 ]; then
    systemctl daemon-reload 2>/dev/null || true
fi

# Parse operational mode flags
DO_SYNC_ALL=false
DO_RESTART=true
TARGET_INSTANCE=""

for arg in "$@"; do
    case "$arg" in
        --sync-all) DO_SYNC_ALL=true ;;
        --no-restart) DO_RESTART=false ;;
        --instance=*) TARGET_INSTANCE="${arg#*=}" ;;
    esac
done

if [ "${1:-}" = "--instance" ] && [ -n "${2:-}" ]; then
    TARGET_INSTANCE="$2"
fi

# Install or refresh dynamic forwarder wrapper to /usr/local/sbin/gameland-panel-sudo
cat > /usr/local/sbin/gameland-panel-sudo << EOF
#!/bin/bash
exec /bin/bash "${PROJECT_DIR}/panel/gameland-panel-sudo.sh" "\$@"
EOF
chmod 0755 /usr/local/sbin/gameland-panel-sudo 2>/dev/null || true

if [ "${1:-}" = "fixperms_only" ]; then
    echo "[OK] Permissions fixed."
    exit 0
fi

echo "================================================="
echo "   GameLand 5v5 Match Server - Setup & Compiler  "
echo "   Directory: ${PROJECT_DIR}"
echo "================================================="

# ─── 1. Ensure Compiler Execution Permission ────────────
echo "[1/5] Checking AMXX compiler & server binaries..."
chmod +x "${PROJECT_DIR}/hlds_linux" "${PROJECT_DIR}/hlds_run" "${PROJECT_DIR}"/*.sh 2>/dev/null || true
chmod +x "${SCRIPTING_DIR}/amxxpc" || true
chmod +x "${SCRIPTING_DIR}/amxxpc32.so" || true
export LD_LIBRARY_PATH=".:${SCRIPTING_DIR}:${LD_LIBRARY_PATH:-}"

# ─── 2. Compile mix_system.sma ──────────────────────────
echo "[2/5] Compiling mix_system.sma..."
cd "${SCRIPTING_DIR}"

if [ ! -f "mix_system.sma" ]; then
    echo "[ERROR] mix_system.sma not found in ${SCRIPTING_DIR}!"
    exit 1
fi

# Run amxxpc compiler
./amxxpc mix_system.sma -i"include" -o"${PLUGINS_DIR}/mix_system.amxx"
if [ ! -f "${PLUGINS_DIR}/mix_system.amxx" ]; then
    echo "[ERROR] Failed to compile mix_system.sma!"
    exit 1
fi
echo "  -> mix_system.amxx compiled successfully!"

# ─── 2b. Compile clanwar_system.sma ─────────────────────
if [ -f "clanwar_system.sma" ]; then
    echo "[2b/5] Compiling clanwar_system.sma..."
    ./amxxpc clanwar_system.sma -i"include" -o"${PLUGINS_DIR}/clanwar_system.amxx" || true
    if [ -f "${PLUGINS_DIR}/clanwar_system.amxx" ]; then
        echo "  -> clanwar_system.amxx compiled successfully!"
    fi
fi

# ─── 3. Compile mix_system_voice_chat.sma ───────────────
echo "[3/5] Compiling mix_system_voice_chat.sma..."
if [ -f "mix_system_voice_chat.sma" ]; then
    ./amxxpc mix_system_voice_chat.sma -i"include" -o"${PLUGINS_DIR}/mix_system_voice_chat.amxx"
    if [ ! -f "${PLUGINS_DIR}/mix_system_voice_chat.amxx" ]; then
        echo "[ERROR] Failed to compile mix_system_voice_chat.sma!"
        exit 1
    fi
    echo "  -> mix_system_voice_chat.amxx compiled successfully!"
fi

# Compile GAMELAND admin helpers (/map, /t1-/t3, /ff0-/ff1, /j0-/j2).
if [ -f "gameland_admin_tools.sma" ]; then
    echo "[3b/5] Compiling gameland_admin_tools.sma..."
    ./amxxpc gameland_admin_tools.sma -i"include" -o"${PLUGINS_DIR}/gameland_admin_tools.amxx"
    if [ ! -f "${PLUGINS_DIR}/gameland_admin_tools.amxx" ]; then
        echo "[ERROR] Failed to compile gameland_admin_tools.sma!"
        exit 1
    fi
    echo "  -> gameland_admin_tools.amxx compiled successfully!"
fi

# Compile GameLand Performance, Fixer, Weapons and Drop Plugins
for p in gameland_lan_optimizer gameland_sound_optimizer gameland_fastduck_fix gameland_only_enforcer player_drop backweapons; do
    if [ -f "${p}.sma" ]; then
        echo "[3c/5] Compiling ${p}.sma..."
        ./amxxpc "${p}.sma" -i"include" -o"${PLUGINS_DIR}/${p}.amxx" || true
        if [ -f "${PLUGINS_DIR}/${p}.amxx" ]; then
            echo "  -> ${p}.amxx compiled successfully!"
        fi
    fi
done

# Touch all compiled binaries to make sure mtime is fresher than .sma sources
touch "${PLUGINS_DIR}"/*.amxx 2>/dev/null || true

cd "${PROJECT_DIR}"

# ─── 4. Register in plugins.ini & modules.ini ───────────
echo "[4/5] Registering plugins and modules..."
MODULES_INI="${CONFIGS_DIR}/modules.ini"
if ! grep -qE '^[[:space:]]*nextclientapi([[:space:]]|$)' "${MODULES_INI}"; then
    printf '\nnextclientapi\n' >> "${MODULES_INI}"
    echo "  -> Ensured nextclientapi in modules.ini"
fi

# Detect and preserve active game mode for main server
# Priority chain: persistent/main_mode.txt -> instances/main_mode.txt -> modes.json -> plugins.ini -> last-resort
MAIN_MODE=""

# Source 1: /opt/gameland/persistent/main_mode.txt  (written by panel + switch_mode + compile)
if [ -f "/opt/gameland/persistent/main_mode.txt" ]; then
    _m="$(cat /opt/gameland/persistent/main_mode.txt | tr -d '[:space:]')"
    [[ "$_m" =~ ^(clanwar|mix5v5|public)$ ]] && MAIN_MODE="$_m"
fi

# Source 2: local copy beside PROJECT_DIR
if [ -z "$MAIN_MODE" ] && [ -f "${PROJECT_DIR}/instances/main_mode.txt" ]; then
    _m="$(cat "${PROJECT_DIR}/instances/main_mode.txt" | tr -d '[:space:]')"
    [[ "$_m" =~ ^(clanwar|mix5v5|public)$ ]] && MAIN_MODE="$_m"
fi

# Source 3: modes.json
if [ -z "$MAIN_MODE" ]; then
    for _mj in "/opt/gameland/persistent/modes.json" "${PROJECT_DIR}/instances/modes.json"; do
        if [ -f "$_mj" ]; then
            _m="$(python3 -c '
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(d.get("main",{}).get("mode",""))
except: print("")
' "$_mj" 2>/dev/null || true)"
            [[ "$_m" =~ ^(clanwar|mix5v5|public)$ ]] && { MAIN_MODE="$_m"; break; }
        fi
    done
fi

# Source 4: live plugins.ini (read what's actually active right now)
if [ -z "$MAIN_MODE" ] && [ -f "${PLUGINS_INI}" ]; then
    if grep -qE '^[[:space:]]*mix_system\.amxx([[:space:]]|$)' "${PLUGINS_INI}" 2>/dev/null; then
        MAIN_MODE="mix5v5"
    elif grep -qE '^[[:space:]]*clanwar_system\.amxx([[:space:]]|$)' "${PLUGINS_INI}" 2>/dev/null; then
        MAIN_MODE="clanwar"
    else
        MAIN_MODE="public"
    fi
fi

# Source 5: absolute last resort - only if every source above failed
[ -z "$MAIN_MODE" ] && MAIN_MODE="clanwar"

echo "  -> Detected active mode: ${MAIN_MODE}"
mkdir -p /opt/gameland/persistent "${PROJECT_DIR}/instances" 2>/dev/null || true
echo "$MAIN_MODE" > "/opt/gameland/persistent/main_mode.txt" 2>/dev/null || true
echo "$MAIN_MODE" > "${PROJECT_DIR}/instances/main_mode.txt" 2>/dev/null || true

# Ensure all 8 GameLand helper plugins are registered and active in plugins.ini
for plugin_entry in \
    "mix_system_voice_chat.amxx:automatic sv_alltalk state for mix rounds" \
    "gameland_admin_tools.amxx:/map menu and sv_alltalk shortcuts" \
    "player_drop.amxx:Match Server player drop / substitute" \
    "backweapons.amxx:weapons displayed on players backs" \
    "gameland_lan_optimizer.amxx:network latency and fps optimizer" \
    "gameland_sound_optimizer.amxx:spatial sound enhancer" \
    "gameland_fastduck_fix.amxx:fast duck and silent run enforcer" \
    "gameland_only_enforcer.amxx:AllClient security enforcer"; do
    
    pl_file="${plugin_entry%%:*}"
    pl_desc="${plugin_entry#*:}"

    if [ -f "${PLUGINS_DIR}/${pl_file}" ]; then
        if grep -qE "^[[:space:]]*;+[[:space:]]*${pl_file}([[:space:]]|$)" "${PLUGINS_INI}"; then
            sed -i -E "s/^[[:space:]]*;+[[:space:]]*(${pl_file}.*)$/\1/" "${PLUGINS_INI}"
            echo "  -> Uncommented ${pl_file} in plugins.ini"
        elif ! grep -qE "^[[:space:]]*${pl_file}([[:space:]]|$)" "${PLUGINS_INI}"; then
            printf '%s\t; %s\n' "${pl_file}" "${pl_desc}" >> "${PLUGINS_INI}"
            echo "  -> Added ${pl_file} to plugins.ini"
        fi
    fi
done

# Enforce MAIN_MODE cleanly in plugins.ini without overwriting user mode
if [ "$MAIN_MODE" = "mix5v5" ]; then
    echo "  -> 5v5 Mix Mode is active for main: ensuring mix_system.amxx is active!"
    if grep -qE "^[[:space:]]*;+[[:space:]]*mix_system\.amxx([[:space:]]|$)" "${PLUGINS_INI}"; then
        sed -i -E "s/^[[:space:]]*;+[[:space:]]*(mix_system\.amxx.*)$/\1/" "${PLUGINS_INI}"
    elif ! grep -qE "^[[:space:]]*mix_system\.amxx([[:space:]]|$)" "${PLUGINS_INI}"; then
        printf 'mix_system.amxx\t; GAMELAND 5v5 mix and match manager\n' >> "${PLUGINS_INI}"
    fi
    sed -i -E 's/^[[:space:]]*clanwar_system\.amxx([[:space:]].*)?$/;clanwar_system.amxx\t; GAMELAND 10-slot Clan War Mode manager/' "${PLUGINS_INI}"
elif [ "$MAIN_MODE" = "public" ]; then
    echo "  -> Public Mode is active for main: disabling clanwar and mix managers!"
    sed -i -E 's/^[[:space:]]*clanwar_system\.amxx([[:space:]].*)?$/;clanwar_system.amxx\t; GAMELAND 10-slot Clan War Mode manager/' "${PLUGINS_INI}"
    sed -i -E 's/^[[:space:]]*mix_system\.amxx([[:space:]].*)?$/;mix_system.amxx\t; GAMELAND 5v5 mix and match manager/' "${PLUGINS_INI}"
else
    echo "  -> Clan War Mode is active for main: ensuring clanwar_system.amxx is active!"
    if grep -qE "^[[:space:]]*;+[[:space:]]*clanwar_system\.amxx([[:space:]]|$)" "${PLUGINS_INI}"; then
        sed -i -E "s/^[[:space:]]*;+[[:space:]]*(clanwar_system\.amxx.*)$/\1/" "${PLUGINS_INI}"
    elif ! grep -qE "^[[:space:]]*clanwar_system\.amxx([[:space:]]|$)" "${PLUGINS_INI}"; then
        printf 'clanwar_system.amxx\t; GAMELAND 10-slot Clan War Mode manager\n' >> "${PLUGINS_INI}"
    fi
    sed -i -E 's/^[[:space:]]*mix_system\.amxx([[:space:]].*)?$/;mix_system.amxx\t; GAMELAND 5v5 mix and match manager/' "${PLUGINS_INI}"
fi

# ─── 5. Adjust start.sh for 5v5 Match (12 Slots) ───────
COMPILED_COUNT=0
for p in clanwar_system mix_system mix_system_voice_chat gameland_admin_tools gameland_only_enforcer gameland_lan_optimizer gameland_sound_optimizer gameland_fastduck_fix player_drop backweapons; do
    if [ -f "${PLUGINS_DIR}/${p}.amxx" ]; then
        COMPILED_COUNT=$((COMPILED_COUNT + 1))
    fi
done

MIX_SHA="$(grep -o '"sha":[[:space:]]*"[^"]*"' "${CONFIGS_DIR}/.mix_last_sync.json" 2>/dev/null | head -1 | cut -d'"' -f4 || true)"
BUILD_SHA="$(git -C "${PROJECT_DIR}" rev-parse --short=7 HEAD 2>/dev/null || echo unknown)"
BUILD_FULL_SHA="$(git -C "${PROJECT_DIR}" rev-parse HEAD 2>/dev/null || echo unknown)"
DEPLOY_SHA="${MIX_SHA:-${BUILD_SHA}}"

cat > "${CONFIGS_DIR}/.mix_last_build.json" <<EOF
{
  "build_time": "$(date -Iseconds)",
  "commit": {
    "sha": "${DEPLOY_SHA}",
    "server_sha": "${BUILD_SHA}",
    "full_sha": "${BUILD_FULL_SHA}",
    "message": "install_mix.sh local build"
  },
  "success": true,
  "compiled_count": ${COMPILED_COUNT},
  "targets": {
    "clanwar_system.sma": "clanwar_system.amxx",
    "mix_system.sma": "mix_system.amxx",
    "mix_system_voice_chat.sma": "mix_system_voice_chat.amxx",
    "gameland_admin_tools.sma": "gameland_admin_tools.amxx",
    "gameland_only_enforcer.sma": "gameland_only_enforcer.amxx",
    "gameland_lan_optimizer.sma": "gameland_lan_optimizer.amxx",
    "gameland_sound_optimizer.sma": "gameland_sound_optimizer.amxx",
    "gameland_fastduck_fix.sma": "gameland_fastduck_fix.amxx",
    "player_drop.sma": "player_drop.amxx",
    "backweapons.sma": "backweapons.amxx"
  }
}
EOF
echo "  -> Wrote deploy record: ${CONFIGS_DIR}/.mix_last_build.json (${COMPILED_COUNT} managed plugins)"

echo "[5/5] Optimizing server config for active game mode..."
existing_slots=""
if [ -f "${PROJECT_DIR}/cstrike/server.cfg" ]; then
    existing_slots=$(grep -E '^[[:space:]]*sv_visiblemaxplayers[[:space:]]+[0-9]+' "${PROJECT_DIR}/cstrike/server.cfg" | head -n1 | awk '{print $2}')
fi

if [ -n "$existing_slots" ] && [ "$existing_slots" -gt 0 ]; then
    main_slots="$existing_slots"
    echo "  -> Preserving existing user-configured slots: ${main_slots}"
elif [ "$MAIN_MODE" = "mix5v5" ]; then
    main_slots="18"
    echo "  -> 5v5 Match active: set MAX_PLAYERS and sv_visiblemaxplayers to 18"
elif [ "$MAIN_MODE" = "public" ]; then
    main_slots="24"
    echo "  -> Public active: set MAX_PLAYERS and sv_visiblemaxplayers to 24"
else
    main_slots="10"
    echo "  -> Clan War active: set MAX_PLAYERS and sv_visiblemaxplayers to 10"
fi

sed -i -E "s/MAX_PLAYERS=\".*\"/MAX_PLAYERS=\"${main_slots}\"/" "${PROJECT_DIR}/start.sh" 2>/dev/null || true
[ -f "${PROJECT_DIR}/.env" ] && sed -i -E "s/MAX_PLAYERS=\".*\"/MAX_PLAYERS=\"${main_slots}\"/" "${PROJECT_DIR}/.env" 2>/dev/null || true
if [ -f "${PROJECT_DIR}/cstrike/server.cfg" ]; then
    if ! grep -q '^[[:space:]]*sv_visiblemaxplayers' "${PROJECT_DIR}/cstrike/server.cfg"; then
        echo "sv_visiblemaxplayers ${main_slots}" >> "${PROJECT_DIR}/cstrike/server.cfg"
    fi
fi

# Helper function to sync compiled plugins, dictionaries, and configs to a specific instance
sync_instance_files() {
    local s_id="$1"
    local target_dir="/opt/gameland/instances/${s_id}"
    if [ ! -d "$target_dir" ] && [ -d "${PROJECT_DIR}/instances/${s_id}" ]; then
        target_dir="${PROJECT_DIR}/instances/${s_id}"
    fi

    if [ ! -d "${target_dir}/cstrike/addons/amxmodx/plugins" ]; then
        echo "  [WARN] Instance '${s_id}' directory not found: ${target_dir}"
        return 1
    fi

    # Sync all compiled plugins
    cp -f "${PLUGINS_DIR}"/*.amxx "${target_dir}/cstrike/addons/amxmodx/plugins/" 2>/dev/null || true
    chmod 666 "${target_dir}/cstrike/addons/amxmodx/plugins/"*.amxx 2>/dev/null || true

    # Sync language dictionary files
    mkdir -p "${target_dir}/cstrike/addons/amxmodx/data/lang" 2>/dev/null || true
    cp -rf "${PROJECT_DIR}/cstrike/addons/amxmodx/data/lang"/* "${target_dir}/cstrike/addons/amxmodx/data/lang/" 2>/dev/null || true

    # Sync match and rules configs (stop.cfg, start.cfg, clanwar.cfg, etc.)
    for cfg_name in stop.cfg start.cfg clanwar.cfg warmup.cfg knife.cfg live.cfg game_init.cfg rehlds.cfg; do
        if [ -f "${PROJECT_DIR}/cstrike/${cfg_name}" ]; then
            cp -f "${PROJECT_DIR}/cstrike/${cfg_name}" "${target_dir}/cstrike/" 2>/dev/null || true
        fi
    done
    if [ ! -f "${target_dir}/cstrike/server.cfg" ] && [ -f "${PROJECT_DIR}/cstrike/server.cfg" ]; then
        cp -f "${PROJECT_DIR}/cstrike/server.cfg" "${target_dir}/cstrike/" 2>/dev/null || true
    fi

    # Hitbox fixer config
    if [ -d "${target_dir}/cstrike/addons/hitbox_fixer" ]; then
        mkdir -p "${target_dir}/cstrike/addons/hitbox_fixer/dlls" 2>/dev/null || true
        if [ -f "${PROJECT_DIR}/cstrike/addons/hitbox_fixer/hbf.cfg" ]; then
            cp -f "${PROJECT_DIR}/cstrike/addons/hitbox_fixer/hbf.cfg" "${target_dir}/cstrike/addons/hitbox_fixer/dlls/hbf.cfg" 2>/dev/null || true
            cp -f "${PROJECT_DIR}/cstrike/addons/hitbox_fixer/hbf.cfg" "${target_dir}/cstrike/addons/hitbox_fixer/hbf.cfg" 2>/dev/null || true
        fi
    fi

    mkdir -p "${target_dir}/cstrike/addons/amxmodx/configs" 2>/dev/null || true
    cp -f "${CONFIGS_DIR}"/ClanWarSettings.ini "${target_dir}/cstrike/addons/amxmodx/configs/" 2>/dev/null || true
    cp -f "${CONFIGS_DIR}"/MixSettings.ini "${target_dir}/cstrike/addons/amxmodx/configs/" 2>/dev/null || true
    for cfg_f in "${CONFIGS_DIR}"/*.cfg; do
        if [ -f "$cfg_f" ]; then
            fname="$(basename "$cfg_f")"
            if [ "$fname" = "amxx.cfg" ] && [ -f "${target_dir}/cstrike/addons/amxmodx/configs/amxx.cfg" ]; then
                continue
            fi
            cp -f "$cfg_f" "${target_dir}/cstrike/addons/amxmodx/configs/" 2>/dev/null || true
        fi
    done

    # Resolve instance specific hostname from servers.json
    inst_hostname=$(python3 -c '
import json, sys
iid = sys.argv[1]
for p in ["'"${PROJECT_DIR}"'/instances/servers.json", "/opt/gameland/persistent/servers.json"]:
    try:
        with open(p) as f:
            for s in json.load(f).get("servers", []):
                if s.get("id") == iid:
                    print(s.get("hostname") or s.get("name") or "")
                    sys.exit(0)
    except Exception: pass
sys.exit(1)
' "$s_id" 2>/dev/null || true)
    if [ -n "$inst_hostname" ]; then
        if [ -f "${target_dir}/cstrike/server.cfg" ]; then
            sed -i -E "s/^[[:space:]]*hostname[[:space:]]+.*/hostname \"${inst_hostname}\"/" "${target_dir}/cstrike/server.cfg" 2>/dev/null || true
            if ! grep -q '^[[:space:]]*hostname' "${target_dir}/cstrike/server.cfg"; then
                echo "hostname \"${inst_hostname}\"" >> "${target_dir}/cstrike/server.cfg"
            fi
            sed -i -E "s/^[[:space:]]*cw_base_hostname[[:space:]]+.*/cw_base_hostname \"${inst_hostname}\"/" "${target_dir}/cstrike/server.cfg" 2>/dev/null || true
            if ! grep -q '^[[:space:]]*cw_base_hostname' "${target_dir}/cstrike/server.cfg"; then
                echo "cw_base_hostname \"${inst_hostname}\"" >> "${target_dir}/cstrike/server.cfg"
            fi
            sed -i -E "s/^[[:space:]]*mix_base_hostname[[:space:]]+.*/mix_base_hostname \"${inst_hostname}\"/" "${target_dir}/cstrike/server.cfg" 2>/dev/null || true
            if ! grep -q '^[[:space:]]*mix_base_hostname' "${target_dir}/cstrike/server.cfg"; then
                echo "mix_base_hostname \"${inst_hostname}\"" >> "${target_dir}/cstrike/server.cfg"
            fi
        fi
        if [ -f "${target_dir}/cstrike/gameland.cfg" ]; then
            sed -i -E '/^[[:space:]]*(hostname|cw_base_hostname|mix_base_hostname)[[:space:]]+/d' "${target_dir}/cstrike/gameland.cfg" 2>/dev/null || true
        fi
        if [ -f "${PROJECT_DIR}/instances/${s_id}.env" ]; then
            sed -i -E "s/^[[:space:]]*HOSTNAME=.*/HOSTNAME=\"${inst_hostname}\"/" "${PROJECT_DIR}/instances/${s_id}.env" 2>/dev/null || true
            sed -i -E "s/^[[:space:]]*SERVER_NAME=.*/SERVER_NAME=\"${inst_hostname}\"/" "${PROJECT_DIR}/instances/${s_id}.env" 2>/dev/null || true
            if ! grep -q '^HOSTNAME=' "${PROJECT_DIR}/instances/${s_id}.env"; then
                echo "HOSTNAME=\"${inst_hostname}\"" >> "${PROJECT_DIR}/instances/${s_id}.env"
            fi
        fi
        amxx_cfg="${target_dir}/cstrike/addons/amxmodx/configs/amxx.cfg"
        if [ -f "$amxx_cfg" ]; then
            sed -i -E '/^[[:space:]]*(cw_base_hostname|mix_base_hostname)[[:space:]]+/d' "$amxx_cfg" 2>/dev/null || true
            echo "cw_base_hostname \"${inst_hostname}\"" >> "$amxx_cfg"
            echo "mix_base_hostname \"${inst_hostname}\"" >> "$amxx_cfg"
        fi
    fi

    # Ensure semiclip disabled (solid competitive collision)
    if [ -f "${target_dir}/cstrike/server.cfg" ]; then
        sed -i -E 's/^[[:space:]]*mp_semiclip[[:space:]]+.*/mp_semiclip 0/' "${target_dir}/cstrike/server.cfg" 2>/dev/null || true
        sed -i -E 's/^[[:space:]]*mp_semiclip_actions[[:space:]]+.*/mp_semiclip_actions 0/' "${target_dir}/cstrike/server.cfg" 2>/dev/null || true
    fi

    # Enforce preserved mode and slots in instance plugins.ini and env
    inst_pini="${target_dir}/cstrike/addons/amxmodx/configs/plugins.ini"
    inst_mode_info=$(python3 -c '
import json, sys
iid = sys.argv[1]
for p in ["/opt/gameland/persistent/modes.json", "'"${PROJECT_DIR}"'/instances/modes.json"]:
    try:
        with open(p) as f:
            d = json.load(f)
            if iid in d:
                print(f"{d[iid].get(\"mode\",\"clanwar\")}|{d[iid].get(\"slots\",10)}")
                sys.exit(0)
    except Exception: pass
for p in ["'"${PROJECT_DIR}"'/instances/servers.json", "/opt/gameland/persistent/servers.json"]:
    try:
        with open(p) as f:
            d = json.load(f)
            for s in d.get("servers", []):
                if s.get("id") == iid:
                    print(f"{s.get(\"mode\",\"clanwar\")}|{s.get(\"slots\",10)}")
                    sys.exit(0)
    except Exception: pass
sys.exit(1)
' "$s_id" 2>/dev/null || true)

    inst_mode="clanwar"
    inst_slots=10
    if [ -n "$inst_mode_info" ]; then
        inst_mode="${inst_mode_info%%|*}"
        inst_slots="${inst_mode_info##*|}"
    elif [ -f "$inst_pini" ]; then
        if grep -qE '^[[:space:]]*mix_system\.amxx([[:space:]]|$)' "$inst_pini"; then
            inst_mode="mix5v5"
            inst_slots=18
        elif grep -qE '^[[:space:]]*clanwar_system\.amxx([[:space:]]|$)' "$inst_pini"; then
            inst_mode="clanwar"
            inst_slots=10
        else
            inst_mode="public"
            inst_slots=24
        fi
    fi

    existing_inst_slots=""
    if [ -f "${target_dir}/cstrike/server.cfg" ]; then
        existing_inst_slots=$(grep -E '^[[:space:]]*sv_visiblemaxplayers[[:space:]]+[0-9]+' "${target_dir}/cstrike/server.cfg" | head -n1 | awk '{print $2}')
    fi

    if [ -f "$inst_pini" ]; then
        if [ "$inst_mode" = "mix5v5" ]; then
            sed -i -E 's/^[[:space:]]*;?[[:space:]]*mix_system\.amxx([[:space:]].*)?$/mix_system.amxx/' "$inst_pini" 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$inst_pini" 2>/dev/null || true
            inst_slots=${existing_inst_slots:-18}
        elif [ "$inst_mode" = "public" ]; then
            sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$inst_pini" 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$inst_pini" 2>/dev/null || true
            inst_slots=${existing_inst_slots:-24}
        else
            sed -i -E 's/^[[:space:]]*;?[[:space:]]*clanwar_system\.amxx([[:space:]].*)?$/clanwar_system.amxx/' "$inst_pini" 2>/dev/null || true
            sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$inst_pini" 2>/dev/null || true
            inst_slots=${existing_inst_slots:-10}
        fi
        chmod 666 "$inst_pini" 2>/dev/null || true
    fi

    for env_f in "${PROJECT_DIR}/instances/${s_id}.env" "${target_dir}/.env"; do
        if [ -f "$env_f" ]; then
            sed -i -E "s/MAX_PLAYERS=\".*\"/MAX_PLAYERS=\"${inst_slots}\"/" "$env_f" 2>/dev/null || true
        fi
    done
    if [ -f "${target_dir}/start.sh" ]; then
        sed -i -E "s/MAX_PLAYERS=\".*\"/MAX_PLAYERS=\"${inst_slots}\"/" "${target_dir}/start.sh" 2>/dev/null || true
    fi
    if [ -f "${target_dir}/cstrike/server.cfg" ]; then
        if ! grep -q '^[[:space:]]*sv_visiblemaxplayers' "${target_dir}/cstrike/server.cfg"; then
            echo "sv_visiblemaxplayers ${inst_slots}" >> "${target_dir}/cstrike/server.cfg"
        fi
    fi

    chmod +x "${target_dir}/hlds_linux" "${target_dir}/hlds_run" "${target_dir}"/*.sh 2>/dev/null || true
    chown -R www-data:www-data "${target_dir}/cstrike/addons/amxmodx" 2>/dev/null || true
    return 0
}

# ─── CASE A: Target Single Isolated Instance ───────────────────
if [ -n "$TARGET_INSTANCE" ] && [ "$TARGET_INSTANCE" != "main" ]; then
    echo "[*] Exclusively compiling and synchronizing instance: '$TARGET_INSTANCE'..."
    if sync_instance_files "$TARGET_INSTANCE"; then
        echo "  -> Synced plugins and configs to instance '$TARGET_INSTANCE'."
        if [ "$DO_RESTART" = true ]; then
            svc="gameland@${TARGET_INSTANCE}.service"
            if systemctl is-active --quiet "$svc" 2>/dev/null || systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                echo "  -> Restarting instance '$TARGET_INSTANCE' ($svc)..."
                systemctl restart "$svc" 2>/dev/null || true
                sleep 2.0
                if systemctl is-active --quiet "$svc" 2>/dev/null && tmux has-session -t "gameland_${TARGET_INSTANCE}" 2>/dev/null; then
                    echo "     [✔ RUNNING] Instance '$TARGET_INSTANCE' is active and online!"
                else
                    echo "     [!] Retrying startup for '$TARGET_INSTANCE'..."
                    systemctl restart "$svc" 2>/dev/null || true
                    sleep 2.0
                fi
            fi
        fi
    fi
    echo "[SUCCESS] Instance '$TARGET_INSTANCE' updated cleanly with zero impact on other servers!"
    exit 0
fi

# ─── CASE B: Synchronize All Instances (Staggered Sequence) ───
if [ "$DO_SYNC_ALL" = true ]; then
    echo "[*] Synchronizing updated plugins to all registered server instances (Staggered)..."

    # 0. Snapshot active status of ALL instances BEFORE restarting main
    declare -A WAS_ACTIVE_MAP
    for inst_dir in /opt/gameland/instances/* "${PROJECT_DIR}/instances"/*; do
        if [ -d "$inst_dir" ]; then
            s_id="$(basename "$inst_dir")"
            if [ "$s_id" != "*" ] && [ "$s_id" != "main" ] && [ "$s_id" != "instances_env" ] && [ "$s_id" != "instances_plugins" ]; then
                svc="gameland@${s_id}.service"
                if systemctl is-active --quiet "$svc" 2>/dev/null || tmux has-session -t "gameland_${s_id}" 2>/dev/null; then
                    WAS_ACTIVE_MAP["$s_id"]=1
                fi
            fi
        fi
    done

    # Restart main FIRST if active, so instances follow sequentially
    if [ "$DO_RESTART" = true ] && (systemctl is-active --quiet gameland.service 2>/dev/null || tmux has-session -t gameland_server 2>/dev/null); then
        echo "  -> Restarting main server (gameland.service)..."
        systemctl restart gameland.service 2>/dev/null || true
        echo "     [*] Waiting 2.5s for main server startup stabilization..."
        sleep 2.5
    fi

    # 1. Collect all known instance IDs from servers.json and /opt/gameland/instances
    declare -A SEEN_INSTANCES
    INST_LIST=()

    # Read from servers.json
    for reg_json in "${PROJECT_DIR}/instances/servers.json" "/opt/gameland/persistent/servers.json"; do
        if [ -f "$reg_json" ]; then
            while read -r s_id; do
                if [ -n "$s_id" ] && [ "$s_id" != "main" ] && [ -z "${SEEN_INSTANCES[$s_id]:-}" ]; then
                    SEEN_INSTANCES["$s_id"]=1
                    INST_LIST+=("$s_id")
                fi
            done < <(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print("\n".join([str(s.get("id","")) for s in d.get("servers",[]) if s.get("id")]))' "$reg_json" 2>/dev/null || true)
        fi
    done

    # Also discover from filesystem
    for inst_dir in /opt/gameland/instances/*; do
        if [ -d "$inst_dir" ]; then
            s_id="$(basename "$inst_dir")"
            if [ -n "$s_id" ] && [ "$s_id" != "*" ] && [ "$s_id" != "main" ] && [ -z "${SEEN_INSTANCES[$s_id]:-}" ]; then
                SEEN_INSTANCES["$s_id"]=1
                INST_LIST+=("$s_id")
            fi
        fi
    done

    # 2. Sync plugins and restart instances sequentially
    synced_count=0
    for s_id in "${INST_LIST[@]}"; do
        if sync_instance_files "$s_id"; then
            synced_count=$((synced_count + 1))
            svc="gameland@${s_id}.service"
            was_active=false
            if [ "${WAS_ACTIVE_MAP[$s_id]:-0}" = "1" ] || systemctl is-active --quiet "$svc" 2>/dev/null || tmux has-session -t "gameland_${s_id}" 2>/dev/null; then
                was_active=true
            fi

            if [ "$was_active" = true ] && [ "$DO_RESTART" = true ]; then
                echo "  -> Restarting instance '$s_id' ($svc)..."
                systemctl restart "$svc" 2>/dev/null || true
                echo "     [*] Waiting 2.5s before next instance..."
                sleep 2.5
                if systemctl is-active --quiet "$svc" 2>/dev/null && tmux has-session -t "gameland_${s_id}" 2>/dev/null; then
                    echo "     [✔ RUNNING] Instance '$s_id' is active and online!"
                else
                    echo "     [!] Retrying startup for '$s_id'..."
                    systemctl restart "$svc" 2>/dev/null || true
                    sleep 2.0
                fi
            else
                echo "  -> Synced plugins to stopped instance '$s_id'."
            fi
        fi
    done
    echo "[*] Total instances synchronized: $synced_count"
    echo "[SUCCESS] Multi-server synchronized staggered successfully!"
    exit 0
else
    echo "[*] Server instances remain isolated and untouched (full independence)."
fi

echo ""
echo "================================================="
echo "   [SUCCESS] 5v5 Match Server Ready!            "
echo "================================================="
echo " Commands for Admins in-game:"
echo "   say /a         -> Master Admin Panel (Add/Remove Admins, Teams, Mix, Maps)"
echo "   say /rev       -> Revive ALL dead players immediately (CT & TR)"
echo "   say /spec      -> Move all players to Spectator -> Hostname: [Pick]"
echo "   say /warm      -> Start WarmUp -> Hostname: [WarmUp]"
echo "   say /knife     -> Start Knife Round -> Hostname: [Knife]"
echo "   say /mix       -> Start 5v5 Match Vote (Knife vs Direct Live)"
echo "   say /live (/lv)-> Direct Live 3-Restart Countdown -> Hostname: CT [X] TR [Y]"
echo "   say /stop      -> Stop Match and return to WarmUp"
echo "   say /score     -> View current match score and halftime stats"
echo "   say /pause     -> Pause / Unpause match"
echo "   say /st        -> Swap teams"
echo "   say /kspec     -> Kick spectators"
echo "================================================="
# Restore persistent admins & servers if needed
if [ -f "/opt/gameland/persistent/users.ini" ]; then
    cp -f /opt/gameland/persistent/users.ini "${CONFIGS_DIR}/users.ini" 2>/dev/null || true
fi
if [ -f "/opt/gameland/persistent/servers.json" ]; then
    cp -f /opt/gameland/persistent/servers.json "${PROJECT_DIR}/instances/servers.json" 2>/dev/null || true
    python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: d = json.load(f)
    if isinstance(d.get("servers"), list):
        d["servers"] = [s for s in d["servers"] if s.get("id") and s.get("id") != "main"]
        with open(sys.argv[1], "w") as f: json.dump(d, f, indent=2)
except Exception: pass
' "${PROJECT_DIR}/instances/servers.json" 2>/dev/null || true
fi

# Ensure gameland.service has no unresolved variables before restarting
if [ -f "/etc/systemd/system/gameland.service" ] && grep -q '\${PROJECT_ROOT}' /etc/systemd/system/gameland.service; then
    sed -i "s|\${PROJECT_ROOT}|${PROJECT_DIR}|g" /etc/systemd/system/gameland.service 2>/dev/null || true
fi
systemctl daemon-reload 2>/dev/null || true

if [ "$DO_RESTART" = true ]; then
    echo " Restarting gameland.service to load plugins..."
    systemctl restart gameland.service 2>/dev/null || true
    sleep 2
    systemctl status gameland.service --no-pager 2>/dev/null || true
fi

