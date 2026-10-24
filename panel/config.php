<?php
/**
 * GameLand Web Panel Configuration
 * Supports Multi-Server instances
 */

// PHP 7.x compatibility polyfills
if (!function_exists('str_starts_with')) {
    function str_starts_with(?string $haystack, ?string $needle): bool {
        return (string)$needle !== '' && strncmp((string)$haystack, (string)$needle, strlen((string)$needle)) === 0;
    }
}
if (!function_exists('str_ends_with')) {
    function str_ends_with(?string $haystack, ?string $needle): bool {
        return (string)$needle === '' || $needle === substr((string)$haystack, -strlen((string)$needle));
    }
}
if (!function_exists('str_contains')) {
    function str_contains(?string $haystack, ?string $needle): bool {
        return (string)$needle === '' || strpos((string)$haystack, (string)$needle) !== false;
    }
}

// Use dedicated panel session folder to prevent Linux /var/lib/php permission drops
$panelSessionPath = __DIR__ . '/sessions';
if (!is_dir($panelSessionPath)) {
    @mkdir($panelSessionPath, 0775, true);
}
if (is_dir($panelSessionPath) && is_writable($panelSessionPath)) {
    session_save_path($panelSessionPath);
}
@ini_set('session.cookie_httponly', '1');
@ini_set('session.use_only_cookies', '1');
@ini_set('session.cookie_secure', '0');
@ini_set('session.cookie_samesite', 'Lax');

if (session_status() === PHP_SESSION_NONE) {
    session_start();
}

// -------------------------------------------------------------
// Web Panel Authentication
// Username & Password
// You can set plain text password or bcrypt hash here
// -------------------------------------------------------------
define('PANEL_USER', 'admin');
define('PANEL_PASS', 'changeme123'); // Change this to your preferred password!

// Session security timeout (7 days keep-alive)
define('SESSION_TIMEOUT', 604800);

// -------------------------------------------------------------
// GitHub Integration (for Match Server plugin auto-deploy)
// Set your GitHub Personal Access Token here to enable:
//   - Triggering GitHub Actions builds remotely
//   - Downloading pre-built .amxx artifacts (recommended!)
//   - No need for local compilation
// Create token at: https://github.com/settings/tokens
// Required scope: repo (or just actions:read for public repos)
// Leave empty to use local amxxpc compiler instead.
// -------------------------------------------------------------
define('GITHUB_TOKEN', '');  // e.g. 'ghp_xxxxxxxxxxxx'
define('GITHUB_REPO', 'GAMELAND-PROJECT/MixSystem_SV_PL');
define('GITHUB_BRANCH', 'main');

// -------------------------------------------------------------
// Multi-Server Instances List
// The main server stays static for backward compatibility. Extra servers
// created by SVGL are loaded from instances/servers.json automatically.
// -------------------------------------------------------------
$detectedServerDir = is_dir('/opt/gameland/server') ? '/opt/gameland/server' : dirname(__DIR__);
$detectedPublicIp = $_SERVER['SERVER_ADDR'] ?? '127.0.0.1';

$mainMode = 'mix5v5';
if (is_file('/opt/gameland/persistent/main_mode.txt')) {
    $m = trim((string)@file_get_contents('/opt/gameland/persistent/main_mode.txt'));
    if (in_array($m, ['clanwar', 'mix5v5', 'public'], true)) $mainMode = $m;
} elseif (is_file($detectedServerDir . '/instances/main_mode.txt')) {
    $m = trim((string)@file_get_contents($detectedServerDir . '/instances/main_mode.txt'));
    if (in_array($m, ['clanwar', 'mix5v5', 'public'], true)) $mainMode = $m;
} else {
    foreach (['/opt/gameland/persistent/modes.json', $detectedServerDir . '/instances/modes.json'] as $mjPath) {
        if (is_file($mjPath)) {
            $mj = @json_decode((string)@file_get_contents($mjPath), true);
            if (!empty($mj['main']['mode']) && in_array($mj['main']['mode'], ['clanwar', 'mix5v5', 'public'], true)) {
                $mainMode = $mj['main']['mode'];
                break;
            }
        }
    }
    $mainPini = $detectedServerDir . '/cstrike/addons/amxmodx/configs/plugins.ini';
    if (is_file($mainPini)) {
        $rawPini = (string)@file_get_contents($mainPini);
        if (preg_match('/^[ \t]*(?!;)[ \t]*mix_system\.amxx/m', $rawPini)) {
            $mainMode = 'mix5v5';
        } elseif (preg_match('/^[ \t]*(?!;)[ \t]*clanwar_system\.amxx/m', $rawPini)) {
            $mainMode = 'clanwar';
        }
    }
}

$mainCfg = $detectedServerDir . '/cstrike/server.cfg';
$mainSlots = 0;
if (is_file($mainCfg) && preg_match('/^\s*sv_visiblemaxplayers\s+([0-9]+)/m', (string)@file_get_contents($mainCfg), $mSlots)) {
    $mainSlots = (int)$mSlots[1];
}
if ($mainSlots <= 0) {
    $mainSlots = ($mainMode === 'clanwar') ? 10 : (($mainMode === 'mix5v5') ? 18 : 24);
}

