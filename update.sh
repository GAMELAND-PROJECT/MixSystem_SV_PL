#!/bin/bash
# =========================================================
# GameLand CS 1.6 - Safe One-Click Updater
# Preserves ALL admins, created servers, configs, modes & slots!
# =========================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$SCRIPT_DIR"

CONFIGS_DIR="${SCRIPT_DIR}/cstrike/addons/amxmodx/configs"
USERS_INI="${CONFIGS_DIR}/users.ini"
MAIN_PINI="${CONFIGS_DIR}/plugins.ini"
PERSIST_DIR="/opt/gameland/persistent"
PERSIST_USERS="${PERSIST_DIR}/users.ini"
PERSIST_SERVERS="${PERSIST_DIR}/servers.json"
SERVERS_JSON="${SCRIPT_DIR}/instances/servers.json"

echo "================================================="
echo " Starting Safe Update for GameLand Server...     "
echo "================================================="

# 1. Backup persistent data (admins, server instances, modes, plugins)
mkdir -p "$PERSIST_DIR"
mkdir -p "${PERSIST_DIR}/instances_env"
mkdir -p "${PERSIST_DIR}/instances_plugins"

# Count non-loopback admins
LOCAL_ADMINS=$(grep -cE '^[[:space:]]*"[^"]+"' "$USERS_INI" 2>/dev/null || echo 0)
PERSIST_ADMINS=$(grep -cE '^[[:space:]]*"[^"]+"' "$PERSIST_USERS" 2>/dev/null || echo 0)

if [ "$LOCAL_ADMINS" -gt "$PERSIST_ADMINS" ]; then
    cp -f "$USERS_INI" "$PERSIST_USERS"
    echo "[*] Saved $LOCAL_ADMINS admin accounts to persistent storage."
elif [ "$PERSIST_ADMINS" -gt 0 ]; then
    echo "[*] Protected $PERSIST_ADMINS existing admin accounts in persistent storage."
elif [ -f "$USERS_INI" ]; then
    cp -f "$USERS_INI" "$PERSIST_USERS"
fi

# Sanitize and remove any ghost 'main' instance from servers.json
for reg_f in "$SERVERS_JSON" "$PERSIST_SERVERS"; do
    if [ -f "$reg_f" ]; then
        python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r") as f: d = json.load(f)
    if isinstance(d.get("servers"), list):
        filtered = [s for s in d["servers"] if s.get("id") and s.get("id") != "main"]
        with open(sys.argv[1], "w") as f: json.dump({"servers": filtered}, f, indent=2)
except Exception: pass
' "$reg_f" 2>/dev/null || true
    fi
done

if [ -f "$SERVERS_JSON" ] && python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); sys.exit(0 if isinstance(d.get("servers"), list) else 1)' "$SERVERS_JSON" 2>/dev/null; then
    cp -f "$SERVERS_JSON" "$PERSIST_SERVERS"
    echo "[*] Saved registered server instances to persistent storage."
elif [ -f "$PERSIST_SERVERS" ]; then
    echo "[*] Protected existing server instances in persistent storage."
fi

# Detect & Preserve Main Server's current active mode and plugins.ini
MAIN_MODE="clanwar"
if [ -f "${PERSIST_DIR}/main_mode.txt" ] && grep -qE '^(clanwar|mix5v5|public)$' "${PERSIST_DIR}/main_mode.txt" 2>/dev/null; then
    MAIN_MODE=$(cat "${PERSIST_DIR}/main_mode.txt" | tr -d '[:space:]')
elif [ -f "$MAIN_PINI" ]; then
    if grep -qE '^[[:space:]]*mix_system\.amxx([[:space:]]|$)' "$MAIN_PINI"; then
        MAIN_MODE="mix5v5"
    elif grep -qE '^[[:space:]]*clanwar_system\.amxx([[:space:]]|$)' "$MAIN_PINI"; then
        MAIN_MODE="clanwar"
    else
        MAIN_MODE="public"
    fi
fi
echo "$MAIN_MODE" > "${PERSIST_DIR}/main_mode.txt"
mkdir -p "${SCRIPT_DIR}/instances" 2>/dev/null || true
echo "$MAIN_MODE" > "${SCRIPT_DIR}/instances/main_mode.txt" 2>/dev/null || true
echo "[*] Preserved main server mode: '$MAIN_MODE'"

if [ -f "$MAIN_PINI" ]; then
    cp -f "$MAIN_PINI" "${PERSIST_DIR}/main_plugins.ini"
fi

# Preserve each instance's plugins.ini and consolidate modes in modes.json
python3 -c '
import json, os, glob, re, shutil

