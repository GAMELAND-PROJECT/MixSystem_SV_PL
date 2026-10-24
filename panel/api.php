<?php
header('Content-Type: application/json');
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/includes/Auth.php';
require_once __DIR__ . '/includes/Rcon.class.php';
require_once __DIR__ . '/includes/ServerCmd.php';

// Verify session & authentication
if (!Auth::isLoggedIn()) {
    echo json_encode(['success' => false, 'message' => 'Unauthorized']);
    exit;
}

// Verify CSRF
$submittedCsrf = $_POST['csrf_token'] ?? $_SERVER['HTTP_X_CSRF_TOKEN'] ?? $_GET['csrf_token'] ?? '';
if (!Auth::verify_csrf($submittedCsrf)) {
    echo json_encode(['success' => false, 'message' => 'Invalid CSRF token']);
    exit;
}

$action = $_POST['action'] ?? '';
$activeServer = get_active_server();

switch ($action) {

    case 'checkpoint_create':
        $label = trim($_POST['label'] ?? 'Manual VPS Checkpoint');
        echo json_encode(ServerCmd::createCheckpoint($label));
        break;

    case 'checkpoint_list':
        echo json_encode(['success' => true, 'checkpoints' => ServerCmd::listCheckpoints()]);
        break;

    case 'checkpoint_restore':
        $cpId = trim($_POST['checkpoint_id'] ?? 'latest');
        echo json_encode(ServerCmd::restoreCheckpoint($cpId));
        break;

    case 'checkpoint_delete':
        $cpId = trim($_POST['checkpoint_id'] ?? '');
        echo json_encode(ServerCmd::deleteCheckpoint($cpId));
        break;

    case 'list_servers':
        global $SERVERS;
        echo json_encode(['success' => true, 'servers' => ServerCmd::getServerList($SERVERS)]);
        break;

    case 'get_bans':
        echo json_encode([
            'success' => true,
            'bans' => ServerCmd::getBanList($activeServer),
        ]);
        break;

    case 'remove_ban':
        $res = ServerCmd::removeBan(
            $activeServer,
            $_POST['ban_type'] ?? '',
            $_POST['ban_target'] ?? ''
        );
        echo json_encode($res);
        break;

    case 'remove_avg_bans':
        echo json_encode(ServerCmd::removeAvgBans($activeServer));
        break;

    case 'switch_server_mode':
        $serverId = $_POST['server_id'] ?? ($activeServer['id'] ?? 'main');
        $targetMode = $_POST['target_mode'] ?? $_POST['mode'] ?? 'clanwar';
        global $SERVERS;
        $targetServer = $SERVERS[$serverId] ?? $activeServer;
        $res = ServerCmd::switchServerMode($targetServer, $targetMode);
        echo json_encode($res);
        break;

    case 'set_afk_guard':
        $serverId = $_POST['server_id'] ?? ($activeServer['id'] ?? 'main');
        $mode = (int)($_POST['afk_guard'] ?? $_POST['mode'] ?? 1);
        global $SERVERS;
        $targetServer = $SERVERS[$serverId] ?? $activeServer;
        $res = ServerCmd::setServerAfkGuard($targetServer, $mode);
        echo json_encode($res);
        break;

    case 'restart_all_servers':
        $res = ServerCmd::restartAllServersStaggered();
        echo json_encode($res);
        break;

    case 'start_all_servers':
        $res = ServerCmd::startAllServersStaggered();
        echo json_encode($res);
        break;

    case 'stop_all_servers':
        $res = ServerCmd::stopAllServers();
        echo json_encode($res);
        break;

    case 'update_vps':
        $res = ServerCmd::updateVpsFromRepo();
        echo json_encode($res);
        break;

    case 'get_servers_list':
        global $SERVERS;
        $list = ServerCmd::getServerList($SERVERS);
        echo json_encode([
            'success' => true,
            'servers' => $list
        ]);
        break;

    case 'create_server':
        $id = $_POST['server_id'] ?? '';
        $port = $_POST['port'] ?? '';
        $name = $_POST['name'] ?? '';
        $slots = $_POST['slots'] ?? 10;
        $hostname = $_POST['hostname'] ?? $name;
        $mode = $_POST['mode'] ?? 'clanwar';
        $res = ServerCmd::createServerInstance($id, $port, $name, $slots, $hostname, $mode);
        echo json_encode($res);
        break;

    case 'remove_server':
        $id = $_POST['server_id'] ?? '';
        $purge = ($_POST['purge'] ?? '0') === '1';
        $res = ServerCmd::removeServerInstance($id, $purge);
        if (($res['success'] ?? false) && ($_SESSION['active_server_id'] ?? '') === $id) {
            unset($_SESSION['active_server_id']);
        }
        echo json_encode($res);
        break;

    case 'update_server':
        $id = $_POST['server_id'] ?? '';
        $data = [
            'name' => $_POST['name'] ?? '',
            'hostname' => $_POST['hostname'] ?? '',
            'port' => $_POST['port'] ?? '',
            'slots' => $_POST['slots'] ?? '',
            'map' => $_POST['map'] ?? '',
            'rcon_password' => $_POST['rcon_password'] ?? '',
            'mode' => $_POST['mode'] ?? '',
            'afk_guard' => $_POST['afk_guard'] ?? '',
        ];
        $res = ServerCmd::updateServerInstance($id, $data);
        echo json_encode($res);
        break;

    case 'save_admin':
    case 'save_admin_all':
        $applyAll = ($action === 'save_admin_all') || (($_POST['apply_all_servers'] ?? $_POST['apply_all'] ?? '0') === '1');
        $res = ServerCmd::saveAdminEverywhere(
            trim($_POST['auth'] ?? $_POST['admin_auth'] ?? ''),
            trim($_POST['password'] ?? $_POST['admin_pass'] ?? ''),
            trim($_POST['access'] ?? $_POST['admin_access'] ?? ''),
            trim($_POST['flags'] ?? $_POST['admin_flags'] ?? ''),
            trim($_POST['comment'] ?? $_POST['admin_comment'] ?? ''),
            $applyAll,
            $activeServer['id'],
            trim($_POST['old_auth'] ?? '')
        );
        echo json_encode($res);
        break;

    case 'delete_admin':
    case 'delete_admin_all':
        $applyAll = ($action === 'delete_admin_all') || (($_POST['apply_all_servers'] ?? $_POST['apply_all'] ?? '0') === '1');
        $res = ServerCmd::deleteAdminEverywhere(
            trim($_POST['auth'] ?? $_POST['delete_auth'] ?? ''),
            $applyAll,
            $activeServer['id']
        );
        echo json_encode($res);
        break;

    case 'get_admins':
        $admins = ServerCmd::getAdmins($activeServer['users_ini']);
        echo json_encode([
            'success' => true,
            'admins' => $admins,
            'server_name' => $activeServer['name']
        ]);
        break;

    case 'save_plugins_all':
        $plugins = $_POST['plugins'] ?? [];
        if (!is_array($plugins)) {
            $plugins = [$plugins];
        }
        $res = ServerCmd::savePluginsEverywhere(
            array_values(array_filter($plugins, 'is_string')),
            true,
            null,
            ($_POST['restart'] ?? '0') === '1'
        );
        echo json_encode($res);
        break;

    case 'deploy_mix_all':
        $res = ServerCmd::deployMixEverywhere(
            ($_POST['compile'] ?? '1') === '1',
            ($_POST['restart'] ?? '1') === '1'
        );
        echo json_encode($res);
        break;

    // ─── RCON Raw Command (Console page) ────────────────────────────────────
    case 'rcon_command':
        $command = trim($_POST['command'] ?? '');
        if (empty($command)) {
            echo json_encode(['success' => false, 'message' => 'Command cannot be empty']);
            exit;
        }
        try {
            $rcon = new GoldSourceRcon(
                $activeServer['ip'],
                $activeServer['port'],
                $activeServer['rcon_password'],
                2.5
            );
            $response = $rcon->execute($command);
            echo json_encode(['success' => true, 'response' => $response]);
        } catch (Exception $e) {
            echo json_encode(['success' => false, 'message' => $e->getMessage()]);
        }
        break;

    // ─── Service Control (start/stop/restart) ───────────────────────────────
    case 'service_control':
        $serviceAction = $_POST['service_action'] ?? '';
        $targetServerId = $_POST['server_id'] ?? ($activeServer['id'] ?? 'main');
        global $SERVERS;
        $svcTarget = $SERVERS[$targetServerId] ?? $activeServer;
        $res = ServerCmd::controlService($svcTarget['service_name'], $serviceAction);
        echo json_encode($res);
        break;

    // ─── Switch Active Server ────────────────────────────────────────────────
    case 'switch_server':
        $serverId = $_POST['server_id'] ?? '';
        global $SERVERS;
        if (isset($SERVERS[$serverId])) {
            $_SESSION['active_server_id'] = $serverId;
            echo json_encode(['success' => true]);
        } else {
            echo json_encode(['success' => false, 'message' => 'Unknown server']);
        }
        break;

    // ─── Get Server Logs ─────────────────────────────────────────────────────
    case 'get_logs':
        $lines = (int)($_POST['lines'] ?? 60);
        $logs = ServerCmd::getLogLines($activeServer['log_file'], $lines);
        echo json_encode(['success' => true, 'logs' => $logs]);
        break;

    // ─── GitHub Sync + Compile + Restart ─────────────────────────────────────
    case 'sync_mix':
        $compile = isset($_POST['compile']) && $_POST['compile'] == '1';
        $restart = isset($_POST['restart']) && $_POST['restart'] == '1';

        $syncRes = ServerCmd::syncMixFromGitHub($activeServer);
        if (!$syncRes['success']) {
            echo json_encode(['success' => false, 'message' => 'Failed to download files from GitHub. Check internet and file permissions.', 'details' => $syncRes]);
            exit;
        }

        $compileRes = null;
        if ($compile) {
            $compileRes = ServerCmd::compilePlugins($activeServer);
        }

        $restartRes = null;
        if ($restart) {
            $restartRes = ServerCmd::controlService($activeServer['service_name'], 'restart');
        }

        echo json_encode([
            'success'  => true,
            'sync'     => $syncRes,
            'compile'  => $compileRes,
            'restart'  => $restartRes,
            'message'  => 'GitHub sync and deploy finished!'
        ]);
        break;

    // ─── Compile Mix Plugins ──────────────────────────────────────────────────
    case 'compile_mix':
        $res = ServerCmd::compilePlugins($activeServer);
        echo json_encode($res);
        break;

    // ─── Mix In-Game Commands via RCON ────────────────────────────────────────
    // Supports: start, stop, knife, warm, pause, restart_round, stop_round
    case 'mix_command':
        $mixAction = trim($_POST['mix_action'] ?? '');

        $mixCmdMap = [
            'start'         => 'amx_mixa',          // start automix queue
            'stop'          => 'amx_mixstop',        // stop/reset match
            'knife'         => 'amx_knife',          // start knife round
            'warm'          => 'amx_warm',           // start warmup
            'pause'         => 'amx_pause',          // pause/unpause
            'restart_round' => 'sv_restart 1',       // restart current round
            'stop_round'    => 'amx_mixstop',        // stop match completely
            'endround'      => 'mp_roundtime 0.01',  // force end round quickly
            'cw_start'      => 'amx_cw start',       // start CW countdown
            'cw_fast'       => 'amx_cw fast',        // toggle fast CW test mode
            'cw_vote'       => 'amx_cw vote',        // force captain election
            'cw_draft'      => 'amx_cw draft',       // force team drafting
            'cw_spec'       => 'amx_cw spec',        // move all to spectator
            'cw_stop'       => 'amx_cw stop',        // reset CW to warmup
        ];

        if (!isset($mixCmdMap[$mixAction])) {
            echo json_encode(['success' => false, 'message' => 'Unknown mix action: ' . htmlspecialchars($mixAction)]);
            exit;
        }

        $rconCmd = $mixCmdMap[$mixAction];

        try {
            $rcon = new GoldSourceRcon(
                $activeServer['ip'],
                $activeServer['port'],
                $activeServer['rcon_password'],
                2.5
            );
            $response = $rcon->execute($rconCmd);
            echo json_encode([
                'success'  => true,
                'action'   => $mixAction,
                'command'  => $rconCmd,
                'response' => trim((string)$response)
            ]);
        } catch (Exception $e) {
            echo json_encode([
                'success' => false,
                'message' => 'RCON error: ' . $e->getMessage()
            ]);
        }
        break;

    // ─── Live Admin Reload via RCON ───────────────────────────────────────────
    case 'reload_admins':
        $res = ServerCmd::reloadAdminsLive($activeServer);
        echo json_encode($res);
        break;

    // ─── Get Plugin List (for plugins page live refresh) ─────────────────────
    case 'get_plugins':
        $plugins  = ServerCmd::getPluginsList($activeServer);
        $gitStatus = ServerCmd::getGitRepoStatus();
        echo json_encode([
            'success'   => true,
            'plugins'   => $plugins,
            'gitStatus' => $gitStatus
        ]);
        break;

    // ─── Toggle a Single Plugin (enable/disable in plugins.ini) ──────────────
    case 'toggle_plugin':
        $pluginFile = trim($_POST['plugin_file'] ?? '');
        $enable     = ($_POST['enable'] ?? '0') === '1';

        if (empty($pluginFile) || !preg_match('/^[a-zA-Z0-9_\-]+\.amxx$/', $pluginFile)) {
            echo json_encode(['success' => false, 'message' => 'Invalid plugin filename.']);
            exit;
        }

        // Get current plugin list, then toggle this one
        $allPlugins = ServerCmd::getPluginsList($activeServer);
        $enabled    = [];
        foreach ($allPlugins as $p) {
            if ($p['file'] === $pluginFile) {
                if ($enable) $enabled[] = $p['file'];
                // else skip (disable it)
            } elseif ($p['enabled']) {
                $enabled[] = $p['file'];
            }
        }

        $res = ServerCmd::savePluginsState($activeServer, $enabled);
        echo json_encode($res);
        break;

    // ─── Get GitHub Repo Status ───────────────────────────────────────────────
    case 'git_status':
        $status = ServerCmd::getGitRepoStatus();
        echo json_encode(['success' => true, 'status' => $status]);
        break;

    // ─── Get Compile Status (check if .amxx files exist and are newer) ────────
    case 'plugin_build_status':
        $managedStatus = ServerCmd::getPluginBuildStatus($activeServer);
        echo json_encode(['success' => true, 'builds' => array_values($managedStatus)]);
        break;

    // ─── VPS Checkpoint Management (Admins & Servers Only) ───────────────────
    case 'checkpoint_create':
        $label = trim($_POST['label'] ?? 'Manual VPS Checkpoint');
        $res = ServerCmd::createCheckpoint($label);
        echo json_encode($res);
        break;

    case 'checkpoint_list':
        $list = ServerCmd::listCheckpoints();
        echo json_encode(['success' => true, 'checkpoints' => $list]);
        break;

    case 'checkpoint_restore':
        $cpId = trim($_POST['checkpoint_id'] ?? 'latest');
        if (empty($cpId)) $cpId = 'latest';
        $res = ServerCmd::restoreCheckpoint($cpId);
        echo json_encode($res);
        break;

    case 'checkpoint_delete':
        $cpId = trim($_POST['checkpoint_id'] ?? '');
        if (empty($cpId)) {
            echo json_encode(['success' => false, 'message' => 'Checkpoint ID is required.']);
            exit;
        }
        $res = ServerCmd::deleteCheckpoint($cpId);
        echo json_encode($res);
        break;

    // ─── Full Build Pipeline Diagnostic ──────────────────────────────────────
    case 'diagnose_build':
        $scriptingDir = $activeServer['cstrike_dir'] . '/addons/amxmodx/scripting';
        $pluginsDir   = $activeServer['cstrike_dir'] . '/addons/amxmodx/plugins';
        $includeDir   = $scriptingDir . '/include';
        $compiler     = $scriptingDir . '/amxxpc';

        $diag = [];

        // 1. Compiler binary
        $compilerExists = file_exists($compiler);
        $diag[] = ['check' => 'Compiler (amxxpc) exists', 'ok' => $compilerExists, 'detail' => $compiler];

        if ($compilerExists) {
            // Make executable
            @chmod($compiler, 0755);
            foreach (['amxxpc32.so', 'amxxpc64.so'] as $lib) {
                if (file_exists($scriptingDir.'/'.$lib)) @chmod($scriptingDir.'/'.$lib, 0755);
            }

            // Test compiler version
            $verOut = @shell_exec('cd ' . escapeshellarg($scriptingDir) . ' && ./amxxpc --version 2>&1');
            $diag[] = ['check' => 'Compiler --version test', 'ok' => !empty($verOut), 'detail' => trim((string)$verOut)];
        }

        // 2. Include directory
        $diag[] = ['check' => 'Include dir exists', 'ok' => is_dir($includeDir), 'detail' => $includeDir];

        // Key includes
        foreach (['reapi.inc', 'mix_system.inc', 'cstrike.inc', 'amxmodx.inc'] as $inc) {
            $incPath = $includeDir . '/' . $inc;
            // Also check default amxmodx include path
            $sysIncPath = $scriptingDir . '/../include/' . $inc;
            $found = file_exists($incPath) || file_exists($sysIncPath);
            $diag[] = [
                'check'  => "Include: {$inc}",
                'ok'     => $found,
                'detail' => $found ? ($incPath) : 'NOT FOUND in ' . $includeDir,
            ];
        }

        // 3. Managed source files
        foreach (array_keys(ServerCmd::getManagedPluginTargets()) as $sma) {
            $p = $scriptingDir . '/' . $sma;
            $exists = file_exists($p);
            $diag[] = [
                'check'  => "Source: {$sma}",
                'ok'     => $exists,
                'detail' => $exists ? date('Y-m-d H:i:s', filemtime($p)) . ' (' . number_format(filesize($p)) . ' bytes)' : 'MISSING',
            ];
        }

        // 4. Managed binary status
        foreach (array_values(ServerCmd::getManagedPluginTargets()) as $amxx) {
            $p = $pluginsDir . '/' . $amxx;
            $exists = file_exists($p) && filesize($p) > 100;
            $diag[] = [
                'check'  => "Binary: {$amxx}",
                'ok'     => $exists,
                'detail' => $exists ? date('Y-m-d H:i:s', filemtime($p)) . ' (' . number_format(filesize($p)) . ' bytes)' : 'MISSING or empty',
            ];
        }

        // 5. plugins.ini check
        $pluginsIni = $activeServer['cstrike_dir'] . '/addons/amxmodx/configs/plugins.ini';
        $iniContent = file_exists($pluginsIni) ? file_get_contents($pluginsIni) : '';
        foreach (array_values(ServerCmd::getManagedPluginTargets()) as $amxx) {
            $registered = (bool)preg_match('/^\s*(?!;)\s*' . preg_quote($amxx, '/') . '(?:\s|$)/mi', $iniContent);
            $diag[] = ['check' => "{$amxx} in plugins.ini (enabled)", 'ok' => $registered, 'detail' => $pluginsIni];
        }

        // 6. Try a real test compile of mix_system.sma
        $testOut = '';
        if ($compilerExists && file_exists($scriptingDir . '/mix_system.sma')) {
            $testBin  = $pluginsDir . '/mix_system.amxx';
            $incArg   = escapeshellarg($includeDir);
            $testCmd  = 'cd ' . escapeshellarg($scriptingDir)
                      . ' && ./amxxpc mix_system.sma'
                      . ' -o' . escapeshellarg($testBin)
                      . ' -i"include" -i' . $incArg
                      . ' 2>&1';
            $testOut  = @shell_exec($testCmd);
            $compiled = file_exists($testBin) && filesize($testBin) > 100;
            $diag[]   = [
                'check'  => 'LIVE TEST: Compile mix_system.sma',
                'ok'     => $compiled,
                'detail' => trim((string)$testOut),
            ];
        }

        echo json_encode(['success' => true, 'diagnostics' => $diag]);
        break;

    // ──────────────────────────────────────────────────────────────────────────
    // Web IDE & Cloud Compiler Endpoints
    // ──────────────────────────────────────────────────────────────────────────

    case 'ide_list_files':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $files = ServerCmd::getIdeFileList($targetServer);
        echo json_encode([
            'success' => true,
            'server_id' => $targetServer['id'] ?? 'main',
            'server_name' => $targetServer['name'] ?? 'Server',
            'files' => $files,
        ]);
        break;

    case 'ide_load_file':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $relPath = $_POST['file_path'] ?? '';
        $res = ServerCmd::readIdeFile($targetServer, $relPath);
        echo json_encode($res);
        break;

    case 'ide_save_file':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $relPath = $_POST['file_path'] ?? '';
        $content = $_POST['content'] ?? '';
        $createBackup = isset($_POST['create_backup']) ? (bool)$_POST['create_backup'] : true;
        $res = ServerCmd::saveIdeFile($targetServer, $relPath, $content, $createBackup);
        echo json_encode($res);
        break;

    case 'ide_compile':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $smaFile = $_POST['sma_file'] ?? '';
        $propagate = !empty($_POST['propagate_to_all']);
        $restart = !empty($_POST['restart_after']);
        $res = ServerCmd::compileIdePlugin($targetServer, $smaFile, $propagate, $restart);
        echo json_encode($res);
        break;

    case 'ide_list_backups':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $relPath = $_POST['file_path'] ?? '';
        $backups = ServerCmd::listIdeBackups($targetServer, $relPath);
        echo json_encode(['success' => true, 'backups' => $backups]);
        break;

    case 'ide_restore_backup':
        $targetServer = $activeServer;
        if (!empty($_POST['server_id']) && isset($SERVERS[$_POST['server_id']])) {
            $targetServer = $SERVERS[$_POST['server_id']];
        }
        $relPath = $_POST['file_path'] ?? '';
        $backupName = $_POST['backup_name'] ?? '';
        $res = ServerCmd::restoreIdeBackup($targetServer, $relPath, $backupName);
        echo json_encode($res);
        break;

    default:
        echo json_encode(['success' => false, 'message' => 'Invalid action']);
        break;
}
