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

# Install or refresh dynamic forwarder wrapper to /usr/local/sbin/gameland-panel-sudo
cat > /usr/local/sbin/gameland-panel-sudo << 'EOF'
#!/bin/bash
exec /bin/bash /opt/gameland/server/panel/gameland-panel-sudo.sh "$@"
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

# Ensure all 9 GameLand & Mix plugins are registered in plugins.ini
for plugin_entry in \
    "mix_system.amxx:GAMELAND 5v5 mix and match manager" \
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

# Ensure clanwar_system is registered in plugins.ini (commented if mix is active)
if [ -f "${PLUGINS_DIR}/clanwar_system.amxx" ]; then
    if ! grep -qE "clanwar_system\.amxx" "${PLUGINS_INI}"; then
        printf ';clanwar_system.amxx\t; GAMELAND 10-slot Clan War Mode manager\n' >> "${PLUGINS_INI}"
        echo "  -> Added ;clanwar_system.amxx (disabled by default) to plugins.ini"
    fi
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
if grep -Eq '^[[:space:]]*clanwar_system\.amxx' "${CONFIGS_DIR}/plugins.ini" 2>/dev/null; then
    sed -i 's/MAX_PLAYERS=".*"/MAX_PLAYERS="10"/' "${PROJECT_DIR}/start.sh"
    echo "  -> Clan War active: set MAX_PLAYERS to 10"
elif grep -Eq '^[[:space:]]*mix_system\.amxx' "${CONFIGS_DIR}/plugins.ini" 2>/dev/null; then
    sed -i 's/MAX_PLAYERS=".*"/MAX_PLAYERS="18"/' "${PROJECT_DIR}/start.sh"
    echo "  -> 5v5 Match active: set MAX_PLAYERS to 18"
fi

# Instances synchronization & automatic multi-server restart
if [ "${1:-}" == "--sync-all" ]; then
    echo "[*] Synchronizing updated plugins to all registered server instances..."
    
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
            done < <(python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print("
".join([str(s.get("id","")) for s in d.get("servers",[]) if s.get("id")]))' "$reg_json" 2>/dev/null || true)
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

    # 2. Sync plugins and restart instances with clean status checking
    synced_count=0
    for s_id in "${INST_LIST[@]}"; do
        # Determine instance directory
        target_dir="/opt/gameland/instances/${s_id}"
        if [ ! -d "$target_dir" ] && [ -d "${PROJECT_DIR}/instances/${s_id}" ]; then
            target_dir="${PROJECT_DIR}/instances/${s_id}"
        fi

        if [ -d "${target_dir}/cstrike/addons/amxmodx/plugins" ]; then
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
            cp -f "${CONFIGS_DIR}"/*.cfg "${target_dir}/cstrike/addons/amxmodx/configs/" 2>/dev/null || true

            chmod +x "${target_dir}/hlds_linux" "${target_dir}/hlds_run" "${target_dir}"/*.sh 2>/dev/null || true
            chown -R www-data:www-data "${target_dir}/cstrike/addons/amxmodx" 2>/dev/null || true
            synced_count=$((synced_count + 1))

            svc="gameland@${s_id}.service"
            # Check if active OR enabled in systemd
            was_active=false
            if systemctl is-active --quiet "$svc" 2>/dev/null; then
                was_active=true
            elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
                was_active=true
            fi

            if [ "$was_active" = true ]; then
                echo "  -> Restarting instance '$s_id' ($svc)..."
                systemctl restart "$svc" 2>/dev/null || true
                sleep 2.5
                if systemctl is-active --quiet "$svc" 2>/dev/null && tmux has-session -t "gameland_${s_id}" 2>/dev/null; then
                    echo "     [✔ RUNNING] Instance '$s_id' is active and online!"
                else
                    echo "     [!] Retrying startup for '$s_id'..."
                    systemctl restart "$svc" 2>/dev/null || true
                    sleep 2.0
                    if systemctl is-active --quiet "$svc" 2>/dev/null && tmux has-session -t "gameland_${s_id}" 2>/dev/null; then
                        echo "     [✔ RUNNING] Instance '$s_id' is active!"
                    else
                        echo "     [✖ FAILED] Check logs: /opt/gameland/instances/${s_id}/logs/server_${s_id}.log"
                    fi
                fi
            else
                echo "  -> Synced plugins to stopped instance '$s_id'."
            fi
        fi
    done
    echo "[*] Total instances synchronized: $synced_count"
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

echo " Restarting gameland.service to load plugins..."
systemctl restart gameland.service
sleep 2
systemctl status gameland.service --no-pager