$SERVERS = [
    'main' => [
        'id'            => 'main',
        'name'          => 'GameLand CS 1.6 #1 (Competitive)',
        'hostname'      => 'GameLand CS 1.6 #1 (Competitive)',
        'ip'            => $detectedPublicIp,
        'port'          => 27015,
        'rcon_password' => 'GameLand@Rcon2026',
        'service_name'  => 'gameland.service',
        'server_dir'    => $detectedServerDir,
        'cstrike_dir'   => $detectedServerDir . '/cstrike',
        'users_ini'     => $detectedServerDir . '/cstrike/addons/amxmodx/configs/users.ini',
        'maps_ini'      => $detectedServerDir . '/cstrike/addons/amxmodx/configs/maps.ini',
        'log_file'      => $detectedServerDir . '/logs/server.log',
        'mode'          => $mainMode,
        'slots'         => $mainSlots,
    ],
];

function gameland_normalize_server(array $server, string $fallbackIp): array {
    $id = preg_replace('/[^a-zA-Z0-9_-]/', '', (string)($server['id'] ?? ''));
    $serverDir = rtrim((string)($server['server_dir'] ?? ''), '/');
    if ($serverDir === '' && $id !== '' && $id !== 'main') {
        if (is_dir('/opt/gameland/instances/' . $id)) {
            $serverDir = '/opt/gameland/instances/' . $id;
        } elseif (is_dir(dirname(__DIR__) . '/instances/' . $id)) {
            $serverDir = dirname(__DIR__) . '/instances/' . $id;
        } else {
            $serverDir = '/opt/gameland/instances/' . $id;
        }
    }
    $name = (string)($server['name'] ?? ('GameLand ' . $id));
    $hostname = (string)($server['hostname'] ?? $name);

    $mode = (string)($server['mode'] ?? '');
    $slots = (int)($server['slots'] ?? 0);
    if (is_file('/opt/gameland/persistent/modes.json')) {
        $modesJson = @json_decode((string)file_get_contents('/opt/gameland/persistent/modes.json'), true);
        if (isset($modesJson[$id]['mode'])) {
            $mode = (string)$modesJson[$id]['mode'];
            if ($slots <= 0) $slots = (int)($modesJson[$id]['slots'] ?? 0);
        }
    }
    if ($mode === '' || !in_array($mode, ['clanwar', 'mix5v5', 'public'], true)) {
        $instPini = $serverDir . '/cstrike/addons/amxmodx/configs/plugins.ini';
        if (is_file($instPini)) {
            $rawPini = (string)@file_get_contents($instPini);
            if (preg_match('/^[ \t]*mix_system\.amxx/m', $rawPini)) {
                $mode = 'mix5v5';
            } elseif (preg_match('/^[ \t]*clanwar_system\.amxx/m', $rawPini)) {
                $mode = 'clanwar';
            } else {
                $mode = 'public';
            }
        } else {
            $mode = 'clanwar';
        }
    }
    $instCfg = $serverDir . '/cstrike/server.cfg';
    if ($slots <= 0 && is_file($instCfg) && preg_match('/^\s*sv_visiblemaxplayers\s+([0-9]+)/m', (string)@file_get_contents($instCfg), $mSlots)) {
        $slots = (int)$mSlots[1];
    }
    if ($slots <= 0) {
        $slots = ($mode === 'clanwar') ? 10 : (($mode === 'mix5v5') ? 18 : 24);
    }

    return [
        'id'            => $id,
        'name'          => $name,
        'hostname'      => $hostname,
        'ip'            => (string)($server['ip'] ?? $fallbackIp),
        'port'          => (int)($server['port'] ?? 27015),
        'rcon_password' => (string)($server['rcon_password'] ?? 'GameLand@Rcon2026'),
        'service_name'  => (string)($server['service_name'] ?? ($id === 'main' ? 'gameland.service' : 'gameland@' . $id . '.service')),
        'server_dir'    => $serverDir,
        'cstrike_dir'   => $serverDir . '/cstrike',
        'users_ini'     => $serverDir . '/cstrike/addons/amxmodx/configs/users.ini',
        'maps_ini'      => $serverDir . '/cstrike/addons/amxmodx/configs/maps.ini',
        'log_file'      => $serverDir . '/logs/server_' . $id . '.log',
        'mode'          => $mode,
        'slots'         => $slots,
    ];
}

$instancesRegistry = dirname(__DIR__) . '/instances/servers.json';
if ((!is_file($instancesRegistry) || filesize($instancesRegistry) < 20) && is_file('/opt/gameland/persistent/servers.json')) {
    $instancesRegistry = '/opt/gameland/persistent/servers.json';
}
if (is_file($instancesRegistry)) {
    $registry = json_decode((string)file_get_contents($instancesRegistry), true);
    foreach (($registry['servers'] ?? []) as $server) {
        $normalized = gameland_normalize_server($server, $detectedPublicIp);
        if ($normalized['id'] !== '' && $normalized['server_dir'] !== '') {
            $SERVERS[$normalized['id']] = $normalized;
        }
    }
}

// Helper to get selected active server
function get_active_server() {
    global $SERVERS;
    if (isset($_SESSION['active_server_id']) && isset($SERVERS[$_SESSION['active_server_id']])) {
        return $SERVERS[$_SESSION['active_server_id']];
    }
    // Default to the first server in the list
    $firstKey = array_key_first($SERVERS);
    return $SERVERS[$firstKey];
}