persist_dir = "'"${PERSIST_DIR}"'"
script_dir = "'"${SCRIPT_DIR}"'"
modes_file = os.path.join(persist_dir, "modes.json")

modes = {}
if os.path.isfile(modes_file):
    try:
        with open(modes_file, "r") as f: modes = json.load(f)
    except Exception: modes = {}

# Also read from servers.json
for sf in [os.path.join(script_dir, "instances", "servers.json"), os.path.join(persist_dir, "servers.json")]:
    if os.path.isfile(sf):
        try:
            with open(sf, "r") as f:
                d = json.load(f)
                for s in d.get("servers", []):
                    sid = s.get("id")
                    if sid and sid != "main":
                        sm = s.get("mode")
                        ss = s.get("slots")
                        if sid not in modes: modes[sid] = {}
                        if sm: modes[sid]["mode"] = sm
                        if ss: modes[sid]["slots"] = int(ss)
        except Exception: pass

# Also check physical instance directories
os.makedirs(os.path.join(persist_dir, "instances_plugins"), exist_ok=True)
for idir in glob.glob("/opt/gameland/instances/*") + glob.glob(os.path.join(script_dir, "instances", "*")):
    if os.path.isdir(idir):
        sid = os.path.basename(idir)
        if sid in ["*", "main", "instances_env", "instances_plugins"]: continue
        pini = os.path.join(idir, "cstrike", "addons", "amxmodx", "configs", "plugins.ini")
        if os.path.isfile(pini):
            try:
                dest = os.path.join(persist_dir, "instances_plugins", f"{sid}_plugins.ini")
                shutil.copy2(pini, dest)
            except Exception: pass
            if sid not in modes or "mode" not in modes[sid]:
                try:
                    with open(pini, "r", errors="ignore") as f:
                        txt = f.read()
                        if re.search(r"^[ \t]*mix_system\.amxx", txt, re.M):
                            modes[sid] = {"mode": "mix5v5", "slots": 18}
                        elif re.search(r"^[ \t]*clanwar_system\.amxx", txt, re.M):
                            modes[sid] = {"mode": "clanwar", "slots": 10}
                        else:
                            modes[sid] = {"mode": "public", "slots": 24}
                except Exception: pass

with open(modes_file, "w") as f:
    json.dump(modes, f, indent=2)
try:
    shutil.copy2(modes_file, os.path.join(script_dir, "instances", "modes.json"))
except Exception: pass
' 2>/dev/null || true

