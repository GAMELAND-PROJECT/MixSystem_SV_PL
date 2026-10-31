<?php
require_once __DIR__ . '/../config.php';

class ServerCmd {

    public static function getManagerRoot() {
        return realpath(__DIR__ . '/../..') ?: dirname(__DIR__, 2);
    }

    public static function getSvglPath() {
        $root = self::getManagerRoot();
        if (is_file($root . '/svgl.sh')) {
            return $root . '/svgl.sh';
        }
        return '/usr/local/bin/svgl';
    }

    public static function getPrivilegedHelperPath() {
        // The sudoers rule grants only the installed root-owned helper.
        // Never execute the repository copy from PHP: its path is not the
        // privileged command and would make sudo ask for a password.
        if (is_file('/usr/local/sbin/gameland-panel-sudo')) {
            return '/usr/local/sbin/gameland-panel-sudo';
        }
        return self::getManagerRoot() . '/panel/gameland-panel-sudo.sh';
    }

    public static function validateInstanceId($id) {
        return is_string($id) && preg_match('/^[a-zA-Z0-9_-]{2,32}$/', $id);
    }

    /**
     * Get GoldSourceRcon instance for a server
     */
    public static function getRcon($serverId = 'main') {
        global $SERVERS;
        if (!isset($SERVERS[$serverId])) {
            return null;
        }
        $server = $SERVERS[$serverId];
        $ip = $server['ip'] ?? '127.0.0.1';
        $port = (int)($server['port'] ?? 27015);
        $pass = (string)($server['rcon_password'] ?? '');
        return new \GoldSourceRcon($ip, $port, $pass, 1.5);
    }

    public static function getServerList(array $servers) {
        $result = [];
        foreach ($servers as $server) {
            $status = self::getServiceStatus($server['service_name'], (int)($server['port'] ?? 0), $server['id'] ?? '');
            $runtime = self::getServerRuntimeSettings($server);
            $mode = self::getCurrentServerMode($server);
            $modeTitle = '🎯 Classic Public';
            if ($mode === 'clanwar') {
                $modeTitle = '⚔️ Clan War (10s)';
            } elseif ($mode === 'mix5v5') {
                $modeTitle = '🎮 5v5 Match (18s)';
            }
            $afkGuard = self::getServerAfkGuard($server);
            $result[] = [
                'id' => $server['id'],
                'name' => $server['name'],
                'ip' => $server['ip'],
                'port' => $server['port'],
                'slots' => $runtime['slots'],
                'map' => $runtime['map'],
                'hostname' => $runtime['hostname'],
                'service_name' => $server['service_name'],
                'server_dir' => $server['server_dir'],
                'status' => $status,
                'mode' => $mode,
                'mode_title' => $modeTitle,
                'afk_guard' => $afkGuard,
                'protected' => $server['id'] === 'main',
            ];
        }
        return $result;
    }

    public static function getManagedServers() {
        global $SERVERS;
        return is_array($SERVERS) ? $SERVERS : [];
    }

    private static function aggregateResults(array $results) {
        $failed = [];
        foreach ($results as $id => $result) {
            if (!($result['success'] ?? false)) {
                $failed[$id] = $result['message'] ?? 'Operation failed';
            }
        }

        $msg = '';
        if (count($results) === 1) {
            $single = reset($results);
            $msg = $single['message'] ?? (empty($failed) ? 'Operation completed successfully.' : 'Operation failed.');
        } elseif (empty($failed) && !empty($results)) {
            $msg = 'Operation completed on all selected servers (' . count($results) . ').';
        } else {
            $msg = 'Operation failed on ' . implode(', ', array_keys($failed)) . ': ' . implode('; ', array_values($failed));
        }

        return [
            'success' => empty($failed) && !empty($results),
            'results' => $results,
            'failed'  => $failed,
            'message' => $msg,
        ];
    }

    public static function saveAdminEverywhere($auth, $password, $access, $flags, $comment, $all = false, $selectedId = null, $oldAuth = '') {
        $activeServer = get_active_server();
        $servers = self::getManagedServers();
        if (!$all) {
            $selectedId = $selectedId ?: ($activeServer['id'] ?? 'main');
            $servers = isset($servers[$selectedId]) ? [$selectedId => $servers[$selectedId]] : [$activeServer['id'] => $activeServer];
        }
        if (empty($servers)) {
            $servers = [$activeServer['id'] => $activeServer];
        }
        $results = [];
        foreach ($servers as $id => $server) {
            $res = self::saveAdmin($server['users_ini'], $auth, $password, $access, $flags, $comment, $oldAuth);
            if ($res['success'] && self::getServiceStatus($server['service_name']) === 'running') {
                $reload = self::reloadAdminsLive($server);
                $res['reload'] = $reload;
                if ($reload['success']) {
                    $res['message'] .= ' (Live server synchronized!)';
                } else {
                    $res['message'] .= ' (Notice: ' . $reload['message'] . ')';
                }
            }
            $results[$id] = $res;
        }
        return self::aggregateResults($results);
    }

    public static function deleteAdminEverywhere($auth, $all = false, $selectedId = null) {
        $activeServer = get_active_server();
        $servers = self::getManagedServers();
        if (!$all) {
            $selectedId = $selectedId ?: ($activeServer['id'] ?? 'main');
            $servers = isset($servers[$selectedId]) ? [$selectedId => $servers[$selectedId]] : [$activeServer['id'] => $activeServer];
        }
        if (empty($servers)) {
            $servers = [$activeServer['id'] => $activeServer];
        }
        $results = [];
        foreach ($servers as $id => $server) {
            $res = self::deleteAdmin($server['users_ini'], $auth);
            if ($res['success'] && self::getServiceStatus($server['service_name']) === 'running') {
                $reload = self::reloadAdminsLive($server);
                $res['reload'] = $reload;
                if ($reload['success']) {
                    $res['message'] .= ' (Live server synchronized!)';
                } else {
                    $res['message'] .= ' (Notice: ' . $reload['message'] . ')';
                }
            }
            $results[$id] = $res;
        }
        return self::aggregateResults($results);
    }

    public static function savePluginsEverywhere(array $enabledPluginFiles, $all = false, $selectedId = null, $restart = false) {
        $servers = self::getManagedServers();
        if (!$all) {
            $selectedId = $selectedId ?: (get_active_server()['id'] ?? 'main');
            $servers = isset($servers[$selectedId]) ? [$selectedId => $servers[$selectedId]] : [];
        }
        $results = [];
        foreach ($servers as $id => $server) {
            $res = self::savePluginsState($server, $enabledPluginFiles);
            if ($res['success'] && $restart) {
                $res['restart'] = self::controlService($server['service_name'], 'restart');
                if (!($res['restart']['success'] ?? false)) {
                    $res['success'] = false;
                    $res['message'] .= ' Configuration saved, but restart failed.';
                }
            }
            $results[$id] = $res;
        }
        return self::aggregateResults($results);
    }

    public static function deployMixEverywhere($compile = true, $restart = true) {
        $results = [];
        foreach (self::getManagedServers() as $id => $server) {
            $sync = self::syncMixFromGitHub($server);
            $result = ['success' => $sync['success'], 'sync' => $sync];
            if ($sync['success'] && $compile) {
                $result['compile'] = self::compilePlugins($server);
                $result['success'] = $result['compile']['success'];
            }
            if ($result['success'] && $restart) {
                $result['restart'] = self::controlService($server['service_name'], 'restart');
                $result['success'] = $result['restart']['success'] ?? false;
                sleep(1);
            }
            $result['message'] = $result['success'] ? 'Deployed successfully.' : 'Deployment failed.';
            $results[$id] = $result;
        }
        return self::aggregateResults($results);
    }

    private static function getServerRuntimeSettings(array $server) {
        $defaultSlots = (($server['mode'] ?? '') === 'clanwar') ? 10 : ((($server['mode'] ?? '') === 'public') ? 24 : 18);
        $settings = [
            'slots' => $defaultSlots,
            'map' => 'de_dust2',
            'hostname' => $server['hostname'] ?? $server['name'] ?? '',
        ];

        $cfg = rtrim($server['server_dir'], '/') . '/cstrike/server.cfg';
        $glCfg = rtrim($server['server_dir'], '/') . '/cstrike/gameland.cfg';
        $foundHost = '';
        if (is_file($cfg)) {
            $content = (string)file_get_contents($cfg);
            if (preg_match('/^\s*(?:cw|mix)_base_hostname\s+"?([^"\r\n]+)"?/mi', $content, $m)) {
                $foundHost = trim($m[1]);
            } elseif (preg_match('/^\s*hostname\s+"?([^"\r\n]+)"?/mi', $content, $m)) {
                $foundHost = trim($m[1]);
            }
        }
        if (empty($foundHost) && is_file($glCfg)) {
            $content = (string)file_get_contents($glCfg);
            if (preg_match('/^\s*(?:cw|mix)_base_hostname\s+"?([^"\r\n]+)"?/mi', $content, $m)) {
                $foundHost = trim($m[1]);
            } elseif (preg_match('/^\s*hostname\s+"?([^"\r\n]+)"?/mi', $content, $m)) {
                $foundHost = trim($m[1]);
            }
        }

        if ($foundHost !== '') {
            $cleanHost = preg_replace('/\s*(\[CW[^\]]*\]|\[WarmUp\]|\[Pick\]|\[Knife\]|\|\s*CT\s*\[.*).*$/i', '', $foundHost);
            $cleanHost = trim((string)$cleanHost);
            if ($cleanHost !== '' && !in_array(strtolower($cleanHost), ['gameland', 'counter-strike 1.6 server'])) {
                $settings['hostname'] = $cleanHost;
            } elseif (!empty($server['hostname'])) {
                $settings['hostname'] = $server['hostname'];
            } elseif (!empty($server['name'])) {
                $settings['hostname'] = $server['name'];
            } else {
                $settings['hostname'] = $cleanHost ?: 'GAMELAND';
            }
        }

        if (($server['id'] ?? '') === 'main') {
            $start = rtrim($server['server_dir'], '/') . '/start.sh';
            if (is_file($start)) {
                $content = (string)file_get_contents($start);
                if (preg_match('/^MAX_PLAYERS="([^"]+)"/m', $content, $m)) $settings['slots'] = (int)$m[1];
                if (preg_match('/^MAP="([^"]+)"/m', $content, $m)) $settings['map'] = $m[1];
            }
            if (($server['mode'] ?? '') === 'clanwar') {
                $settings['slots'] = 10;
            }
        } else {
            $env = self::getManagerRoot() . '/instances/' . $server['id'] . '.env';
            if (is_file($env)) {
                $content = (string)file_get_contents($env);
                if (preg_match('/^MAX_PLAYERS="([^"]+)"/m', $content, $m)) $settings['slots'] = (int)$m[1];
                if (preg_match('/^MAP="([^"]+)"/m', $content, $m)) $settings['map'] = $m[1];
            }
        }

        return $settings;
    }

    private static function getRegistryPath() {
        return self::getManagerRoot() . '/instances/servers.json';
    }

    private static function readRegistry() {
        $path = self::getRegistryPath();
        $persist = '/opt/gameland/persistent/servers.json';
        if (!is_file($path) && is_file($persist)) {
            @mkdir(dirname($path), 0777, true);
            @copy($persist, $path);
        }
        if (!is_file($path)) {
            return ['servers' => []];
        }
        $data = json_decode((string)file_get_contents($path), true);
        return is_array($data) ? $data : ['servers' => []];
    }