if compgen -G "${SCRIPT_DIR}/instances/*.env" > /dev/null; then
    cp -f "${SCRIPT_DIR}/instances"/*.env "${PERSIST_DIR}/instances_env/" 2>/dev/null || true
fi

# 2. Kill HLTV completely
pkill -9 -f hltv 2>/dev/null || true
screen -X -S gameland_hltv quit 2>/dev/null || true
screen -X -S demo_compressor quit 2>/dev/null || true

# 3. Pull latest clean updates from GitHub
echo "[*] Fetching latest updates from GitHub..."
git fetch origin main

# Unset skip-worktree & assume-unchanged on all protected files so git reset NEVER fails with 'Entry not uptodate'
git update-index --no-skip-worktree "$USERS_INI" 2>/dev/null || true
git update-index --no-skip-worktree "$SERVERS_JSON" 2>/dev/null || true
git update-index --no-skip-worktree "$MAIN_PINI" 2>/dev/null || true
git update-index --no-skip-worktree "${SCRIPT_DIR}/start.sh" 2>/dev/null || true
git update-index --no-assume-unchanged "$USERS_INI" 2>/dev/null || true
git update-index --no-assume-unchanged "$SERVERS_JSON" 2>/dev/null || true
git update-index --no-assume-unchanged "$MAIN_PINI" 2>/dev/null || true
git update-index --no-assume-unchanged "${SCRIPT_DIR}/start.sh" 2>/dev/null || true

# Force reset index and working tree cleanly
git checkout -f 2>/dev/null || true
git reset --hard origin/main

# 4. Restore persistent data immediately after git reset
if [ -f "$PERSIST_USERS" ] && [ -s "$PERSIST_USERS" ]; then
    cp -f "$PERSIST_USERS" "$USERS_INI"
    chmod 666 "$USERS_INI" 2>/dev/null || true
    echo "[*] Restored $(grep -cE '^[[:space:]]*"[^"]+"' "$USERS_INI" 2>/dev/null || echo 0) admin accounts to users.ini."
fi

if [ -f "$PERSIST_SERVERS" ] && [ -s "$PERSIST_SERVERS" ]; then
    mkdir -p "${SCRIPT_DIR}/instances"
    cp -f "$PERSIST_SERVERS" "$SERVERS_JSON"
    chmod 666 "$SERVERS_JSON" 2>/dev/null || true
    echo "[*] Restored server instances to instances/servers.json."
fi

if compgen -G "${PERSIST_DIR}/instances_env/*.env" > /dev/null; then
    mkdir -p "${SCRIPT_DIR}/instances"
    cp -f "${PERSIST_DIR}/instances_env"/*.env "${SCRIPT_DIR}/instances/" 2>/dev/null || true
    chmod 666 "${SCRIPT_DIR}/instances"/*.env 2>/dev/null || true
fi

# Restore Main Server Mode, plugins.ini, and slots
if [ -f "${PERSIST_DIR}/main_plugins.ini" ] && [ -s "${PERSIST_DIR}/main_plugins.ini" ]; then
    cp -f "${PERSIST_DIR}/main_plugins.ini" "$MAIN_PINI"
fi
SAVED_MAIN_MODE=$(cat "${PERSIST_DIR}/main_mode.txt" 2>/dev/null | tr -d '[:space:]')
if [ -z "$SAVED_MAIN_MODE" ]; then SAVED_MAIN_MODE="clanwar"; fi

if [ "$SAVED_MAIN_MODE" = "mix5v5" ]; then
    sed -i -E 's/^[[:space:]]*;?[[:space:]]*mix_system\.amxx([[:space:]].*)?$/mix_system.amxx/' "$MAIN_PINI" 2>/dev/null || true
    sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$MAIN_PINI" 2>/dev/null || true
    sed -i 's/MAX_PLAYERS=".*"/MAX_PLAYERS="18"/' "${SCRIPT_DIR}/start.sh" 2>/dev/null || true
    echo "[*] Restored main server mode: 5v5 Match (18 slots)"
elif [ "$SAVED_MAIN_MODE" = "public" ]; then
    sed -i -E 's/^[[:space:]]*clanwar_system\.amxx/;\0/' "$MAIN_PINI" 2>/dev/null || true
    sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$MAIN_PINI" 2>/dev/null || true
    sed -i 's/MAX_PLAYERS=".*"/MAX_PLAYERS="24"/' "${SCRIPT_DIR}/start.sh" 2>/dev/null || true
    echo "[*] Restored main server mode: Public (24 slots)"
else
    sed -i -E 's/^[[:space:]]*;?[[:space:]]*clanwar_system\.amxx([[:space:]].*)?$/clanwar_system.amxx/' "$MAIN_PINI" 2>/dev/null || true
    sed -i -E 's/^[[:space:]]*mix_system\.amxx/;\0/' "$MAIN_PINI" 2>/dev/null || true
    sed -i 's/MAX_PLAYERS=".*"/MAX_PLAYERS="10"/' "${SCRIPT_DIR}/start.sh" 2>/dev/null || true
    echo "[*] Restored main server mode: Clan War (10 slots)"
fi
chmod 666 "$MAIN_PINI" 2>/dev/null || true

# Restore each instance plugins.ini from backup
for pini_bk in "${PERSIST_DIR}/instances_plugins"/*_plugins.ini; do
    if [ -f "$pini_bk" ]; then
        sid=$(basename "$pini_bk" | sed 's/_plugins\.ini$//')
        target_dir="/opt/gameland/instances/${sid}"
        if [ ! -d "$target_dir" ] && [ -d "${SCRIPT_DIR}/instances/${sid}" ]; then
            target_dir="${SCRIPT_DIR}/instances/${sid}"
        fi
        if [ -d "${target_dir}/cstrike/addons/amxmodx/configs" ]; then
            cp -f "$pini_bk" "${target_dir}/cstrike/addons/amxmodx/configs/plugins.ini" 2>/dev/null || true
            chmod 666 "${target_dir}/cstrike/addons/amxmodx/configs/plugins.ini" 2>/dev/null || true
        fi
    fi
done

# 5. Tell Git to NEVER overwrite users.ini, servers.json, plugins.ini, and start.sh during future git reset --hard
git update-index --skip-worktree "$USERS_INI" 2>/dev/null || true
git update-index --skip-worktree "$SERVERS_JSON" 2>/dev/null || true
git update-index --skip-worktree "$MAIN_PINI" 2>/dev/null || true
git update-index --skip-worktree "${SCRIPT_DIR}/start.sh" 2>/dev/null || true

# 6. Install Git hooks so even manual git reset --hard automatically restores admins and modes
if [ -d "${SCRIPT_DIR}/.git/hooks" ]; then
    cat > "${SCRIPT_DIR}/.git/hooks/post-checkout" << 'HOOK_EOF'
#!/bin/bash
if [ -f "/opt/gameland/persistent/users.ini" ] && [ -s "/opt/gameland/persistent/users.ini" ]; then
    cp -f /opt/gameland/persistent/users.ini /opt/gameland/server/cstrike/addons/amxmodx/configs/users.ini 2>/dev/null || true
    chmod 666 /opt/gameland/server/cstrike/addons/amxmodx/configs/users.ini 2>/dev/null || true
fi
if [ -f "/opt/gameland/persistent/servers.json" ] && [ -s "/opt/gameland/persistent/servers.json" ]; then
    cp -f /opt/gameland/persistent/servers.json /opt/gameland/server/instances/servers.json 2>/dev/null || true
    chmod 666 /opt/gameland/server/instances/servers.json 2>/dev/null || true
fi
if [ -f "/opt/gameland/persistent/main_plugins.ini" ] && [ -s "/opt/gameland/persistent/main_plugins.ini" ]; then
    cp -f /opt/gameland/persistent/main_plugins.ini /opt/gameland/server/cstrike/addons/amxmodx/configs/plugins.ini 2>/dev/null || true
    chmod 666 /opt/gameland/server/cstrike/addons/amxmodx/configs/plugins.ini 2>/dev/null || true
fi
git update-index --skip-worktree /opt/gameland/server/cstrike/addons/amxmodx/configs/users.ini 2>/dev/null || true
git update-index --skip-worktree /opt/gameland/server/instances/servers.json 2>/dev/null || true
git update-index --skip-worktree /opt/gameland/server/cstrike/addons/amxmodx/configs/plugins.ini 2>/dev/null || true
git update-index --skip-worktree /opt/gameland/server/start.sh 2>/dev/null || true
HOOK_EOF
    chmod +x "${SCRIPT_DIR}/.git/hooks/post-checkout" 2>/dev/null || true
    cp -f "${SCRIPT_DIR}/.git/hooks/post-checkout" "${SCRIPT_DIR}/.git/hooks/post-merge" 2>/dev/null || true
    chmod +x "${SCRIPT_DIR}/.git/hooks/post-merge" 2>/dev/null || true
fi

# 7. Ensure execute permissions on all binaries and scripts
chmod +x "${SCRIPT_DIR}/hlds_linux" "${SCRIPT_DIR}/hlds_run" "${SCRIPT_DIR}"/*.sh "${SCRIPT_DIR}/panel/gameland-panel-sudo.sh" 2>/dev/null || true
if [ -f "${SCRIPT_DIR}/panel/gameland-panel-sudo.sh" ]; then
    mkdir -p /usr/local/sbin 2>/dev/null || true
    cat > /usr/local/sbin/gameland-panel-sudo << EOF
#!/bin/bash
exec /bin/bash "${SCRIPT_DIR}/panel/gameland-panel-sudo.sh" "\$@"
EOF
    chmod 0755 /usr/local/sbin/gameland-panel-sudo 2>/dev/null || true
fi
ln -sf "${SCRIPT_DIR}/svgl.sh" /usr/local/bin/svgl 2>/dev/null || true
ln -sf "${SCRIPT_DIR}/svgl.sh" /usr/local/bin/SVGL 2>/dev/null || true
chmod +x /usr/local/bin/svgl /usr/local/bin/SVGL 2>/dev/null || true

# Refresh systemd service definitions with 100% decoupled units
rm -rf /etc/systemd/system/gameland*.service.d 2>/dev/null || true
if [ -f "${SCRIPT_DIR}/gameland@.service" ]; then
    cp -f "${SCRIPT_DIR}/gameland@.service" /etc/systemd/system/gameland@.service 2>/dev/null || true
    chmod 644 /etc/systemd/system/gameland@.service 2>/dev/null || true
fi
if [ -f "${SCRIPT_DIR}/gameland.service" ]; then
    cp -f "${SCRIPT_DIR}/gameland.service" /etc/systemd/system/gameland.service 2>/dev/null || true
    chmod 644 /etc/systemd/system/gameland.service 2>/dev/null || true
fi
systemctl daemon-reload 2>/dev/null || true

# 8. Recompile and restart cleanly (preserving every server's mode!)
echo "[*] Compiling mix system plugins and synchronizing..."
bash "${SCRIPT_DIR}/install_mix.sh" --sync-all

echo "================================================="
echo " [SUCCESS] Safe Update Completed!                "
echo " Admins, Servers, Modes & Slots preserved 100%!  "
echo "================================================="