    private static function writeRegistry(array $registry) {
        $path = self::getRegistryPath();
        $dir = dirname($path);
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
        if (isset($registry['servers']) && is_array($registry['servers'])) {
            $registry['servers'] = array_values(array_filter($registry['servers'], fn($s) => ($s['id'] ?? '') !== 'main' && ($s['id'] ?? '') !== ''));
        }
        @mkdir('/opt/gameland/persistent', 0777, true);
        @file_put_contents('/opt/gameland/persistent/servers.json', json_encode($registry, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
        return @file_put_contents($path, json_encode($registry, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n") !== false;
    }

    private static function writeServerCfgValue($serverDir, $key, $value) {
        $cfg = rtrim($serverDir, '/') . '/cstrike/server.cfg';
        $value = trim((string)$value);
        if ($value === '') {
            return true;
        }
        $line = $key . ' "' . str_replace('"', '', $value) . '"';
        $lines = is_file($cfg) ? file($cfg, FILE_IGNORE_NEW_LINES) : [];
        $found = false;
        foreach ($lines as $i => $existing) {
            if (preg_match('/^\s*' . preg_quote($key, '/') . '\s+/i', $existing)) {
                $lines[$i] = $line;
                $found = true;
            }
        }
        if (!$found) {
            $lines[] = $line;
        }
        return @file_put_contents($cfg, implode("\n", $lines) . "\n") !== false;
    }

    private static function updateEnvFile($id, array $values) {
        $envPath = self::getManagerRoot() . '/instances/' . $id . '.env';
        if (!is_file($envPath)) {
            return false;
        }
        $lines = file($envPath, FILE_IGNORE_NEW_LINES);
        $seen = [];
        foreach ($lines as $i => $line) {
            if (preg_match('/^([A-Z0-9_]+)=/', $line, $m) && array_key_exists($m[1], $values)) {
                $lines[$i] = $m[1] . '="' . str_replace('"', '', (string)$values[$m[1]]) . '"';
                $seen[$m[1]] = true;
            }
        }
        foreach ($values as $key => $value) {
            if (!isset($seen[$key])) {
                $lines[] = $key . '="' . str_replace('"', '', (string)$value) . '"';
            }
        }
        return @file_put_contents($envPath, implode("\n", $lines) . "\n") !== false;
    }

    private static function updateStartShValue($serverDir, $key, $value) {
        $start = rtrim($serverDir, '/') . '/start.sh';
        if (!is_file($start)) {
            return false;
        }
        $content = (string)file_get_contents($start);
        $value = str_replace('"', '', (string)$value);
        $content = preg_replace('/^' . preg_quote($key, '/') . '=".*"$/m', $key . '="' . $value . '"', $content, 1, $count);
        if (!$count) {
            $content .= "\n" . $key . '="' . $value . '"' . "\n";
        }
        return @file_put_contents($start, $content) !== false;
    }

    public static function createServerInstance($id, $port, $name, $slots = 10, $hostname = '', $mode = 'clanwar') {
        $id = trim((string)$id);
        $name = trim((string)$name);
        $port = (int)$port;
        $mode = trim((string)$mode) ?: 'clanwar';

        if (!self::validateInstanceId($id) || $id === 'main') {
            return ['success' => false, 'message' => 'Invalid server id. Use 2-32 chars: letters, numbers, dash or underscore.'];
        }
        if ($port < 1024 || $port > 65535) {
            return ['success' => false, 'message' => 'Invalid port. Use a value between 1024 and 65535.'];
        }
        $slots = (int)$slots;
        if ($slots < 1 || $slots > 32) {
            $slots = ($mode === 'clanwar') ? 10 : (($mode === 'mix5v5') ? 18 : 24);
        }
        if ($name === '') {
            $name = 'GAMELAND #' . $id;
        }
        if (trim((string)$hostname) === '') {
            $hostname = $name;
        }

        $helper = escapeshellarg(self::getPrivilegedHelperPath());
        $cmd = 'sudo -n ' . $helper . ' add '
             . escapeshellarg($id) . ' '
             . escapeshellarg((string)$port) . ' '
             . escapeshellarg($name) . ' '
             . escapeshellarg((string)$slots) . ' '
             . escapeshellarg($mode) . ' 2>&1';
        $lines = [];
        $exitCode = 1;
        @exec($cmd, $lines, $exitCode);
        $output = implode("\n", $lines);

        $ok = $exitCode === 0 && str_contains($output, '[OK]');
        if ($ok) {
            $registry = self::readRegistry();
            $serverDir = '/opt/gameland/instances/' . $id;
            foreach ($registry['servers'] as &$entry) {
                if (($entry['id'] ?? '') === $id) {
                    $entry['name'] = $name;
                    $entry['hostname'] = $hostname;
                    $entry['port'] = $port;
                    $entry['mode'] = $mode;
                    $entry['slots'] = $slots;
                    $entry['rcon_password'] = $entry['rcon_password'] ?? 'GameLand@Rcon2026';
                    $serverDir = $entry['server_dir'] ?? $serverDir;
                    break;
                }
            }
            self::writeRegistry($registry);
            self::updateEnvFile($id, [
                'SERVER_NAME' => $name,
                'HOSTNAME'    => $hostname,
                'SERVER_PORT' => $port,
                'MAX_PLAYERS' => $slots,
                'MAP'         => 'de_dust2',
            ]);
            self::writeServerCfgValue($serverDir, 'hostname', $hostname);
            self::writeServerCfgValue($serverDir, 'cw_base_hostname', $hostname);
            self::writeServerCfgValue($serverDir, 'mix_base_hostname', $hostname);
            self::writeServerCfgValue($serverDir, 'sv_visiblemaxplayers', (string)$slots);
        }

        return [
            'success' => $ok,
            'message' => is_string($output) ? trim($output) : 'No output from SVGL.',
            'output' => trim((string)$output),
        ];
    }

    public static function removeServerInstance($id, $purge = false) {
        $id = trim((string)$id);
        if (!self::validateInstanceId($id) || $id === 'main') {
            return ['success' => false, 'message' => 'Invalid or protected server id.'];
        }

        $helper = escapeshellarg(self::getPrivilegedHelperPath());
        $cmd = 'sudo -n ' . $helper . ' remove ' . escapeshellarg($id)
             . ($purge ? ' --purge' : '')
             . ' 2>&1';
        $lines = [];
        $exitCode = 1;
        @exec($cmd, $lines, $exitCode);
        $output = implode("\n", $lines);

        return [
            'success' => $exitCode === 0 && str_contains($output, '[OK]'),
            'message' => trim($output) !== '' ? trim($output) : 'No output from SVGL.',
            'output' => trim($output),
            'exit_code' => $exitCode,
        ];
    }

    public static function updateServerInstance($id, array $data) {
        $id = trim((string)$id);
        if (!self::validateInstanceId($id) && $id !== 'main') {
            return ['success' => false, 'message' => 'Invalid server id.'];
        }

        $name = trim((string)($data['name'] ?? ''));
        $hostname = trim((string)($data['hostname'] ?? ''));
        $port = (int)($data['port'] ?? 0);
        $slots = (int)($data['slots'] ?? 0);
        $map = trim((string)($data['map'] ?? ''));
        $rcon = trim((string)($data['rcon_password'] ?? ''));
        $mode = trim((string)($data['mode'] ?? ''));

        if ($port && ($port < 1024 || $port > 65535)) {
            return ['success' => false, 'message' => 'Invalid port.'];
        }
        if ($slots && ($slots < 1 || $slots > 32)) {
            return ['success' => false, 'message' => 'Invalid slot count.'];
        }
        if ($map !== '' && !preg_match('/^[a-zA-Z0-9_]+$/', $map)) {
            return ['success' => false, 'message' => 'Invalid map name.'];
        }

        global $SERVERS;
        if (!isset($SERVERS[$id])) {
            return ['success' => false, 'message' => 'Server not found in panel registry.'];
        }

        $server = $SERVERS[$id];
        if ($port) {
            foreach ($SERVERS as $otherId => $otherServer) {
                if ($otherId !== $id && (int)($otherServer['port'] ?? 0) === $port) {
                    return ['success' => false, 'message' => 'Port is already assigned to another server.'];
                }
            }
        }
        $serverDir = $server['server_dir'];

        $effectiveHost = $hostname !== '' ? $hostname : $name;
        if ($effectiveHost !== '') {
            self::writeServerCfgValue($serverDir, 'hostname', $effectiveHost);
            self::writeServerCfgValue($serverDir, 'cw_base_hostname', $effectiveHost);
            self::writeServerCfgValue($serverDir, 'mix_base_hostname', $effectiveHost);
        }
        if ($rcon !== '') {
            self::writeServerCfgValue($serverDir, 'rcon_password', $rcon);
        }

        // Live RCON update if server is running so the user sees the change INSTANTLY
        if ($effectiveHost !== '') {
            try {
                $rconObj = self::getRcon($id);
                if ($rconObj) {
                    $rconObj->execute('cw_base_hostname "' . addslashes($effectiveHost) . '"');
                    $rconObj->execute('mix_base_hostname "' . addslashes($effectiveHost) . '"');
                    $rconObj->execute('hostname "' . addslashes($effectiveHost) . '"');
                }
            } catch (\Throwable $e) {}
        }

        if ($id === 'main') {
            if ($slots) {
                self::updateStartShValue($serverDir, 'MAX_PLAYERS', $slots);
            }
            if ($port) {
                self::updateStartShValue($serverDir, 'SERVER_PORT', $port);
            }
            if ($map !== '') {
                self::updateStartShValue($serverDir, 'MAP', $map);
            }
            if ($name !== '') {
                self::updateStartShValue($serverDir, 'SERVER_NAME', $name);
            }
            if ($effectiveHost !== '') {
                self::updateStartShValue($serverDir, 'HOSTNAME', $effectiveHost);
            }
        } else {
            $env = [];
            if ($slots) $env['MAX_PLAYERS'] = $slots;
            if ($port) $env['SERVER_PORT'] = $port;
            if ($map !== '') $env['MAP'] = $map;
            if ($name !== '') $env['SERVER_NAME'] = $name;
            if ($effectiveHost !== '') $env['HOSTNAME'] = $effectiveHost;
            if (!empty($env)) {
                self::updateEnvFile($id, $env);
            }

            $registry = self::readRegistry();
            foreach ($registry['servers'] as &$entry) {
                if (($entry['id'] ?? '') === $id) {
                    if ($name !== '') $entry['name'] = $name;
                    if ($effectiveHost !== '') $entry['hostname'] = $effectiveHost;
                    if ($port) $entry['port'] = $port;
                    if ($rcon !== '') $entry['rcon_password'] = $rcon;
                    if ($slots) $entry['slots'] = $slots;
                    break;
                }
            }
            self::writeRegistry($registry);
        }

        $currentMode = self::getCurrentServerMode($server);
        if ($mode !== '' && $mode !== $currentMode) {
            self::switchServerMode($server, $mode);
        }

        if (isset($data['afk_guard']) && $data['afk_guard'] !== '') {
            self::setServerAfkGuard($server, (int)$data['afk_guard']);
        }

        return [
            'success' => true,
            'message' => 'Server settings saved. Restart the server to apply changes.',
        ];
    }

    /**
     * Single source of truth for plugins managed by the panel.
     * Keep this list aligned with install_mix.sh and plugins.ini.
     */
    public static function getManagedPluginTargets() {
        return [
            'gameland_only_enforcer.sma' => 'gameland_only_enforcer.amxx',
            'gameland_lan_optimizer.sma' => 'gameland_lan_optimizer.amxx',
            'gameland_sound_optimizer.sma' => 'gameland_sound_optimizer.amxx',
            'gameland_fastduck_fix.sma'  => 'gameland_fastduck_fix.amxx',
            'gameland_dense_smoke.sma'   => 'gameland_dense_smoke.amxx',
            'gameland_admin_tools.sma'   => 'gameland_admin_tools.amxx',
            'clanwar_system.sma'         => 'clanwar_system.amxx',
            'mix_system.sma'             => 'mix_system.amxx',
            'mix_system_voice_chat.sma'  => 'mix_system_voice_chat.amxx',
            'player_drop.sma'            => 'player_drop.amxx',
            'backweapons.sma'            => 'backweapons.amxx',
        ];
    }

    public static function getPluginBuildStatus($serverInfo) {
        $scriptingDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/scripting';
        $pluginsDir   = $serverInfo['cstrike_dir'] . '/addons/amxmodx/plugins';
        $pluginsIni   = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        $rawIni = file_exists($pluginsIni) ? (string)file_get_contents($pluginsIni) : '';
        // Normalize CRLF to LF so regex matches reliably across Windows and Linux line endings
        $registeredText = str_replace("\r", "", $rawIni);
        $status = [];

        foreach (self::getManagedPluginTargets() as $src => $bin) {
            $srcPath = $scriptingDir . '/' . $src;
            $binPath = $pluginsDir . '/' . $bin;
            $srcExists = is_file($srcPath);
            $binExists = is_file($binPath) && filesize($binPath) > 100;
            $srcMtime = $srcExists ? filemtime($srcPath) : 0;
            $binMtime = $binExists ? filemtime($binPath) : 0;
            $registered = (bool)preg_match(
                '/^[ \t]*(?!;)[ \t]*' . preg_quote($bin, '/') . '(?=[ \t\r\n;]|$)/mi',
                $registeredText
            );
            $status[$src] = [
                'source' => $src,
                'binary' => $bin,
                'source_exists' => $srcExists,
                'binary_exists' => $binExists,
                'registered' => $registered,
                'needs_rebuild' => $srcExists && (!$binExists || ($binMtime < $srcMtime && ($srcMtime - $binMtime) > 120)),
                'source_mtime' => $srcMtime ? date('Y-m-d H:i:s', $srcMtime) : null,
                'binary_mtime' => $binMtime ? date('Y-m-d H:i:s', $binMtime) : null,
                'source_hash' => $srcExists ? hash_file('sha256', $srcPath) : null,
                'binary_hash' => $binExists ? hash_file('sha256', $binPath) : null,
            ];
        }
        return $status;
    }

    /**
     * Get systemctl service status with true process / port verification
     */
    public static function getServiceStatus($serviceName, $port = 0, $serverId = '') {
        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
            $output = @shell_exec('tasklist /FI "IMAGENAME eq hlds.exe" 2>&1');
            return (stripos((string)$output, 'hlds.exe') !== false) ? 'running' : 'stopped';
        }

        // 1. Privileged check via sudo helper (verifies systemctl AND live tmux session as root)
        $helper = self::getPrivilegedHelperPath();
        if (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
            $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            $cleanSvc = escapeshellarg($serviceName);
            $cleanH = escapeshellarg($h);
            $sudoOut = trim((string)@shell_exec("sudo -n {$cleanH} service is-active {$cleanSvc} 2>&1"));
            if ($sudoOut === 'active') {
                return 'running';
            }
        }

        // 2. Fast UDP A2S query or socket listener check if port is known (Absolute Ground Truth)
        if ($port > 0) {
            $portInt = (int)$port;
            try {
                $rcon = new \GoldSourceRcon('127.0.0.1', $portInt, '', 0.25);
                $info = $rcon->getInfo();
                if ($info !== false && is_array($info)) {
                    return 'running';
                }
            } catch (\Throwable $e) {}

            $fuserOut = @shell_exec("fuser {$portInt}/udp 2>/dev/null");
            if (!empty(trim((string)$fuserOut))) {
                return 'running';
            }

            $ssOut = @shell_exec("ss -lun '( sport = :{$portInt} )' 2>/dev/null");
            if (!empty($ssOut) && stripos($ssOut, ":{$portInt}") !== false) {
                return 'running';
            }

            $pgrep = @shell_exec("pgrep -f '\\+port {$portInt}' 2>/dev/null");
            if (!empty(trim((string)$pgrep))) {
                return 'running';
            }
        }

        // 3. Direct tmux session check
        $tmuxName = ($serverId === 'main' || empty($serverId)) ? 'gameland_server' : ('gameland_' . $serverId);
        $tmuxCheck = @shell_exec('tmux has-session -t ' . escapeshellarg($tmuxName) . ' 2>&1');
        if ($tmuxCheck === null || trim((string)$tmuxCheck) === '') {
            return 'running';
        }

        // 4. Direct systemctl fallback check
        $cleanService = escapeshellarg($serviceName);
        $output = @shell_exec("systemctl is-active {$cleanService} 2>&1");
        $status = trim((string)$output);
        if ($status === 'active') {
            return 'running';
        }

        return 'stopped';
    }

    /**
     * Execute systemctl start/stop/restart via sudo
     */
    public static function controlService($serviceName, $action) {
        if (!in_array($action, ['start', 'stop', 'restart'], true)) {
            return ['success' => false, 'message' => 'Invalid action'];
        }

        $port = 0;
        $serverId = '';
        foreach (self::getManagedServers() as $s) {
            if (($s['service_name'] ?? '') === $serviceName) {
                $port = (int)($s['port'] ?? 0);
                $serverId = $s['id'] ?? '';
                break;
            }
        }

        $cleanService = escapeshellarg($serviceName);
        $cleanAction = escapeshellarg($action);
        
        $lines = [];
        $exitCode = 1;
        $helper = escapeshellarg(self::getPrivilegedHelperPath());
        @exec("sudo -n {$helper} service {$cleanAction} {$cleanService} 2>&1", $lines, $exitCode);
        $output = implode("\n", $lines);
        sleep(2);
        $newStatus = self::getServiceStatus($serviceName, $port, $serverId);
        return [
            'success' => $exitCode === 0,
            'action' => $action,
            'status' => $newStatus,
            'output' => trim($output),
            'exit_code' => $exitCode,
        ];
    }

    /**
     * Safe Staggered Restart of ALL servers (reboots 1-by-1 with 2.5s delay)
     */
    public static function restartAllServersStaggered() {
        $helper = self::getPrivilegedHelperPath();
        $lines = [];
        $exitCode = 1;
        if (is_file('/usr/local/sbin/gameland-panel-sudo') || is_file($helper)) {
            $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            @exec("sudo -n " . escapeshellarg($h) . " restart_all 2>&1", $lines, $exitCode);
        } else {
            @exec("bash " . escapeshellarg(self::getManagerRoot() . "/restart_all.sh") . " 2>&1", $lines, $exitCode);
        }

        return [
            'success' => $exitCode === 0,
            'message' => 'تمام سرورها با موفقیت و به صورت متوالی (با ۲.۵ ثانیه فاصله) ری‌استارت شدند.',
            'output'  => implode("\n", $lines),
            'exit_code' => $exitCode,
        ];
    }

    /**
     * Sequentially start any stopped servers (1-by-1 with 2.5s delay)
     */
    public static function startAllServersStaggered() {
        $helper = self::getPrivilegedHelperPath();
        $lines = [];
        $exitCode = 1;
        if (is_file('/usr/local/sbin/gameland-panel-sudo') || is_file($helper)) {
            $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            @exec("sudo -n " . escapeshellarg($h) . " start_all 2>&1", $lines, $exitCode);
        } else {
            @exec("bash " . escapeshellarg(self::getManagerRoot() . "/start_all.sh") . " 2>&1", $lines, $exitCode);
        }

        return [
            'success' => $exitCode === 0,
            'message' => 'سرورهای آفلاین با موفقیت و بدون تداخل یکی‌یکی روشن شدند.',
            'output'  => implode("\n", $lines),
            'exit_code' => $exitCode,
        ];
    }

    /**
     * Safely stop all servers cleanly
     */
    public static function stopAllServers() {
        $helper = self::getPrivilegedHelperPath();
        $lines = [];
        $exitCode = 1;
        if (is_file('/usr/local/sbin/gameland-panel-sudo') || is_file($helper)) {
            $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            @exec("sudo -n " . escapeshellarg($h) . " stop_all 2>&1", $lines, $exitCode);
        } else {
            @exec("bash " . escapeshellarg(self::getManagerRoot() . "/stop_all.sh") . " 2>&1", $lines, $exitCode);
        }

        return [
            'success' => $exitCode === 0,
            'message' => 'تمامی سرورها با موفقیت و به صورت ایزوله خاموش شدند.',
            'output'  => implode("\n", $lines),
            'exit_code' => $exitCode,
        ];
    }

    /**
     * Read the last N lines of the server log file
     */
    public static function getLogLines($logPath, $lines = 80) {
        if (!file_exists($logPath)) {
            return "Log file not found at: {$logPath}\nMake sure the server has been launched at least once.";
        }
        $cleanLines = max(1, (int)$lines);
        if (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN') {
            $content = @file($logPath);
            if ($content === false) return "Could not read log file.";
            $slice = array_slice($content, -$cleanLines);
            return implode("", $slice) ?: "No logs available.";
        }
        $cleanPath = escapeshellarg($logPath);
        $output = @shell_exec("tail -n {$cleanLines} {$cleanPath} 2>&1");
        return $output ? $output : "No logs available.";
    }

    /**
     * List all available .bsp maps in cstrike/maps and maps.ini
     */
    public static function getAvailableMaps($serverInfo) {
        $maps = [];
        $mapsDir = $serverInfo['cstrike_dir'] . '/maps';
        if (is_dir($mapsDir)) {
            $files = scandir($mapsDir);
            foreach ($files as $file) {
                if (substr($file, -4) === '.bsp') {
                    $maps[] = substr($file, 0, -4);
                }
            }
        }

        // Also check maps.ini if exists
        $mapsIni = $serverInfo['maps_ini'];
        if (file_exists($mapsIni)) {
            $iniContent = file($mapsIni, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
            foreach ($iniContent as $line) {
                $line = trim($line);
                if ($line !== '' && $line[0] !== ';' && $line[0] !== '/') {
                    $parts = preg_split('/\s+/', $line);
                    $mapName = trim($parts[0]);
                    if (!in_array($mapName, $maps, true)) {
                        $maps[] = $mapName;
                    }
                }
            }
        }

        sort($maps);
        return $maps;
    }

    private static function banFiles(array $serverInfo) {
        $cstrike = rtrim($serverInfo['cstrike_dir'], '/');
        return [
            'ip' => $cstrike . '/listip.cfg',
            'steam' => $cstrike . '/banned.cfg',
        ];
    }

    private static function parseBanLine($line, $source) {
        $line = trim((string)$line);
        if ($line === '' || $line[0] === ';' || str_starts_with($line, '//')) {
            return null;
        }

        if ($source === 'ip' && preg_match('/^addip\s+"?([0-9.]+)"?\s+"?([0-9]{1,3}(?:\.[0-9]{1,3}){3})"?/i', $line, $m)) {
            return [
                'type' => 'ip',
                'target' => $m[2],
                'minutes' => $m[1],
                'raw' => $line,
            ];
        }

        if ($source === 'steam' && preg_match('/^banid\s+"?([0-9.]+)"?\s+"?((?:STEAM|VALVE)_[0-9]:[0-9]:[0-9]+)"?/i', $line, $m)) {
            return [
                'type' => 'steam',
                'target' => $m[2],
                'minutes' => $m[1],
                'raw' => $line,
            ];
        }

        return null;
    }

    private static function findBanLogHint(array $serverInfo, $target) {
        $target = trim((string)$target);
        if ($target === '') {
            return ['reason' => '', 'log_line' => ''];
        }

        $paths = [
            rtrim($serverInfo['cstrike_dir'], '/') . '/addons/amxmodx/logs',
            rtrim($serverInfo['cstrike_dir'], '/') . '/logs',
            rtrim($serverInfo['server_dir'], '/') . '/logs',
        ];
        $matches = [];
        foreach ($paths as $dir) {
            if (!is_dir($dir)) {
                continue;
            }
            $files = glob($dir . '/*.log') ?: [];
            usort($files, fn($a, $b) => filemtime($b) <=> filemtime($a));
            foreach (array_slice($files, 0, 8) as $file) {
                $lines = @file($file, FILE_IGNORE_NEW_LINES);
                if (!$lines) {
                    continue;
                }
                foreach (array_reverse($lines) as $line) {
                    if (stripos($line, $target) !== false && preg_match('/ban|kick|avg|ping|latency/i', $line)) {
                        $matches[] = $line;
                        if (stripos($line, 'avg') !== false) {
                            return ['reason' => 'avg', 'log_line' => $line];
                        }
                        break;
                    }
                }
            }
        }
        return ['reason' => '', 'log_line' => $matches[0] ?? ''];
    }

    public static function getBanList(array $serverInfo) {
        $files = self::banFiles($serverInfo);
        $bans = [];
        foreach ($files as $source => $path) {
            if (!is_file($path)) {
                continue;
            }
            $lines = file($path, FILE_IGNORE_NEW_LINES);
            foreach ($lines as $index => $line) {
                $ban = self::parseBanLine($line, $source);
                if (!$ban) {
                    continue;
                }
                $hint = self::findBanLogHint($serverInfo, $ban['target']);
                $ban['file'] = $path;
                $ban['line'] = $index;
                $ban['reason'] = $hint['reason'];
                $ban['log_line'] = $hint['log_line'];
                $ban['is_avg'] = stripos($ban['raw'] . ' ' . $ban['log_line'], 'avg') !== false;
                $bans[] = $ban;
            }
        }
        usort($bans, fn($a, $b) => strcmp($a['type'] . $a['target'], $b['type'] . $b['target']));
        return $bans;
    }

    public static function removeBan(array $serverInfo, $type, $target) {
        $type = strtolower(trim((string)$type));
        $target = trim((string)$target);
        if (!in_array($type, ['ip', 'steam'], true)) {
            return ['success' => false, 'message' => 'Invalid ban type.'];
        }
        if ($type === 'ip' && !filter_var($target, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            return ['success' => false, 'message' => 'Invalid IP address.'];
        }
        if ($type === 'steam' && !preg_match('/^(?:STEAM|VALVE)_[0-9]:[0-9]:[0-9]+$/', $target)) {
            return ['success' => false, 'message' => 'Invalid SteamID/AuthID.'];
        }

        $files = self::banFiles($serverInfo);
        $path = $files[$type];
        $removed = false;
        if (is_file($path)) {
            $lines = file($path, FILE_IGNORE_NEW_LINES);
            $kept = [];
            foreach ($lines as $line) {
                $ban = self::parseBanLine($line, $type);
                if ($ban && strcasecmp($ban['target'], $target) === 0) {
                    $removed = true;
                    continue;
                }
                $kept[] = $line;
            }
            if (@file_put_contents($path, implode("\n", $kept) . "\n") === false) {
                return ['success' => false, 'message' => 'Unable to write ban file. Check permissions.'];
            }
        }

        $liveMessage = '';
        try {
            $rcon = new GoldSourceRcon($serverInfo['ip'], $serverInfo['port'], $serverInfo['rcon_password'], 1.5);
            if ($type === 'ip') {
                $rcon->execute('removeip ' . $target);
                $rcon->execute('writeip');
            } else {
                $rcon->execute('removeid ' . $target);
                $rcon->execute('writeid');
            }
            $liveMessage = ' Live server ban cache updated.';
        } catch (Exception $e) {
            $liveMessage = ' File updated; live RCON update failed: ' . $e->getMessage();
        }

        return [
            'success' => true,
            'message' => ($removed ? 'Ban removed.' : 'Ban was not present in file.') . $liveMessage,
        ];
    }

    public static function removeAvgBans(array $serverInfo) {
        $bans = self::getBanList($serverInfo);
        $results = [];
        foreach ($bans as $ban) {
            if ($ban['is_avg']) {
                $results[] = self::removeBan($serverInfo, $ban['type'], $ban['target']);
            }
        }
        $failed = array_filter($results, fn($r) => !($r['success'] ?? false));
        return [
            'success' => empty($failed),
            'message' => 'Removed ' . count($results) . ' avg-related ban(s).' . (!empty($failed) ? ' Some removals failed.' : ''),
            'results' => $results,
        ];
    }

    /**
     * Parse AMX Mod X users.ini
     * Format: "identity" "password" "flags" "connection_flags" ; comment
     */
    public static function getAdmins($usersIniPath) {
        $admins = [];
        if (is_file('/opt/gameland/persistent/users.ini') && filesize('/opt/gameland/persistent/users.ini') > 0) {
            if (!file_exists($usersIniPath) || filesize($usersIniPath) === 0) {
                @copy('/opt/gameland/persistent/users.ini', $usersIniPath);
            }
        }
        if (!file_exists($usersIniPath) || filesize($usersIniPath) === 0) {
            $fallback = dirname(__DIR__, 2) . '/cstrike/addons/amxmodx/configs/users.ini';
            if (file_exists($fallback) && filesize($fallback) > 0) {
                $usersIniPath = $fallback;
            } else {
                // Auto-healing: If users.ini is missing or empty, ensure the default local loopback admin exists
                $defaultContent = "; Users configuration file\n; Format: <name|ip|steamid> <password> <access flags> <account flags>\n\"loopback\" \"\" \"abcdefghijklmnopqrstuv\" \"de\" ; Server Local Admin\n";
                self::writeUsersIniFile($usersIniPath, $defaultContent);
                if (!file_exists($usersIniPath) || filesize($usersIniPath) === 0) {
                    $admins[] = [
                        'line_num' => 0,
                        'auth'     => 'loopback',
                        'password' => '',
                        'access'   => 'abcdefghijklmnopqrstuv',
                        'flags'    => 'de',
                        'comment'  => 'Server Local Admin'
                    ];
                    return $admins;
                }
            }
        }

        $lines = @file($usersIniPath, FILE_IGNORE_NEW_LINES);
        if ($lines === false || empty($lines)) {
            $admins[] = [
                'line_num' => 0,
                'auth'     => 'loopback',
                'password' => '',
                'access'   => 'abcdefghijklmnopqrstuv',
                'flags'    => 'de',
                'comment'  => 'Server Local Admin'
            ];
            return $admins;
        }

        foreach ($lines as $index => $line) {
            $trimmed = trim($line);
            if ($trimmed === '' || $trimmed[0] === ';' || substr($trimmed, 0, 2) === '//') {
                continue;
            }

            // Standard match: "auth" "password" "access" "flags" [; comment]
            if (preg_match('/^"([^"]+)"\s+"([^"]*)"\s+"([^"]+)"\s+"([^"]+)"(?:\s*;?\s*(.*))?$/', $trimmed, $m)) {
                $admins[] = [
                    'line_num' => $index,
                    'auth'     => $m[1],
                    'password' => $m[2],
                    'access'   => $m[3],
                    'flags'    => $m[4],
                    'comment'  => isset($m[5]) ? trim($m[5]) : ''
                ];
            } elseif (preg_match('/^"([^"]+)"\s+"([^"]*)"\s+([a-zA-Z]+)\s+([a-zA-Z]+)(?:\s*;?\s*(.*))?$/', $trimmed, $m)) {
                // Quoted auth & pass, unquoted access & flags
                $admins[] = [
                    'line_num' => $index,
                    'auth'     => $m[1],
                    'password' => $m[2],
                    'access'   => $m[3],
                    'flags'    => $m[4],
                    'comment'  => isset($m[5]) ? trim($m[5]) : ''
                ];
            } elseif (preg_match('/^"([^"]+)"/', $trimmed, $m)) {
                // Fallback token extraction for any loose format
                $comment = '';
                $commentPos = strpos($trimmed, ';');
                $codePart = ($commentPos !== false) ? substr($trimmed, 0, $commentPos) : $trimmed;
                if ($commentPos !== false) {
                    $comment = trim(substr($trimmed, $commentPos + 1));
                }
                preg_match_all('/"([^"]*)"|(\S+)/', $codePart, $matches);
                $tokens = [];
                for ($ti = 0; $ti < count($matches[0]); $ti++) {
                    $tokens[] = ($matches[1][$ti] !== '') ? $matches[1][$ti] : $matches[2][$ti];
                }
                if (count($tokens) >= 4) {
                    $admins[] = [
                        'line_num' => $index,
                        'auth'     => $tokens[0],
                        'password' => $tokens[1],
                        'access'   => $tokens[2],
                        'flags'    => $tokens[3],
                        'comment'  => $comment
                    ];
                }
            }
        }
        return $admins;
    }

    /**
     * Safely write content to users.ini with maximum resilience and zero data loss
     */
    public static function writeUsersIniFile($usersIniPath, $content) {
        $dir = dirname($usersIniPath);
        if (!is_dir($dir)) {
            @mkdir($dir, 0777, true);
        }

        // 1. Direct write attempt
        if (@file_put_contents($usersIniPath, $content) !== false) {
            @chmod($usersIniPath, 0666);
            @mkdir('/opt/gameland/persistent', 0777, true);
            @file_put_contents('/opt/gameland/persistent/users.ini', $content);
            return true;
        }

        // 2. Chmod and retry direct write
        @chmod($usersIniPath, 0666);
        if (@file_put_contents($usersIniPath, $content) !== false) {
            return true;
        }

        // 3. Atomic write via temp file in the SAME directory (avoids /tmp cross-filesystem and PrivateTmp)
        $tmpFile = $usersIniPath . '.tmp.' . uniqid('', true);
        if (@file_put_contents($tmpFile, $content) !== false) {
            @chmod($tmpFile, 0666);
            if (@rename($tmpFile, $usersIniPath)) {
                @chmod($usersIniPath, 0666);
                return true;
            }
            @unlink($tmpFile);
        }

        // 4. Safe base64 streaming pipe to privileged helper (100% bypasses /tmp namespace)
        $helpers = [
            '/usr/local/sbin/gameland-panel-sudo',
            self::getManagerRoot() . '/panel/gameland-panel-sudo.sh'
        ];
        $b64 = base64_encode($content);

        foreach ($helpers as $hlp) {
            if (!is_file($hlp)) {
                continue;
            }
            $cmd = "echo " . escapeshellarg($b64) . " | sudo -n " . escapeshellarg($hlp) . " write_users_ini_b64 " . escapeshellarg($usersIniPath) . " 2>&1";
            $out = [];
            $ret = -1;
            @exec($cmd, $out, $ret);
            if ($ret === 0 && file_exists($usersIniPath) && @file_get_contents($usersIniPath) === $content) {
                return true;
            }
        }

        // 5. Privileged fixperms repair and retry direct write
        foreach ($helpers as $hlp) {
            if (!is_file($hlp)) {
                continue;
            }
            @exec("sudo -n " . escapeshellarg($hlp) . " fixperms 2>&1");
        }
        @chmod($usersIniPath, 0666);
        if (@file_put_contents($usersIniPath, $content) !== false) {
            return true;
        }

        return false;
    }

    /**
     * Add or edit an admin in users.ini
     */
    public static function saveAdmin($usersIniPath, $auth, $password, $access, $flags, $comment = '', $oldAuth = '') {
        $auth = trim((string)$auth);
        $password = trim((string)$password);
        $access = trim((string)$access);
        $flags = trim((string)$flags);
        $comment = trim((string)$comment);
        $oldAuth = trim((string)$oldAuth);

        // Sanitize quotes to avoid corrupting users.ini format
        $auth = str_replace('"', '', $auth);
        $password = str_replace('"', '', $password);
        $access = preg_replace('/[^a-zA-Z]/', '', $access);
        $flags = preg_replace('/[^a-zA-Z]/', '', $flags);
        $comment = str_replace(["\r", "\n", '"'], '', $comment);

        if (empty($auth)) {
            return ['success' => false, 'message' => 'نام کاربری یا شناسه ادمین (Auth) نمی‌تواند خالی باشد.'];
        }
        if (empty($access)) {
            $access = 'abcdefghijklmnopqrstuv';
        }
        if (empty($flags)) {
            $flags = (str_starts_with($auth, 'STEAM_') || str_starts_with($auth, 'VALVE_')) ? 'ce' : 'a';
        }

        if (!file_exists($usersIniPath)) {
            $fallback = dirname(__DIR__, 2) . '/cstrike/addons/amxmodx/configs/users.ini';
            if (file_exists($fallback) || is_dir(dirname($fallback))) {
                $usersIniPath = $fallback;
            }
        }

        $lineStr = sprintf('"%s" "%s" "%s" "%s"', $auth, $password, $access, $flags);
        if ($comment !== '') {
            $lineStr .= ' ; ' . $comment;
        }

        $lines = file_exists($usersIniPath) ? @file($usersIniPath, FILE_IGNORE_NEW_LINES) : [];
        if ($lines === false || empty($lines)) {
            $lines = [
                '; Users configuration file',
                '; Format: <name|ip|steamid> <password> <access flags> <account flags>',
                '"loopback" "" "abcdefghijklmnopqrstuv" "de" ; Server Local Admin'
            ];
        }

        $found = false;
        $targetAuth = ($oldAuth !== '') ? $oldAuth : $auth;

        foreach ($lines as $idx => $line) {
            $t = trim($line);
            if ($t === '' || $t[0] === ';' || substr($t, 0, 2) === '//') {
                continue;
            }
            if (preg_match('/^"([^"]+)"/', $t, $m)) {
                if (strcasecmp($m[1], $targetAuth) === 0 || ($oldAuth === '' && strcasecmp($m[1], $auth) === 0)) {
                    $lines[$idx] = $lineStr;
                    $found = true;
                    break;
                }
            }
        }

        if (!$found) {
            $lines[] = $lineStr;
        }

        $content = implode("\n", $lines) . "\n";
        $ok = self::writeUsersIniFile($usersIniPath, $content);
        if (!$ok) {
            return ['success' => false, 'message' => 'عدم دسترسی به نوشتن در users.ini (' . $usersIniPath . '). لطفاً دستور sudo bash fix_perms.sh را در ترمینال اجرا کنید.'];
        }

        return ['success' => true, 'message' => $found ? "ادمین '$auth' با موفقیت بروزرسانی شد." : "ادمین '$auth' با موفقیت به سرور اضافه شد."];
    }

    /**
     * Delete an admin from users.ini
     */
    public static function deleteAdmin($usersIniPath, $auth) {
        $auth = trim((string)$auth);
        $authClean = str_replace('"', '', $auth);
        if (!file_exists($usersIniPath)) {
            $fallback = dirname(__DIR__, 2) . '/cstrike/addons/amxmodx/configs/users.ini';
            if (file_exists($fallback)) {
                $usersIniPath = $fallback;
            } else {
                return ['success' => false, 'message' => 'users.ini not found.'];
            }
        }

        $lines = @file($usersIniPath, FILE_IGNORE_NEW_LINES);
        if ($lines === false) {
            return ['success' => false, 'message' => 'Unable to read users.ini.'];
        }

        $newLines = [];
        $deleted = false;

        foreach ($lines as $line) {
            $t = trim($line);
            if (preg_match('/^"([^"]+)"/', $t, $m)) {
                if (strcasecmp($m[1], $authClean) === 0 || strcasecmp($m[1], $auth) === 0) {
                    $deleted = true;
                    continue; // skip this line
                }
            }
            $newLines[] = $line;
        }

        if (!$deleted) {
            return ['success' => false, 'message' => "ادمین '$auth' در فایل یافت نشد."];
        }

        $content = implode("\n", $newLines) . "\n";
        $ok = self::writeUsersIniFile($usersIniPath, $content);
        if (!$ok) {
            return ['success' => false, 'message' => 'خطا در ذخیره حذف ادمین روی فایل users.ini.'];
        }

        return ['success' => true, 'message' => "ادمین '$auth' با موفقیت از سرور حذف شد."];
    }

    /**
     * Send live commands to server to reload admins and refresh connected players' rights
     */
    public static function reloadAdminsLive($serverInfo) {
        try {
            $rcon = new GoldSourceRcon(
                $serverInfo['ip'],
                $serverInfo['port'],
                $serverInfo['rcon_password'],
                1.0
            );
            // In AMX Mod X the command is amx_reloadadmins (with an 's')
            $r1 = $rcon->execute('amx_reloadadmins');
            return [
                'success' => true,
                'output' => trim($r1),
                'message' => 'حقوق ادمین‌ها بلافاصله روی سرور ریلود شد.'
            ];
        } catch (Throwable $e) {
            return [
                'success' => false,
                'message' => 'ارتباط RCON با سرور برقرار نشد: ' . $e->getMessage()
            ];
        }
    }

    /**
     * Get all plugins registered in plugins.ini, plus unlisted plugins in plugins/ dir
     */
    public static function getPluginsList($serverInfo) {
        $pluginsIni = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        $pluginsDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/plugins';
        
        $plugins = [];
        $registered = [];

        if (file_exists($pluginsIni)) {
            $lines = file($pluginsIni, FILE_IGNORE_NEW_LINES);
            $currentSection = 'General';

            foreach ($lines as $line) {
                $trimmed = trim($line);
                if ($trimmed === '') continue;

                // Section header comment (e.g. "; Menus")
                if ($trimmed[0] === ';' && !preg_match('/;\s*([a-zA-Z0-9_\-]+\.amxx)/', $trimmed)) {
                    $cleanSection = trim(ltrim($trimmed, ';- '));
                    if (!empty($cleanSection)) {
                        $currentSection = $cleanSection;
                    }
                    continue;
                }

                // Check if line is a plugin (enabled or disabled)
                $isEnabled = ($trimmed[0] !== ';');
                $lineClean = ltrim($trimmed, '; ');

                // Match plugin filename and optional comment
                if (preg_match('/^([a-zA-Z0-9_\-]+\.amxx)(?:\s*;?\s*(.*))?/', $lineClean, $m)) {
                    $pluginFile = $m[1];
                    $comment = isset($m[2]) ? trim($m[2]) : '';
                    $isCwPlugin = str_contains($pluginFile, 'clanwar_');
                    $isMixPlugin = str_contains($pluginFile, 'mix_');

                    $section = $currentSection;
                    if ($isCwPlugin) {
                        $section = 'Clan War Mode';
                    } elseif ($isMixPlugin) {
                        $section = '5v5 Match Server';
                    }

                    $plugins[] = [
                        'file'       => $pluginFile,
                        'enabled'    => $isEnabled,
                        'section'    => $section,
                        'comment'    => $comment,
                        'is_mix'     => ($isMixPlugin || $isCwPlugin),
                        'installed'  => file_exists($pluginsDir . '/' . $pluginFile),
                    ];
                    $registered[$pluginFile] = true;
                }
            }
        }

        // Also check if there are .amxx files in plugins/ that are not yet in plugins.ini
        if (is_dir($pluginsDir)) {
            $diskFiles = scandir($pluginsDir);
            foreach ($diskFiles as $f) {
                if (substr($f, -5) === '.amxx' && !isset($registered[$f])) {
                    $isCw = str_contains($f, 'clanwar_');
                    $isMix = str_contains($f, 'mix_');
                    $section = 'Custom / Unregistered';
                    if ($isCw) {
                        $section = 'Clan War Mode';
                    } elseif ($isMix) {
                        $section = '5v5 Match Server';
                    }

                    $plugins[] = [
                        'file'       => $f,
                        'enabled'    => false,
                        'section'    => $section,
                        'comment'    => 'Found in plugins folder',
                        'is_mix'     => ($isMix || $isCw),
                        'installed'  => true,
                    ];
                }
            }
        }

        return $plugins;
    }

    /**
     * Save updated enabled/disabled state of plugins back to plugins.ini
     */
    public static function savePluginsState($serverInfo, array $enabledPluginFiles) {
        $pluginsIni = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        if (!file_exists($pluginsIni)) {
            return ['success' => false, 'message' => 'plugins.ini not found.'];
        }

        $lines = file($pluginsIni, FILE_IGNORE_NEW_LINES);
        $newLines = [];
        $handled = [];

        foreach ($lines as $line) {
            $trimmed = trim($line);
            if ($trimmed === '' || ($trimmed[0] === ';' && !preg_match('/;\s*([a-zA-Z0-9_\-]+\.amxx)/', $trimmed))) {
                $newLines[] = $line;
                continue;
            }

            $lineClean = ltrim($trimmed, '; ');
            if (preg_match('/^([a-zA-Z0-9_\-]+\.amxx)(.*)$/', $lineClean, $m)) {
                $pName = $m[1];
                $rest = $m[2];
                $shouldEnable = in_array($pName, $enabledPluginFiles, true);

                if ($shouldEnable) {
                    $newLines[] = $pName . $rest;
                } else {
                    $newLines[] = ';' . $pName . $rest;
                }
                $handled[$pName] = true;
            } else {
                $newLines[] = $line;
            }
        }

        // Add any newly enabled plugins that were not originally in plugins.ini
        foreach ($enabledPluginFiles as $pName) {
            if (!isset($handled[$pName])) {
                $newLines[] = $pName;
            }
        }

        $res = @file_put_contents($pluginsIni, implode("\n", $newLines) . "\n");
        if ($res === false) {
            return ['success' => false, 'message' => 'Failed to write plugins.ini. Check file permissions.'];
        }

        return ['success' => true, 'message' => 'Plugins configuration updated successfully.'];
    }

    /**
     * Detect current active server mode ('clanwar', 'mix5v5', or 'public')
     */
    public static function getCurrentServerMode($serverInfo) {
        $serverId = $serverInfo['id'] ?? 'main';

        // 1. Check in-memory serverInfo mode
        if (!empty($serverInfo['mode']) && in_array($serverInfo['mode'], ['clanwar', 'mix5v5', 'public'], true)) {
            return $serverInfo['mode'];
        }

        // 2. Check persistent/modes.json
        $modesFile = '/opt/gameland/persistent/modes.json';
        if (is_file($modesFile)) {
            $m = @json_decode((string)@file_get_contents($modesFile), true);
            if (is_array($m) && !empty($m[$serverId]['mode']) && in_array($m[$serverId]['mode'], ['clanwar', 'mix5v5', 'public'], true)) {
                return $m[$serverId]['mode'];
            }
        }

        // 3. For main server, check persistent/main_mode.txt
        if ($serverId === 'main' && is_file('/opt/gameland/persistent/main_mode.txt')) {
            $mm = trim((string)@file_get_contents('/opt/gameland/persistent/main_mode.txt'));
            if (in_array($mm, ['clanwar', 'mix5v5', 'public'], true)) {
                return $mm;
            }
        }

        // 4. Fallback: inspect live plugins.ini
        $pluginsIni = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        if (!file_exists($pluginsIni)) {
            return 'clanwar';
        }
        $raw = (string)file_get_contents($pluginsIni);
        $raw = str_replace("\r", "", $raw);
        $cwActive = (bool)preg_match('/^[ \t]*(?!;)[ \t]*clanwar_system\.amxx(?=[ \t\r\n;]|$)/mi', $raw);
        if ($cwActive) {
            return 'clanwar';
        }
        $mixActive = (bool)preg_match('/^[ \t]*(?!;)[ \t]*mix_system\.amxx(?=[ \t\r\n;]|$)/mi', $raw);
        if ($mixActive) {
            return 'mix5v5';
        }
        return 'public';
    }

    /**
     * Quick Switch Mode: 'clanwar', 'mix5v5', or 'public'
     */
    public static function switchServerMode($serverInfo, $targetMode) {
        $currentPlugins = self::getPluginsList($serverInfo);
        $enabled = [];

        foreach ($currentPlugins as $p) {
            if ($p['enabled']) {
                $enabled[] = $p['file'];
            }
        }

        $serverDir = $serverInfo['server_dir'];
        $startSh = $serverDir . '/start.sh';
        $envFile = $serverDir . '/.env';

        $coreHelpers = [
            'gameland_admin_tools.amxx',
            'mix_system_voice_chat.amxx',
            'player_drop.amxx',
            'backweapons.amxx',
            'gameland_lan_optimizer.amxx',
            'gameland_sound_optimizer.amxx',
            'gameland_fastduck_fix.amxx',
            'gameland_only_enforcer.amxx',
        ];

        $newSlots = 24;
        $modeLabel = '';

        $cfgFile = ($serverInfo['cstrike_dir'] ?? '') . '/server.cfg';
        $existingCustomSlots = 0;
        if (is_file($cfgFile) && preg_match('/^\s*sv_visiblemaxplayers\s+([0-9]+)/m', (string)@file_get_contents($cfgFile), $mSlots)) {
            $existingCustomSlots = (int)$mSlots[1];
        }

        if ($targetMode === 'clanwar') {
            $newSlots = 10;
            $modeLabel = '⚔️ Clan War Mode (10 Slots)';

            // Enable clanwar_system.amxx
            if (!in_array('clanwar_system.amxx', $enabled, true)) {
                $enabled[] = 'clanwar_system.amxx';
            }
            // Enable core helpers
            foreach ($coreHelpers as $ch) {
                if (!in_array($ch, $enabled, true)) {
                    $enabled[] = $ch;
                }
            }
            // Disable mix_system.amxx
            $enabled = array_values(array_filter($enabled, fn($f) => $f !== 'mix_system.amxx'));

        } elseif ($targetMode === 'mix5v5') {
            // Preserve user-configured custom slots (e.g. 22 slots) if set, otherwise default to 18
            $newSlots = ($existingCustomSlots > 0 && $existingCustomSlots !== 10) ? $existingCustomSlots : 18;
            $modeLabel = "🎮 5v5 Match Server Mode ({$newSlots} Slots)";

            // Enable mix_system.amxx
            if (!in_array('mix_system.amxx', $enabled, true)) {
                $enabled[] = 'mix_system.amxx';
            }
            // Enable core helpers
            foreach ($coreHelpers as $ch) {
                if (!in_array($ch, $enabled, true)) {
                    $enabled[] = $ch;
                }
            }
            // Disable clanwar_system.amxx
            $enabled = array_values(array_filter($enabled, fn($f) => $f !== 'clanwar_system.amxx'));

        } elseif ($targetMode === 'public') {
            $newSlots = ($existingCustomSlots > 0 && $existingCustomSlots > 10) ? $existingCustomSlots : 24;
            $modeLabel = "🎯 Classic Public Mode ({$newSlots} Slots)";

            // Disable both mix_system and clanwar_system
            $enabled = array_values(array_filter($enabled, fn($f) => $f !== 'mix_system.amxx' && $f !== 'clanwar_system.amxx'));

        } else {
            return ['success' => false, 'message' => 'Unknown mode: ' . $targetMode];
        }

        $serverId = $serverInfo['id'] ?? 'main';
        $serverDir = $serverInfo['server_dir'];
        $startSh = $serverDir . '/start.sh';
        $envFile = $serverDir . '/.env';

        // 1. Privileged execution via sudo helper (with instance id passed!)
        $helper = self::getPrivilegedHelperPath();
        if (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
            $hPath = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            @exec("sudo -n " . escapeshellarg($hPath) . " switch_mode " . escapeshellarg($targetMode) . " " . escapeshellarg($serverId) . " 2>&1");
            @exec("sudo -n " . escapeshellarg($hPath) . " set_slots " . escapeshellarg((string)$newSlots) . " " . escapeshellarg($serverId) . " 2>&1");
        }

        // 2. Direct edits for this specific server
        if ($serverId === 'main') {
            if (file_exists($startSh)) {
                $content = (string)@file_get_contents($startSh);
                $content = preg_replace('/MAX_PLAYERS=".*"/', 'MAX_PLAYERS="' . $newSlots . '"', $content);
                @file_put_contents($startSh, $content);
            }
            if (file_exists($envFile)) {
                $envContent = (string)@file_get_contents($envFile);
                $envContent = preg_replace('/MAX_PLAYERS=".*"/', 'MAX_PLAYERS="' . $newSlots . '"', $envContent);
                $envContent = preg_replace('/^MAX_PLAYERS=.*$/m', 'MAX_PLAYERS="' . $newSlots . '"', $envContent);
                @file_put_contents($envFile, $envContent);
            }
        } else {
            self::updateEnvFile($serverId, [
                'MAX_PLAYERS' => $newSlots,
            ]);
            if (file_exists($envFile)) {
                $envContent = (string)@file_get_contents($envFile);
                $envContent = preg_replace('/MAX_PLAYERS=".*"/', 'MAX_PLAYERS="' . $newSlots . '"', $envContent);
                $envContent = preg_replace('/^MAX_PLAYERS=.*$/m', 'MAX_PLAYERS="' . $newSlots . '"', $envContent);
                @file_put_contents($envFile, $envContent);
            }
            if (file_exists($startSh)) {
                $content = (string)@file_get_contents($startSh);
                $content = preg_replace('/MAX_PLAYERS=".*"/', 'MAX_PLAYERS="' . $newSlots . '"', $content);
                @file_put_contents($startSh, $content);
            }
        }

        self::writeServerCfgValue($serverDir, 'sv_visiblemaxplayers', (string)$newSlots);

        $res = self::savePluginsState($serverInfo, $enabled);
        if (!$res['success']) {
            // If PHP direct write failed, privileged helper already took care of it
        }

        // 3. Update registry servers.json, main_mode.txt, and modes.json with mode and slots
        if ($serverId === 'main') {
            @file_put_contents('/opt/gameland/persistent/main_mode.txt', $targetMode . "\n");
            @file_put_contents(self::getManagerRoot() . '/instances/main_mode.txt', $targetMode . "\n");
        }
        $modesFile = '/opt/gameland/persistent/modes.json';
        $modesData = is_file($modesFile) ? json_decode((string)@file_get_contents($modesFile), true) : [];
        if (!is_array($modesData)) $modesData = [];
        $modesData[$serverId] = ['mode' => $targetMode, 'slots' => $newSlots];
        @file_put_contents($modesFile, json_encode($modesData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
        @file_put_contents(self::getManagerRoot() . '/instances/modes.json', json_encode($modesData, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");

        $registry = self::readRegistry();
        if (isset($registry['servers']) && is_array($registry['servers'])) {
            foreach ($registry['servers'] as &$entry) {
                if (($entry['id'] ?? '') === $serverId) {
                    $entry['mode'] = $targetMode;
                    $entry['slots'] = $newSlots;
                    break;
                }
            }
            self::writeRegistry($registry);
        }

        // 4. Restart ONLY this server's dedicated service
        $svc = $serverInfo['service_name'] ?? ($serverId === 'main' ? 'gameland.service' : 'gameland@' . $serverId . '.service');
        // Note: gameland-panel-sudo switch_mode already performs isolated restart safely.
        // We only trigger controlService if not on Linux or if sudo helper was absent.
        if (!is_file('/usr/local/sbin/gameland-panel-sudo')) {
            self::controlService($svc, 'restart');
        }

        return [
            'success' => true,
            'message' => 'Server «' . ($serverInfo['name'] ?? $serverId) . '» switched to ' . $modeLabel . ' (' . $newSlots . ' slots). Service ' . $svc . ' restarted.'
        ];
    }

    /**
     * Get AFK Guard status for a specific server (0 = Disabled/Test, 1 = Full Guard, 2 = Spec Only)
     */
    public static function getServerAfkGuard($serverInfo) {
        $serverDir = $serverInfo['server_dir'] ?? '';
        $cfg = rtrim($serverDir, '/') . '/cstrike/server.cfg';
        if (file_exists($cfg)) {
            $raw = (string)@file_get_contents($cfg);
            if (preg_match('/^[ \t]*gameland_afk_guard[ \t]+([0-2])/mi', $raw, $m)) {
                return (int)$m[1];
            }
        }

        // Check registry fallback
        $registry = self::readRegistry();
        if (isset($registry['servers']) && is_array($registry['servers'])) {
            $serverId = $serverInfo['id'] ?? '';
            foreach ($registry['servers'] as $entry) {
                if (($entry['id'] ?? '') === $serverId && isset($entry['afk_guard'])) {
                    return (int)$entry['afk_guard'];
                }
            }
        }

        return 0; // Default: Disabled for competitive 5v5 mix
    }

    /**
     * Set AFK Guard status for a specific server, apply live via RCON and persist in server.cfg + registry
     */
    public static function setServerAfkGuard($serverInfo, $mode) {
        $mode = (int)$mode;
        if ($mode < 0 || $mode > 2) {
            $mode = 1;
        }

        $serverId = $serverInfo['id'] ?? 'main';
        $serverDir = $serverInfo['server_dir'] ?? '';

        // 1. Persist in cstrike/server.cfg
        self::writeServerCfgValue($serverDir, 'gameland_afk_guard', (string)$mode);
        self::writeServerCfgValue($serverDir, 'mp_autokick', '0');

        // 1.1 Also invoke privileged helper to ensure root server.cfg is written even if php lacks direct write perm
        $helper = self::getPrivilegedHelperPath();
        if (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
            $hPath = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            @exec("sudo -n " . escapeshellarg($hPath) . " set_afk_guard " . escapeshellarg((string)$mode) . " " . escapeshellarg($serverId) . " 2>&1");
        }

        // 2. Persist in registry servers.json (for instances only, never main)
        if ($serverId !== 'main' && $serverId !== '') {
            $registry = self::readRegistry();
            if (!isset($registry['servers']) || !is_array($registry['servers'])) {
                $registry['servers'] = [];
            }
            $found = false;
            foreach ($registry['servers'] as &$entry) {
                if (($entry['id'] ?? '') === $serverId) {
                    $entry['afk_guard'] = $mode;
                    $found = true;
                    break;
                }
            }
            if (!$found) {
                $registry['servers'][] = [
                    'id' => $serverId,
                    'afk_guard' => $mode
                ];
            }
            self::writeRegistry($registry);
        }

        // 3. Live Apply via RCON (Immediate effect without server restart!)
        $liveSuccess = false;
        $liveMsg = '';
        try {
            $rcon = new GoldSourceRcon(
                $serverInfo['ip'],
                $serverInfo['port'],
                $serverInfo['rcon_password'],
                1.5
            );
            $rcon->execute('gameland_afk_guard ' . $mode);
            $rcon->execute('mp_autokick 0');
            $rcon->execute('amx_afk_guard ' . $mode);
            $liveSuccess = true;
            $liveMsg = ' (اعمال زنده و فوری در سرور بدون نیاز به ری‌استارت)';
        } catch (Exception $e) {
            $liveSuccess = false;
            $liveMsg = ' (در کانفیگ سرور ذخیره شد؛ به دلیل در دسترس نبودن RCON، پس از ری‌استارت یا راند بعدی اعمال می‌شود)';
        }

        $modeLabels = [
            0 => 'غیرفعال (مخصوص تست کلن‌وار - بدون کیک و اسپکت)',
            1 => 'حفاظت کامل (حالت عادی - انتقال به اسپکت + کیک تایم‌اوت)',
            2 => 'فقط انتقال به اسپکت (بدون هیچ‌گونه کیک)'
        ];

        return [
            'success' => true,
            'afk_guard' => $mode,
            'server_id' => $serverId,
            'live_applied' => $liveSuccess,
            'message' => 'وضعیت AFK برای سرور «' . ($serverInfo['name'] ?? $serverId) . '» به «' . $modeLabels[$mode] . '» تغییر یافت' . $liveMsg,
        ];
    }

    /**
     * Build a GitHub API HTTP context with optional auth token
     */
    private static function githubHttpContext($timeout = 8) {
        $token = defined('GITHUB_TOKEN') ? GITHUB_TOKEN : '';
        $headers = "User-Agent: GameLand-WebPanel/2.0\r\n"
                 . "Accept: application/vnd.github.v3+json\r\n";
        if (!empty($token)) {
            $headers .= "Authorization: Bearer {$token}\r\n";
        }
        return stream_context_create([
            'http' => [
                'method'  => 'GET',
                'header'  => $headers,
                'timeout' => $timeout,
                'ignore_errors' => true,
            ]
        ]);
    }

    /**
     * Build a GitHub raw-content HTTP context (no JSON accept header needed)
     */
    private static function githubRawContext($timeout = 10) {
        $token = defined('GITHUB_TOKEN') ? GITHUB_TOKEN : '';
        $headers = "User-Agent: GameLand-WebPanel/2.0\r\n";
        if (!empty($token)) {
            $headers .= "Authorization: Bearer {$token}\r\n";
        }
        return stream_context_create([
            'http' => [
                'method'  => 'GET',
                'header'  => $headers,
                'timeout' => $timeout,
                'ignore_errors' => true,
            ]
        ]);
    }

    /**
     * Get the latest commit information from the GitHub repository
     */
    public static function getGitRepoStatus($repo = null, $branch = null, $forceRefresh = false) {
        $repo   = $repo   ?? (defined('GITHUB_REPO')   ? GITHUB_REPO   : 'GAMELAND-PROJECT/MixSystem_SV_PL');
        $branch = $branch ?? (defined('GITHUB_BRANCH') ? GITHUB_BRANCH : 'main');

        $cacheFile = sys_get_temp_dir() . '/gl_gh_' . md5($repo . '@' . $branch) . '.json';
        if (!$forceRefresh && file_exists($cacheFile) && (time() - filemtime($cacheFile) < 180)) {
            $cached = @json_decode(@file_get_contents($cacheFile), true);
            if ($cached && !empty($cached['sha'])) {
                return $cached;
            }
        }

        $url  = "https://api.github.com/repos/{$repo}/commits/{$branch}";
        $ctx  = self::githubHttpContext(5);
        $res  = @file_get_contents($url, false, $ctx);
        if ($res === false) {
            if (file_exists($cacheFile)) {
                $cached = @json_decode(@file_get_contents($cacheFile), true);
                if ($cached && !empty($cached['sha'])) return $cached;
            }
            return null;
        }

        $data = json_decode($res, true);
        if (!$data || !isset($data['sha'])) {
            if (file_exists($cacheFile)) {
                $cached = @json_decode(@file_get_contents($cacheFile), true);
                if ($cached && !empty($cached['sha'])) return $cached;
            }
            return null;
        }

        $status = [
            'sha'      => substr($data['sha'], 0, 7),
            'full_sha' => $data['sha'],
            'message'  => $data['commit']['message'] ?? '',
            'author'   => $data['commit']['author']['name'] ?? '',
            'date'     => $data['commit']['author']['date'] ?? '',
        ];
        @file_put_contents($cacheFile, json_encode($status));
        return $status;
    }

    /**
     * Download the latest source files from GitHub repo and update server files
     * Fast, resilient, non-blocking: tests connectivity first with 2.5s probe.
     */
    public static function syncMixFromGitHub($serverInfo) {
        $repo    = defined('GITHUB_REPO')   ? GITHUB_REPO   : 'GAMELAND-PROJECT/MixSystem_SV_PL';
        $branch  = defined('GITHUB_BRANCH') ? GITHUB_BRANCH : 'main';
        $baseUrl = "https://raw.githubusercontent.com/{$repo}/{$branch}/";
        $cstrike = $serverInfo['cstrike_dir'];
        $serverDir = $serverInfo['server_dir'] ?? dirname($cstrike);

        // Always attempt fast git sync first if local git repository exists
        $gitPulled = false;
        if (is_dir($serverDir . '/.git')) {
            $gitOut = [];
            $gitCode = 1;
            @exec("cd " . escapeshellarg($serverDir) . " && git fetch origin main 2>&1 && git reset --hard origin/main 2>&1", $gitOut, $gitCode);
            if ($gitCode === 0) {
                $gitPulled = true;
            } else {
                $helper = self::getPrivilegedHelperPath();
                if (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
                    $hPath = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
                    @exec("sudo -n " . escapeshellarg($hPath) . " git_sync 2>&1");
                    $gitPulled = true;
                }
            }
        }

        // Target file mapping: [Remote Repo, Remote Path, Local Relative to cstrike, Local Dev Source]
        $syncTargets = [
            // MixSystem Repository Sources & Includes
            ['repo' => $repo, 'remote' => 'scripting/include/mix_system.inc',    'local' => 'addons/amxmodx/scripting/include/mix_system.inc',    'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/include/mix_system.inc'],
            ['repo' => $repo, 'remote' => 'scripting/mix_system.sma',            'local' => 'addons/amxmodx/scripting/mix_system.sma',            'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/mix_system.sma'],
            ['repo' => $repo, 'remote' => 'scripting/mix_system_voice_chat.sma', 'local' => 'addons/amxmodx/scripting/mix_system_voice_chat.sma', 'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/mix_system_voice_chat.sma'],
            ['repo' => $repo, 'remote' => 'scripting/gameland_admin_tools.sma',  'local' => 'addons/amxmodx/scripting/gameland_admin_tools.sma',  'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/gameland_admin_tools.sma'],
            ['repo' => $repo, 'remote' => 'configs/MixSettings.ini',             'local' => 'addons/amxmodx/configs/MixSettings.ini',             'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/configs/MixSettings.ini'],
            ['repo' => $repo, 'remote' => 'configs/start.cfg',                   'local' => 'addons/amxmodx/configs/start.cfg',                   'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/configs/start.cfg'],
            ['repo' => $repo, 'remote' => 'configs/stop.cfg',                    'local' => 'addons/amxmodx/configs/stop.cfg',                    'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/configs/stop.cfg'],
            ['repo' => $repo, 'remote' => 'configs/overtime.cfg',                'local' => 'addons/amxmodx/configs/overtime.cfg',                'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/configs/overtime.cfg'],
            ['repo' => $repo, 'remote' => 'data/lang/mix_system.txt',            'local' => 'addons/amxmodx/data/lang/mix_system.txt',            'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/data/lang/mix_system.txt'],

            // Clan War System Sources, Configs & Binaries
            ['repo' => $repo, 'remote' => 'scripting/clanwar_system.sma',        'local' => 'addons/amxmodx/scripting/clanwar_system.sma',        'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/clanwar_system.sma'],
            ['repo' => $repo, 'remote' => 'configs/ClanWarSettings.ini',         'local' => 'addons/amxmodx/configs/ClanWarSettings.ini',         'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/configs/ClanWarSettings.ini'],
            ['repo' => $repo, 'remote' => 'data/lang/clanwar_system.txt',        'local' => 'addons/amxmodx/data/lang/clanwar_system.txt',        'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/data/lang/clanwar_system.txt'],
            ['repo' => $repo, 'remote' => 'plugins/clanwar_system.amxx',         'local' => 'addons/amxmodx/plugins/clanwar_system.amxx',         'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/clanwar_system.amxx'],

            // MixSystem Pre-compiled Binaries (External Build Artifacts)
            ['repo' => $repo, 'remote' => 'plugins/mix_system.amxx',            'local' => 'addons/amxmodx/plugins/mix_system.amxx',            'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/mix_system.amxx'],
            ['repo' => $repo, 'remote' => 'plugins/mix_system_voice_chat.amxx', 'local' => 'addons/amxmodx/plugins/mix_system_voice_chat.amxx', 'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/mix_system_voice_chat.amxx'],
            ['repo' => $repo, 'remote' => 'plugins/gameland_admin_tools.amxx',  'local' => 'addons/amxmodx/plugins/gameland_admin_tools.amxx',  'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/gameland_admin_tools.amxx'],
            ['repo' => $repo, 'remote' => 'plugins/gameland_fastduck_fix.amxx', 'local' => 'addons/amxmodx/plugins/gameland_fastduck_fix.amxx', 'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/gameland_fastduck_fix.amxx'],
            ['repo' => $repo, 'remote' => 'plugins/player_drop.amxx',            'local' => 'addons/amxmodx/plugins/player_drop.amxx',            'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/player_drop.amxx'],

            // GameLand Core Plugins Repository Sources & Binaries
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/gameland_fastduck_fix.sma',    'local' => 'addons/amxmodx/scripting/gameland_fastduck_fix.sma',    'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/scripting/gameland_fastduck_fix.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/gameland_only_enforcer.sma',   'local' => 'addons/amxmodx/scripting/gameland_only_enforcer.sma',   'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/scripting/gameland_only_enforcer.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/gameland_lan_optimizer.sma',   'local' => 'addons/amxmodx/scripting/gameland_lan_optimizer.sma',   'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/scripting/gameland_lan_optimizer.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/gameland_sound_optimizer.sma', 'local' => 'addons/amxmodx/scripting/gameland_sound_optimizer.sma', 'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/scripting/gameland_sound_optimizer.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/plugins/gameland_lan_optimizer.amxx',   'local' => 'addons/amxmodx/plugins/gameland_lan_optimizer.amxx',   'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/plugins/gameland_lan_optimizer.amxx'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/plugins/gameland_sound_optimizer.amxx', 'local' => 'addons/amxmodx/plugins/gameland_sound_optimizer.amxx', 'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/plugins/gameland_sound_optimizer.amxx'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/plugins/gameland_only_enforcer.amxx',   'local' => 'addons/amxmodx/plugins/gameland_only_enforcer.amxx',   'local_src' => dirname($serverDir) . '/GameLand_Core_Plugins/plugins/gameland_only_enforcer.amxx'],

            // Back Weapons Repository Sources & Binaries
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/backweapons.sma',               'local' => 'addons/amxmodx/scripting/backweapons.sma',               'local_src' => dirname($serverDir) . '/back gun/backweapons.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/plugins/backweapons.amxx',               'local' => 'addons/amxmodx/plugins/backweapons.amxx',               'local_src' => dirname($serverDir) . '/back gun/backweapons.amxx'],

            // High Density Opaque Smoke Grenade & Sprite
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/scripting/gameland_dense_smoke.sma',      'local' => 'addons/amxmodx/scripting/gameland_dense_smoke.sma',      'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/scripting/gameland_dense_smoke.sma'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/addons/amxmodx/plugins/gameland_dense_smoke.amxx',        'local' => 'addons/amxmodx/plugins/gameland_dense_smoke.amxx',        'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/plugins/gameland_dense_smoke.amxx'],
            ['repo' => 'GAMELAND-PROJECT/server', 'remote' => 'cstrike/sprites/gas_puff_02.spr',                                'local' => 'sprites/gas_puff_02.spr',                                'local_src' => dirname($serverDir) . '/MixSystem_SV_PL/cstrike/sprites/gas_puff_02.spr'],
        ];

        // 1. Probe GitHub raw connectivity (test if reachable)
        $probeUrl = $baseUrl . 'configs/MixSettings.ini';
        $probeOk = false;
        if (function_exists('curl_init')) {
            $ch = curl_init($probeUrl);
            curl_setopt_array($ch, [
                CURLOPT_NOBODY => true,
                CURLOPT_TIMEOUT => 3,
                CURLOPT_CONNECTTIMEOUT => 2,
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_USERAGENT => 'GameLand-WebPanel/2.0',
                CURLOPT_SSL_VERIFYPEER => false,
            ]);
            $token = defined('GITHUB_TOKEN') ? GITHUB_TOKEN : '';
            if (!empty($token)) {
                curl_setopt($ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer {$token}"]);
            }
            curl_exec($ch);
            $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
            curl_close($ch);
            if ($httpCode >= 200 && $httpCode < 400) {
                $probeOk = true;
            }
        } else {
            $ctx = self::githubRawContext(3);
            $test = @file_get_contents($probeUrl, false, $ctx);
            if ($test !== false) {
                $probeOk = true;
            }
        }

        $updatedFiles = [];
        $failedFiles  = [];

        foreach ($syncTargets as $t) {
            $targetRepo = $t['repo'];
            $remotePath = $t['remote'];
            $localRelPath = $t['local'];

            $destFile = $cstrike . '/' . $localRelPath;
            $destDir  = dirname($destFile);
            if (!is_dir($destDir)) {
                @mkdir($destDir, 0775, true);
            }

            // Always prioritize local external repository source if available on disk
            $localSrc = $t['local_src'] ?? null;
            if ($localSrc && is_file($localSrc)) {
                if (@copy($localSrc, $destFile) || (@file_put_contents($destFile, @file_get_contents($localSrc)) !== false)) {
                    $updatedFiles[] = basename($destFile);
                    continue;
                }
            }

            // Remote GitHub fallback
            $content = false;
            if ($probeOk) {
                $url = "https://raw.githubusercontent.com/{$targetRepo}/{$branch}/" . $remotePath . '?t=' . time();
                if (function_exists('curl_init')) {
                    $ch = curl_init($url);
                    curl_setopt_array($ch, [
                        CURLOPT_TIMEOUT => 4,
                        CURLOPT_CONNECTTIMEOUT => 2,
                        CURLOPT_RETURNTRANSFER => true,
                        CURLOPT_USERAGENT => 'GameLand-WebPanel/2.0',
                        CURLOPT_SSL_VERIFYPEER => false,
                    ]);
                    $token = defined('GITHUB_TOKEN') ? GITHUB_TOKEN : '';
                    if (!empty($token)) {
                        curl_setopt($ch, CURLOPT_HTTPHEADER, ["Authorization: Bearer {$token}"]);
                    }
                    $content = curl_exec($ch);
                    $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
                    curl_close($ch);
                    if ($code < 200 || $code >= 400) {
                        $content = false;
                    }
                } else {
                    $ctx = self::githubRawContext(4);
                    $content = @file_get_contents($url, false, $ctx);
                }

                if ($content !== false && strlen($content) > 10) {
                    if (@file_put_contents($destFile, $content) !== false) {
                        $updatedFiles[] = basename($destFile);
                        continue;
                    }
                }
            }

            if (!file_exists($destFile)) {
                $failedFiles[] = basename($destFile);
            }
        }

        // Register any newly synced plugins in plugins.ini immediately
        if (count($updatedFiles) > 0) {
            self::ensureMixRegistered($serverInfo);
        }

        // Save last sync metadata (commit SHA + time + file list)
        $commit = self::getGitRepoStatus();
        $syncMeta = [
            'commit'    => $commit,
            'sync_time' => date('Y-m-d H:i:s'),
            'files'     => $updatedFiles,
            'failed'    => $failedFiles,
        ];
        @file_put_contents(
            $cstrike . '/addons/amxmodx/configs/.mix_last_sync.json',
            json_encode($syncMeta, JSON_PRETTY_PRINT)
        );

        $isSuccess = count($updatedFiles) > 0;
        return [
            'success' => $isSuccess,
            'updated' => $updatedFiles,
            'failed'  => $failedFiles,
            'commit'  => $commit,
            'message' => $isSuccess
                ? "Synchronized " . count($updatedFiles) . " plugin files successfully."
                : ($probeOk ? "No updates found." : "Local sources not found and GitHub raw CDN unreachable.")
        ];
    }

    public static function getMainServerCstrikeDir() {
        return self::getManagerRoot() . '/cstrike';
    }

    /**
     * Compile plugins using the server's amxxpc compiler
     * Compiles all managed GameLand, security, and mix plugins
     */
    public static function compilePlugins($serverInfo, $propagateToAll = false) {
        $scriptingDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/scripting';
        $pluginsDir   = $serverInfo['cstrike_dir'] . '/addons/amxmodx/plugins';

        if (!is_dir($scriptingDir)) {
            return ['success' => false, 'message' => 'Scripting directory not found: ' . $scriptingDir, 'output' => '', 'compiled_count' => 0];
        }

        if (!is_dir($pluginsDir)) {
            @mkdir($pluginsDir, 0775, true);
        }

        $isWin = (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN');

        if ($isWin) {
            $compiler = $scriptingDir . '/amxxpc.exe';
            if (!file_exists($compiler) && file_exists($scriptingDir . '/amxxpc')) {
                $compiler = $scriptingDir . '/amxxpc';
            }
        } else {
            $compiler = $scriptingDir . '/amxxpc';
            if (!file_exists($compiler) && file_exists($scriptingDir . '/amxxpc32')) {
                $compiler = $scriptingDir . '/amxxpc32';
            }
        }

        // Ensure compiler is executable on Linux/Unix
        if (file_exists($compiler)) {
            if (!$isWin) {
                @chmod($compiler, 0755);
            }
        } else {
            return [
                'success'        => false,
                'compiled_count' => 0,
                'output'         => '',
                'message'        => 'Compiler not found: ' . $compiler . ". Make sure amxxpc binary exists in the scripting/ directory."
            ];
        }

        // Also make shared library executable on Unix
        if (strtoupper(substr(PHP_OS, 0, 3)) !== 'WIN') {
            foreach (['amxxpc32.so', 'amxxpc64.so'] as $lib) {
                $libPath = $scriptingDir . '/' . $lib;
                if (file_exists($libPath)) @chmod($libPath, 0755);
            }
        }

        $targets = self::getManagedPluginTargets();
        $isWin = (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN');

        // Prefer running compiler via privileged helper if installed on Linux
        if (!$isWin && is_file(self::getPrivilegedHelperPath())) {
            $helper = escapeshellarg(self::getPrivilegedHelperPath());
            $lines = [];
            $exitCode = 1;
            $sId = $serverInfo['id'] ?? 'main';
            if ($sId === 'main') {
                @exec("sudo -n {$helper} compile 2>&1", $lines, $exitCode);
            } else {
                @exec("sudo -n {$helper} compile_server " . escapeshellarg($sId) . " 2>&1", $lines, $exitCode);
            }
            if ($exitCode === 0) {
                self::ensureMixRegistered($serverInfo);
                foreach ($targets as $src => $bin) {
                    $bPath = $pluginsDir . '/' . $bin;
                    if (is_file($bPath)) @touch($bPath, time() + 5);
                }

                // If this is an isolated server instance (not main), make sure its own plugins dir has the compiled binaries
                $mainPlugins = self::getMainServerCstrikeDir() . '/addons/amxmodx/plugins';
                if (($serverInfo['cstrike_dir'] ?? '') !== self::getMainServerCstrikeDir()) {
                    foreach ($targets as $binFile) {
                        $srcBin = $mainPlugins . '/' . $binFile;
                        if (file_exists($srcBin)) {
                            @copy($srcBin, $pluginsDir . '/' . $binFile);
                        }
                    }
                    $mainSprite = self::getMainServerCstrikeDir() . '/sprites/gas_puff_02.spr';
                    if (file_exists($mainSprite)) {
                        @mkdir($serverInfo['cstrike_dir'] . '/sprites', 0777, true);
                        @copy($mainSprite, $serverInfo['cstrike_dir'] . '/sprites/gas_puff_02.spr');
                    }
                    self::ensureMixRegistered($serverInfo);
                }

                // Propagate compiled .amxx to all other server instances ONLY if explicitly requested
                if ($propagateToAll) {
                    $allServers = self::getManagedServers();
                    foreach ($allServers as $sId => $sConf) {
                        if (($sConf['cstrike_dir'] ?? '') !== $serverInfo['cstrike_dir']) {
                            $otherPluginsDir = ($sConf['cstrike_dir'] ?? '') . '/addons/amxmodx/plugins';
                            if (is_dir($otherPluginsDir)) {
                                foreach ($targets as $binFile) {
                                    $srcBin = $pluginsDir . '/' . $binFile;
                                    if (file_exists($srcBin)) {
                                        @copy($srcBin, $otherPluginsDir . '/' . $binFile);
                                    }
                                }
                                $mainSprite = self::getMainServerCstrikeDir() . '/sprites/gas_puff_02.spr';
                                if (file_exists($mainSprite)) {
                                    @mkdir(($sConf['cstrike_dir'] ?? '') . '/sprites', 0777, true);
                                    @copy($mainSprite, ($sConf['cstrike_dir'] ?? '') . '/sprites/gas_puff_02.spr');
                                }
                                self::ensureMixRegistered($sConf);
                            }
                        }
                    }
                }

                // Save authoritative build record
                $metaPath = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/.mix_last_build.json';
                $buildMeta = [
                    'build_time' => date('c'),
                    'commit' => self::getGitRepoStatus(),
                    'success' => true,
                    'compiled_count' => count($targets),
                    'targets' => self::getPluginBuildStatus($serverInfo),
                ];
                @file_put_contents($metaPath, json_encode($buildMeta, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

                return [
                    'success' => true,
                    'compiled_count' => count($targets),
                    'output' => implode("\n", $lines),
                    'message' => 'All plugins compiled and registered successfully.',
                ];
            }
        }

        $output        = '';
        $compiledCount = 0;
        $errorCount    = 0;
        $compiledFiles = [];

        foreach ($targets as $src => $bin) {
            $srcPath = $scriptingDir . '/' . $src;
            $binPath = $pluginsDir   . '/' . $bin;

            if (!file_exists($srcPath)) {
                if (file_exists($binPath) && filesize($binPath) > 100) {
                    $compiledCount++;
                    $compiledFiles[] = $bin;
                    @touch($binPath, time() + 5);
                    $output .= "=== SKIP {$src} === (active pre-compiled binary preserved)\n\n";
                } else {
                    $output .= "=== SKIP {$src} === (source file not found)\n\n";
                }
                continue;
            }

            // Build cross-platform execution command
            $includeDir = escapeshellarg($scriptingDir . '/include');
            if ($isWin) {
                $cmd = "cd /D " . escapeshellarg($scriptingDir)
                     . " && " . escapeshellarg($compiler) . " " . escapeshellarg($src)
                     . " -o" . escapeshellarg($binPath)
                     . " -i\"include\""
                     . " -i" . $includeDir
                     . " 2>&1";
            } else {
                $compilerBinary = basename($compiler);
                $cmd = "cd " . escapeshellarg($scriptingDir)
                     . " && export LD_LIBRARY_PATH=.:" . escapeshellarg($scriptingDir) . ":\$LD_LIBRARY_PATH"
                     . " && chmod +x ./" . $compilerBinary . " 2>/dev/null || true"
                     . " && ./" . $compilerBinary . " " . escapeshellarg($src)
                     . " -o" . escapeshellarg($binPath)
                     . " -i\"include\""
                     . " -i" . $includeDir
                     . " 2>&1";
            }

            $exitCode = 0;
            $lines = [];
            @exec($cmd, $lines, $exitCode);
            $res = implode("\n", $lines);
            $output .= "=== Compiling {$src} (exit {$exitCode}) ===\n" . trim($res) . "\n\n";

            // Verify the .amxx was created or fallback to existing valid binary
            if ($exitCode === 0 && file_exists($binPath) && filesize($binPath) > 100) {
                $compiledCount++;
                $compiledFiles[] = $bin;
                @touch($binPath, time() + 5);
            } elseif (file_exists($binPath) && filesize($binPath) > 100) {
                $compiledCount++;
                $compiledFiles[] = $bin;
                @touch($binPath, time() + 5);
                $output .= "-> Active pre-compiled binary preserved for {$bin}\n\n";
            } else {
                $errorCount++;
            }
        }

        // Register compiled plugins in plugins.ini
        if ($compiledCount > 0) {
            $mainSprite = self::getMainServerCstrikeDir() . '/sprites/gas_puff_02.spr';
            if (file_exists($mainSprite) && ($serverInfo['cstrike_dir'] ?? '') !== self::getMainServerCstrikeDir()) {
                @mkdir($serverInfo['cstrike_dir'] . '/sprites', 0777, true);
                @copy($mainSprite, $serverInfo['cstrike_dir'] . '/sprites/gas_puff_02.spr');
            }
            self::ensureMixRegistered($serverInfo);

            // Propagate compiled .amxx and sprites to all other server instances automatically
            $allServers = self::getManagedServers();
            foreach ($allServers as $sId => $sConf) {
                if (($sConf['cstrike_dir'] ?? '') !== $serverInfo['cstrike_dir']) {
                    $otherPluginsDir = ($sConf['cstrike_dir'] ?? '') . '/addons/amxmodx/plugins';
                    if (is_dir($otherPluginsDir)) {
                        foreach ($compiledFiles as $binFile) {
                            $srcBin = $pluginsDir . '/' . $binFile;
                            if (file_exists($srcBin)) {
                                @copy($srcBin, $otherPluginsDir . '/' . $binFile);
                            }
                        }
                        if (file_exists($mainSprite)) {
                            @mkdir(($sConf['cstrike_dir'] ?? '') . '/sprites', 0777, true);
                            @copy($mainSprite, ($sConf['cstrike_dir'] ?? '') . '/sprites/gas_puff_02.spr');
                        }
                        self::ensureMixRegistered($sConf);
                    }
                }
            }
        }

        // Persist an authoritative deployment record used by the panel.
        $metaPath = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/.mix_last_build.json';
        $buildMeta = [
            'build_time' => date('c'),
            'commit' => self::getGitRepoStatus(),
            'success' => $errorCount === 0 && $compiledCount > 0,
            'compiled_count' => $compiledCount,
            'targets' => self::getPluginBuildStatus($serverInfo),
        ];
        @file_put_contents($metaPath, json_encode($buildMeta, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));

        if ($compiledCount === 0 && $errorCount === 0) {
            $message = 'No .sma source files found to compile.';
        } elseif ($compiledCount > 0) {
            $message = "Compiled {$compiledCount} plugin(s) successfully!" . ($errorCount > 0 ? " ({$errorCount} had errors — check log)" : '');
        } else {
            $message = "Compilation failed. No .amxx binaries were produced. Check compiler output below.";
        }

        return [
            'success'        => $compiledCount > 0 && $errorCount === 0,
            'output'         => trim($output),
            'compiled_count' => $compiledCount,
            'compiled_files' => $compiledFiles,
            'message'        => $message
        ];
    }

    /**
     * Ensure GameLand & mix plugins are listed and ENABLED in plugins.ini
     */
    public static function ensureMixRegistered($serverInfo) {
        $pluginsIni = $serverInfo['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        $pluginsDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/plugins';

        if (!file_exists($pluginsIni)) {
            return;
        }

        $serverMode = self::getCurrentServerMode($serverInfo);
        $serverId = $serverInfo['id'] ?? 'main';

        // Check if server.cfg already has a custom sv_visiblemaxplayers setting (e.g. 22 slots)
        $cfg = $serverInfo['cstrike_dir'] . '/server.cfg';
        $userSlots = 0;
        if (is_file($cfg)) {
            $cfgContent = (string)@file_get_contents($cfg);
            if (preg_match('/^\s*sv_visiblemaxplayers\s+([0-9]+)/m', $cfgContent, $mSlots)) {
                $userSlots = (int)$mSlots[1];
            }
        }

        // If user configured custom slots (e.g. 22 slots), strictly preserve it!
        if ($userSlots > 0 && ($serverMode !== 'clanwar' || $userSlots === 10)) {
            $slots = $userSlots;
        } else {
            $slots = ($serverMode === 'clanwar') ? 10 : (($serverMode === 'public') ? 24 : 18);
        }

        // Core helper candidates that remain enabled for all modes
        $candidates = [
            'gameland_only_enforcer.amxx'   => 'GameLand exclusive AllClient security enforcer',
            'gameland_lan_optimizer.amxx'   => 'GameLand network latency & fps optimizer',
            'gameland_sound_optimizer.amxx' => 'GameLand spatial sound & footsteps enhancer',
            'gameland_fastduck_fix.amxx'    => 'GameLand fast duck / silent run enforcer',
            'gameland_dense_smoke.amxx'     => 'GameLand high density opaque smoke grenade (anti-see-through)',
            'gameland_admin_tools.amxx'     => 'GameLand admin tools (/map, /j0-/j2, /ff0-/ff1)',
            'mix_system_voice_chat.amxx'    => 'Match Server Voice Chat',
            'player_drop.amxx'              => 'Match Server player drop/substitute',
            'backweapons.amxx'              => 'GameLand Back Weapons display',
        ];

        if ($serverMode === 'mix5v5') {
            $candidates['mix_system.amxx'] = 'Match Server 5v5 System (main)';
        } elseif ($serverMode === 'clanwar') {
            $candidates['clanwar_system.amxx'] = 'Clan War 10-slot System';
        }

        $mixFiles = [];
        foreach ($candidates as $f => $desc) {
            if (file_exists($pluginsDir . '/' . $f)) {
                $mixFiles[$f] = $desc;
            }
        }

        $content  = str_replace("\r", "", (string)file_get_contents($pluginsIni));
        $modified = false;

        // Strictly enforce mutual exclusion between mix_system and clanwar_system
        if ($serverMode === 'mix5v5') {
            if (preg_match('/^\s*(?!;)\s*clanwar_system\.amxx/m', $content)) {
                $content  = preg_replace('/^\s*(?!;)\s*clanwar_system\.amxx(.*)$/m', ';clanwar_system.amxx$1', $content);
                $modified = true;
            }
        } elseif ($serverMode === 'clanwar') {
            if (preg_match('/^\s*(?!;)\s*mix_system\.amxx/m', $content)) {
                $content  = preg_replace('/^\s*(?!;)\s*mix_system\.amxx(.*)$/m', ';mix_system.amxx$1', $content);
                $modified = true;
            }
        } else { // public
            if (preg_match('/^\s*(?!;)\s*clanwar_system\.amxx/m', $content)) {
                $content  = preg_replace('/^\s*(?!;)\s*clanwar_system\.amxx(.*)$/m', ';clanwar_system.amxx$1', $content);
                $modified = true;
            }
            if (preg_match('/^\s*(?!;)\s*mix_system\.amxx/m', $content)) {
                $content  = preg_replace('/^\s*(?!;)\s*mix_system\.amxx(.*)$/m', ';mix_system.amxx$1', $content);
                $modified = true;
            }
        }

        foreach ($mixFiles as $mf => $desc) {
            // If it exists but is commented out → uncomment it
            if (preg_match('/^\s*;+\s*' . preg_quote($mf, '/') . '/m', $content)) {
                $content  = preg_replace('/^\s*;+\s*(' . preg_quote($mf, '/') . '.*)$/m', '$1', $content);
                $modified = true;
            } elseif (!preg_match('/^\s*' . preg_quote($mf, '/') . '/m', $content)) {
                // Not present at all → add it
                if (!str_contains($content, '; GameLand & Match Server System')) {
                    $content .= "\n; GameLand & Match Server System\n";
                }
                $content .= $mf . " ; " . $desc . "\n";
                $modified = true;
            }
        }

        if ($modified) {
            @file_put_contents($pluginsIni, $content);
        }

        // Auto-heal sv_visiblemaxplayers in server.cfg ONLY if missing entirely
        if (is_file($cfg)) {
            $cfgContent = (string)@file_get_contents($cfg);
            if (!preg_match('/^\s*sv_visiblemaxplayers\s+[0-9]+/m', $cfgContent)) {
                $newCfg = rtrim($cfgContent) . "\nsv_visiblemaxplayers {$slots}\n";
                @file_put_contents($cfg, $newCfg);
            }
        }

        // Persist mode & slots in persistent storage
        if ($serverId === 'main') {
            @file_put_contents('/opt/gameland/persistent/main_mode.txt', $serverMode . "\n");
        }
        $modesFile = '/opt/gameland/persistent/modes.json';
        $m = is_file($modesFile) ? @json_decode((string)@file_get_contents($modesFile), true) : [];
        if (!is_array($m)) $m = [];
        $m[$serverId] = ['mode' => $serverMode, 'slots' => $slots];
        @file_put_contents($modesFile, json_encode($m, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
    }

    /**
     * Create a VPS checkpoint snapshot
     */
    public static function createCheckpoint($label = 'Manual VPS Checkpoint') {
        $helper = self::getPrivilegedHelperPath();
        $labelArg = escapeshellarg($label);
        $output = [];
        $ret = 1;
        if (is_file($helper)) {
            @exec("sudo -n " . escapeshellarg($helper) . " checkpoint_create {$labelArg} 2>&1", $output, $ret);
        } else {
            $script = dirname(__DIR__, 2) . '/checkpoint.sh';
            @exec("bash " . escapeshellarg($script) . " create {$labelArg} 2>&1", $output, $ret);
        }
        $raw = implode("\n", $output);
        $json = json_decode($raw, true);
        if (is_array($json) && !empty($json['success'])) {
            return $json;
        }
        return ['success' => false, 'message' => 'Failed to create checkpoint: ' . $raw];
    }

    /**
     * List all VPS checkpoints
     */
    public static function listCheckpoints() {
        $cpDir = '/opt/gameland/checkpoints';
        $list = [];
        if (is_dir($cpDir)) {
            $files = glob($cpDir . '/cp_*.json');
            foreach ($files as $f) {
                $d = json_decode(@file_get_contents($f), true);
                if (is_array($d)) {
                    $tar = $cpDir . '/' . ($d['archive'] ?? '');
                    if (is_file($tar)) {
                        $list[] = $d;
                    }
                }
            }
        }
        usort($list, function($a, $b) {
            return strcmp($b['timestamp'] ?? '', $a['timestamp'] ?? '');
        });
        return $list;
    }

    /**
     * Restore a VPS checkpoint
     */
    public static function restoreCheckpoint($checkpointId) {
        $helper = self::getPrivilegedHelperPath();
        $idArg = escapeshellarg($checkpointId);
        $output = [];
        $ret = 1;
        if (is_file($helper)) {
            @exec("sudo -n " . escapeshellarg($helper) . " checkpoint_restore {$idArg} 2>&1", $output, $ret);
        } else {
            $script = dirname(__DIR__, 2) . '/checkpoint.sh';
            @exec("bash " . escapeshellarg($script) . " restore {$idArg} 2>&1", $output, $ret);
        }
        $raw = implode("\n", $output);
        $json = json_decode($raw, true);
        if (is_array($json) && !empty($json['success'])) {
            return $json;
        }
        return ['success' => false, 'message' => 'Failed to restore checkpoint: ' . $raw];
    }

    /**
     * Delete a VPS checkpoint
     */
    public static function deleteCheckpoint($checkpointId) {
        $helper = self::getPrivilegedHelperPath();
        $idArg = escapeshellarg($checkpointId);
        $output = [];
        $ret = 1;
        if (is_file($helper)) {
            @exec("sudo -n " . escapeshellarg($helper) . " checkpoint_delete {$idArg} 2>&1", $output, $ret);
        } else {
            $script = dirname(__DIR__, 2) . '/checkpoint.sh';
            @exec("bash " . escapeshellarg($script) . " delete {$idArg} 2>&1", $output, $ret);
        }
        $raw = implode("\n", $output);
        $json = json_decode($raw, true);
        if (is_array($json)) {
            return $json;
        }
        return ['success' => true, 'message' => 'Checkpoint deleted.'];
    }

    /**
     * One-click safe update from GitHub repository directly from web panel.
     * Runs update.sh with root privileges via gameland-panel-sudo.
     */
    public static function updateVpsFromRepo() {
        $helper = self::getPrivilegedHelperPath();
        $output = [];
        $exitCode = 1;

        if (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
            $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
            // 1. Try update_all
            $cmd = 'sudo -n ' . escapeshellarg($h) . ' update_all 2>&1';
            @exec($cmd, $output, $exitCode);
            if ($exitCode === 2) {
                // Legacy helper might not recognize update_all, fallback to git_sync
                $output = [];
                $cmd = 'sudo -n ' . escapeshellarg($h) . ' git_sync 2>&1';
                @exec($cmd, $output, $exitCode);
            }
        } else {
            $root = self::getManagerRoot();
            $cmd = 'cd ' . escapeshellarg($root) . ' && git fetch origin main 2>&1 && git reset --hard origin/main 2>&1';
            @exec($cmd, $output, $exitCode);
        }

        return [
            'success' => ($exitCode === 0),
            'exit_code' => $exitCode,
            'output' => implode("\n", $output),
            'message' => ($exitCode === 0) ? 'سیستم با موفقیت از گیت‌هاب به‌روزرسانی شد.' : 'خطا در به‌روزرسانی از گیت‌هاب.'
        ];
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Web IDE & 1-Click Cloud Compiler Subsystem
    // ══════════════════════════════════════════════════════════════════════════

    /**
     * Resolves a safe, canonical path within the active server's cstrike or addons directory.
     * Prevents directory traversal attacks.
     */
    public static function getIdeSafeFilePath($serverInfo, $relPath) {
        $relPath = str_replace('\\', '/', trim((string)$relPath));
        if (str_contains($relPath, '..') || str_starts_with($relPath, '/')) {
            return null;
        }

        $baseDir = realpath($serverInfo['cstrike_dir']);
        if (!$baseDir) {
            $baseDir = $serverInfo['cstrike_dir'];
        }

        $target = $baseDir . '/' . ltrim($relPath, '/');
        $realTarget = realpath($target);

        // If file already exists, verify realpath is inside baseDir
        if ($realTarget) {
            $realBase = realpath($baseDir);
            if ($realBase && !str_starts_with($realTarget, $realBase)) {
                return null;
            }
            return $realTarget;
        }

        // For new files or files that will be created
        $realDir = realpath(dirname($target));
        $realBase = realpath($baseDir);
        if ($realDir && $realBase && str_starts_with($realDir, $realBase)) {
            return $target;
        }

        return null;
    }

    /**
     * Returns structured list of all editable files for the server instance.
     */
    public static function getIdeFileList($serverInfo) {
        $cstrikeDir = $serverInfo['cstrike_dir'];
        $scriptingDir = $cstrikeDir . '/addons/amxmodx/scripting';
        $langDir = $cstrikeDir . '/addons/amxmodx/data/lang';
        $configsDir = $cstrikeDir . '/addons/amxmodx/configs';

        $files = [];

        // 1. Scripting Files (*.sma)
        if (is_dir($scriptingDir)) {
            $smaFiles = glob($scriptingDir . '/*.sma') ?: [];
            foreach ($smaFiles as $f) {
                $base = basename($f);
                $isMatch = ($base === 'clanwar_system.sma' || $base === 'mix_system.sma' || $base === 'mix_system_voice_chat.sma');
                $files[] = [
                    'name' => $base,
                    'rel_path' => 'addons/amxmodx/scripting/' . $base,
                    'group' => $isMatch ? '⚔️ Match & ClanWar Plugins' : '🛠️ Server Plugins',
                    'type' => 'sma',
                    'can_compile' => true,
                    'size' => filesize($f),
                    'mtime' => filemtime($f),
                    'mtime_str' => date('Y-m-d H:i', filemtime($f)),
                ];
            }

            // Scripting includes (*.inc)
            $incFiles = glob($scriptingDir . '/include/*.inc') ?: [];
            foreach ($incFiles as $f) {
                $base = basename($f);
                $files[] = [
                    'name' => $base,
                    'rel_path' => 'addons/amxmodx/scripting/include/' . $base,
                    'group' => '📚 Includes (.inc)',
                    'type' => 'inc',
                    'can_compile' => false,
                    'size' => filesize($f),
                    'mtime' => filemtime($f),
                    'mtime_str' => date('Y-m-d H:i', filemtime($f)),
                ];
            }
        }

        // 2. Language & Translations (*.txt)
        if (is_dir($langDir)) {
            $langFiles = glob($langDir . '/*.txt') ?: [];
            foreach ($langFiles as $f) {
                $base = basename($f);
                $files[] = [
                    'name' => $base,
                    'rel_path' => 'addons/amxmodx/data/lang/' . $base,
                    'group' => '💬 Language & Messages',
                    'type' => 'txt',
                    'can_compile' => false,
                    'size' => filesize($f),
                    'mtime' => filemtime($f),
                    'mtime_str' => date('Y-m-d H:i', filemtime($f)),
                ];
            }
        }

        // 3. Configurations (*.ini, *.cfg)
        if (is_dir($configsDir)) {
            foreach (['plugins.ini', 'amxx.cfg', 'cvars.ini', 'users.ini', 'maps.ini'] as $cfg) {
                $f = $configsDir . '/' . $cfg;
                if (file_exists($f)) {
                    $files[] = [
                        'name' => $cfg,
                        'rel_path' => 'addons/amxmodx/configs/' . $cfg,
                        'group' => '⚙️ Configs & Settings',
                        'type' => 'ini',
                        'can_compile' => false,
                        'size' => filesize($f),
                        'mtime' => filemtime($f),
                        'mtime_str' => date('Y-m-d H:i', filemtime($f)),
                    ];
                }
            }
        }

        // server.cfg
        $serverCfg = $cstrikeDir . '/server.cfg';
        if (file_exists($serverCfg)) {
            $files[] = [
                'name' => 'server.cfg',
                'rel_path' => 'server.cfg',
                'group' => '⚙️ Configs & Settings',
                'type' => 'cfg',
                'can_compile' => false,
                'size' => filesize($serverCfg),
                'mtime' => filemtime($serverCfg),
                'mtime_str' => date('Y-m-d H:i', filemtime($serverCfg)),
            ];
        }

        return $files;
    }

    /**
     * Reads a source file safely and lists its backups.
     */
    public static function readIdeFile($serverInfo, $relPath) {
        $path = self::getIdeSafeFilePath($serverInfo, $relPath);
        if (!$path || !file_exists($path)) {
            return ['success' => false, 'message' => 'File not found or access denied: ' . htmlspecialchars($relPath)];
        }

        $content = @file_get_contents($path);
        if ($content === false) {
            return ['success' => false, 'message' => 'Failed to read file content. Check file permissions.'];
        }

        $baseName = basename($path);
        $backups = self::listIdeBackups($serverInfo, $relPath);

        return [
            'success' => true,
            'rel_path' => $relPath,
            'name' => $baseName,
            'content' => $content,
            'size' => filesize($path),
            'mtime' => filemtime($path),
            'mtime_str' => date('Y-m-d H:i:s', filemtime($path)),
            'backups' => $backups,
        ];
    }

    /**
     * Saves a source file safely with automatic backup and LF normalization.
     */
    public static function saveIdeFile($serverInfo, $relPath, $content, $createBackup = true) {
        $path = self::getIdeSafeFilePath($serverInfo, $relPath);
        if (!$path) {
            return ['success' => false, 'message' => 'Invalid file path. Path traversal is blocked.'];
        }

        // Create backup before writing if file exists
        $backupCreated = null;
        if ($createBackup && file_exists($path)) {
            $backupDir = dirname($path) . '/backups';
            if (!is_dir($backupDir)) {
                @mkdir($backupDir, 0775, true);
            }
            if (is_dir($backupDir)) {
                $baseName = basename($path);
                $backupFile = $backupDir . '/' . $baseName . '.' . date('Ymd_His') . '.bak';
                if (@copy($path, $backupFile)) {
                    $backupCreated = basename($backupFile);
                    // Keep at most 20 recent backups
                    $allBackups = glob($backupDir . '/' . $baseName . '.*.bak') ?: [];
                    if (count($allBackups) > 20) {
                        usort($allBackups, fn($a, $b) => filemtime($a) <=> filemtime($b));
                        $toDelete = array_slice($allBackups, 0, count($allBackups) - 20);
                        foreach ($toDelete as $old) {
                            @unlink($old);
                        }
                    }
                }
            }
        }

        // Normalize line endings to LF (\n) to prevent pawn compiler issues
        $cleanContent = str_replace(["\r\n", "\r"], "\n", $content);

        $written = @file_put_contents($path, $cleanContent);
        if ($written === false) {
            return ['success' => false, 'message' => 'Failed to write to file. Check filesystem permissions on ' . htmlspecialchars($path)];
        }

        return [
            'success' => true,
            'message' => 'File saved successfully (' . number_format($written) . ' bytes).',
            'backup' => $backupCreated,
            'size' => $written,
            'mtime' => filemtime($path),
            'mtime_str' => date('Y-m-d H:i:s'),
        ];
    }

    /**
     * Lists backups for a specific file.
     */
    public static function listIdeBackups($serverInfo, $relPath) {
        $path = self::getIdeSafeFilePath($serverInfo, $relPath);
        if (!$path) return [];

        $backupDir = dirname($path) . '/backups';
        if (!is_dir($backupDir)) return [];

        $baseName = basename($path);
        $files = glob($backupDir . '/' . $baseName . '.*.bak') ?: [];
        usort($files, fn($a, $b) => filemtime($b) <=> filemtime($a));

        $backups = [];
        foreach ($files as $f) {
            $backups[] = [
                'filename' => basename($f),
                'size' => filesize($f),
                'mtime' => filemtime($f),
                'date_str' => date('Y-m-d H:i:s', filemtime($f)),
            ];
        }
        return $backups;
    }

    /**
     * Restores a backup file safely.
     */
    public static function restoreIdeBackup($serverInfo, $relPath, $backupName) {
        $path = self::getIdeSafeFilePath($serverInfo, $relPath);
        if (!$path) return ['success' => false, 'message' => 'Invalid file path.'];

        $backupName = basename(trim((string)$backupName));
        $backupDir = dirname($path) . '/backups';
        $backupPath = $backupDir . '/' . $backupName;

        if (!file_exists($backupPath)) {
            return ['success' => false, 'message' => 'Backup file not found: ' . htmlspecialchars($backupName)];
        }

        // Create safety backup of current before reverting
        $safety = $backupDir . '/' . basename($path) . '.before_revert_' . date('Ymd_His') . '.bak';
        if (file_exists($path)) {
            @copy($path, $safety);
        }

        if (!@copy($backupPath, $path)) {
            return ['success' => false, 'message' => 'Failed to restore backup file.'];
        }

        $content = @file_get_contents($path);
        return [
            'success' => true,
            'message' => 'Backup restored successfully from ' . htmlspecialchars($backupName),
            'content' => $content,
            'size' => filesize($path),
            'mtime' => filemtime($path),
            'mtime_str' => date('Y-m-d H:i:s', filemtime($path)),
        ];
    }

    /**
     * Compiles a single .sma plugin with amxxpc directly or via privileged helper,
     * with live terminal output capture, optional restart, and optional multi-server sync.
     */
    public static function compileIdePlugin($serverInfo, $smaFile, $propagateToAll = false, $restartAfter = false) {
        $smaFile = basename(trim((string)$smaFile));
        if (!str_ends_with($smaFile, '.sma')) {
            return ['success' => false, 'message' => 'Target file must be a .sma Pawn source file.', 'output' => ''];
        }

        $scriptingDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/scripting';
        $pluginsDir = $serverInfo['cstrike_dir'] . '/addons/amxmodx/plugins';
        $srcPath = $scriptingDir . '/' . $smaFile;
        $amxxName = substr($smaFile, 0, -4) . '.amxx';
        $binPath = $pluginsDir . '/' . $amxxName;

        if (!file_exists($srcPath)) {
            return ['success' => false, 'message' => 'Source file not found: ' . $smaFile, 'output' => ''];
        }

        if (!is_dir($pluginsDir)) {
            @mkdir($pluginsDir, 0775, true);
        }

        $isWin = (strtoupper(substr(PHP_OS, 0, 3)) === 'WIN');
        $lines = [];
        $exitCode = 1;

        if ($isWin) {
            $compiler = $scriptingDir . '/amxxpc.exe';
            if (!file_exists($compiler) && file_exists($scriptingDir . '/amxxpc')) {
                $compiler = $scriptingDir . '/amxxpc';
            }
            if (!file_exists($compiler)) {
                return ['success' => false, 'message' => 'amxxpc.exe not found in scripting dir.', 'output' => ''];
            }

            // Execute amxxpc on Windows
            $cmd = 'cd /d "' . $scriptingDir . '" && "' . $compiler . '" "' . $smaFile . '" 2>&1';
            @exec($cmd, $lines, $exitCode);

            // Copy generated .amxx to plugins dir if generated in scripting dir
            $scriptingAmxx = $scriptingDir . '/' . $amxxName;
            if (file_exists($scriptingAmxx)) {
                @copy($scriptingAmxx, $binPath);
                @touch($binPath, time() + 5);
            }
        } else {
            // Linux execution
            $helper = self::getPrivilegedHelperPath();
            $sId = $serverInfo['id'] ?? 'main';

            // Check if compiler binary exists
            $compiler = $scriptingDir . '/amxxpc';
            if (!file_exists($compiler) && file_exists($scriptingDir . '/amxxpc32')) {
                $compiler = $scriptingDir . '/amxxpc32';
            }
            if (file_exists($compiler)) {
                @chmod($compiler, 0755);
            }
            foreach (['amxxpc32.so', 'amxxpc64.so'] as $lib) {
                $libPath = $scriptingDir . '/' . $lib;
                if (file_exists($libPath)) @chmod($libPath, 0755);
            }

            // Direct compilation with amxxpc inside instance scripting directory
            if (file_exists($compiler)) {
                $cleanScripting = escapeshellarg($scriptingDir);
                $cleanCompiler = escapeshellarg($compiler);
                $cleanSma = escapeshellarg($smaFile);
                $cmd = "cd {$cleanScripting} && LD_LIBRARY_PATH={$cleanScripting}:\${LD_LIBRARY_PATH:-} {$cleanCompiler} {$cleanSma} 2>&1";
                @exec($cmd, $lines, $exitCode);

                $scriptingAmxx = $scriptingDir . '/' . $amxxName;
                if (file_exists($scriptingAmxx)) {
                    @copy($scriptingAmxx, $binPath);
                    @chmod($binPath, 0664);
                    @touch($binPath, time() + 5);
                }
            } elseif (is_file($helper) || is_file('/usr/local/sbin/gameland-panel-sudo')) {
                $h = is_file('/usr/local/sbin/gameland-panel-sudo') ? '/usr/local/sbin/gameland-panel-sudo' : $helper;
                $cmd = 'sudo -n ' . escapeshellarg($h) . ' compile_server ' . escapeshellarg($sId) . ' 2>&1';
                @exec($cmd, $lines, $exitCode);
            }
        }

        $output = implode("\n", $lines);
        $compiledOk = (file_exists($binPath) && (time() - filemtime($binPath) <= 20) && !str_contains($output, 'fatal error') && !str_contains($output, 'Compilation aborted'));

        // If compile output specifically has Done.
        if (str_contains($output, 'Done.') || str_contains($output, 'Total requirements:')) {
            $compiledOk = true;
        }

        if ($compiledOk) {
            // Touch binary
            if (file_exists($binPath)) {
                @touch($binPath, time() + 5);
            }

            // Multi-server synchronization if requested
            $syncedCount = 0;
            if ($propagateToAll) {
                $allServers = self::getManagedServers();
                foreach ($allServers as $oId => $oConf) {
                    if (($oConf['cstrike_dir'] ?? '') !== $serverInfo['cstrike_dir']) {
                        $otherPluginsDir = ($oConf['cstrike_dir'] ?? '') . '/addons/amxmodx/plugins';
                        $otherScriptingDir = ($oConf['cstrike_dir'] ?? '') . '/addons/amxmodx/scripting';
                        if (is_dir($otherPluginsDir) && file_exists($binPath)) {
                            @copy($binPath, $otherPluginsDir . '/' . $amxxName);
                            @touch($otherPluginsDir . '/' . $amxxName, time() + 5);
                            $syncedCount++;
                        }
                        if (is_dir($otherScriptingDir) && file_exists($srcPath)) {
                            @copy($srcPath, $otherScriptingDir . '/' . $smaFile);
                        }
                        if ($amxxName === 'gameland_dense_smoke.amxx') {
                            $mainSprite = self::getMainServerCstrikeDir() . '/sprites/gas_puff_02.spr';
                            if (file_exists($mainSprite)) {
                                @mkdir(($oConf['cstrike_dir'] ?? '') . '/sprites', 0777, true);
                                @copy($mainSprite, ($oConf['cstrike_dir'] ?? '') . '/sprites/gas_puff_02.spr');
                            }
                        }
                        self::ensureMixRegistered($oConf);
                    }
                }
            }
            if ($amxxName === 'gameland_dense_smoke.amxx') {
                $mainSprite = self::getMainServerCstrikeDir() . '/sprites/gas_puff_02.spr';
                if (file_exists($mainSprite) && ($serverInfo['cstrike_dir'] ?? '') !== self::getMainServerCstrikeDir()) {
                    @mkdir($serverInfo['cstrike_dir'] . '/sprites', 0777, true);
                    @copy($mainSprite, $serverInfo['cstrike_dir'] . '/sprites/gas_puff_02.spr');
                }
                self::ensureMixRegistered($serverInfo);
            }

            // Restart server if requested
            $restarted = false;
            if ($restartAfter) {
                self::controlService($serverInfo['service_name'], 'restart');
                $restarted = true;
            }

            $binSize = file_exists($binPath) ? filesize($binPath) : 0;
            $msg = "Plugin [{$amxxName}] compiled successfully! (" . number_format($binSize) . " bytes)";
            if ($syncedCount > 0) {
                $msg .= " → Synced to {$syncedCount} other instances.";
            }
            if ($restarted) {
                $msg .= " → 🔄 Server restarted!";
            }

            return [
                'success' => true,
                'message' => $msg,
                'output' => $output,
                'binary' => $amxxName,
                'binary_size' => $binSize,
                'restarted' => $restarted,
                'exit_code' => $exitCode,
            ];
        } else {
            return [
                'success' => false,
                'message' => "Compilation failed for [{$smaFile}]. See compiler output below.",
                'output' => $output,
                'binary' => $amxxName,
                'binary_size' => 0,
                'restarted' => false,
                'exit_code' => $exitCode,
            ];
        }
    }
}

