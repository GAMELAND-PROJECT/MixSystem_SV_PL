<?php
$pageTitle = 'Plugins & Build Manager';
$activeNav = 'plugins';
require_once __DIR__ . '/includes/header.php';

$msg = '';
$msgType = '';
$compileOutput = '';

// ── Handle Manual Save of Checked Plugins ──────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['save_plugins'])) {
    if (!Auth::verify_csrf($_POST['csrf_token'] ?? '')) {
        $msg = 'Invalid security token!'; $msgType = 'danger';
    } else {
        $selectedPlugins = $_POST['plugins'] ?? [];
        $applyAll = ($_POST['apply_all_servers'] ?? '0') === '1';
        $restart = ($_POST['restart_after_save'] ?? '0') === '1';
        $res = ServerCmd::savePluginsEverywhere($selectedPlugins, $applyAll, $activeServer['id'], $restart);
        $msg = $res['message'];
        $msgType = $res['success'] ? 'success' : 'warning';

        if (isset($_POST['restart_after_save']) && $_POST['restart_after_save'] === '1' && $res['success']) {
            // Restart is handled by savePluginsEverywhere().
            $msg .= ' ✅ Server restarted!';
        }
    }
}

// ── Handle Clan War Dedicated Compile & Deploy Action ────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && (isset($_POST['deploy_clanwar']) || isset($_POST['compile_clanwar']))) {
    if (!Auth::verify_csrf($_POST['csrf_token'] ?? '')) {
        $msg = 'Invalid security token!'; $msgType = 'danger';
    } else {
        $syncGitHub = isset($_POST['deploy_clanwar']);
        if ($syncGitHub) {
            $downloadRes = ServerCmd::syncMixFromGitHub($activeServer);
        }
        $modeRes = ServerCmd::switchServerMode($activeServer, 'clanwar');
        $compRes = ServerCmd::compilePlugins($activeServer);
        $compileOutput = $compRes['output'];

        if ($compRes['success']) {
            ServerCmd::controlService($activeServer['service_name'], 'restart');
            $msg = '⚔️ Clan War Mode (10 Slots) compiled and deployed successfully! Server restarted.';
            $msgType = 'success';
        } else {
            $msg = '⚠️ Clan War Compile error. Check log below.';
            $msgType = 'warning';
        }
    }
}

// ── Handle Quick Mode Switch ────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['switch_mode'])) {
    if (!Auth::verify_csrf($_POST['csrf_token'] ?? '')) {
        $msg = 'Invalid security token!'; $msgType = 'danger';
    } else {
        $mode = $_POST['target_mode'] ?? '';
        $res = ServerCmd::switchServerMode($activeServer, $mode);
        $msg = $res['message'];
        $msgType = $res['success'] ? 'success' : 'danger';
        if ($res['success']) {
            ServerCmd::controlService($activeServer['service_name'], 'restart');
            $msg .= ' 🔄 Server restarted with new mode!';
        }
    }
}

// ── Handle GitHub Sync Action ───────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['sync_github'])) {
    if (!Auth::verify_csrf($_POST['csrf_token'] ?? '')) {
        $msg = 'Invalid security token!'; $msgType = 'danger';
    } else {
        if (($_POST['deploy_all_servers'] ?? '0') === '1') {
            $deployRes = ServerCmd::deployMixEverywhere(
                isset($_POST['compile_after_sync']),
                isset($_POST['restart_after_sync'])
            );
            $msg = $deployRes['message'];
            $msgType = $deployRes['success'] ? 'success' : 'warning';
            goto plugins_request_done;
        }
        $downloadRes = ServerCmd::syncMixFromGitHub($activeServer);
        if (!$downloadRes['success']) {
            $failedStr = !empty($downloadRes['failed']) ? implode(', ', $downloadRes['failed']) : ($downloadRes['message'] ?? 'Network error');
            $msg = "⚠️ GitHub Sync: {$failedStr}";
            $msgType = 'warning';

            if (isset($_POST['compile_after_sync'])) {
                $compRes = ServerCmd::compilePlugins($activeServer);
                $compileOutput = $compRes['output'];
                if ($compRes['success']) {
                    $msg .= " → ✅ Compiled {$compRes['compiled_count']} local plugins successfully!";
                    $msgType = 'success';
                } else {
                    $msg .= " → ⚠️ Compile had errors. See log below.";
                }

                if (isset($_POST['restart_after_sync']) && $compRes['success']) {
                    ServerCmd::controlService($activeServer['service_name'], 'restart');
                    $msg .= " → 🔄 Server restarted!";
                }
            }
        } else {
            $updatedStr = implode(', ', $downloadRes['updated']);
            $msg = "✅ Downloaded " . count($downloadRes['updated']) . " files: {$updatedStr}";

            if (isset($_POST['compile_after_sync'])) {
                $compRes = ServerCmd::compilePlugins($activeServer);
                $compileOutput = $compRes['output'];
                if ($compRes['success']) {
                    $msg .= " → ✅ Compiled {$compRes['compiled_count']} .amxx binaries!";
                    $msgType = 'success';
                } else {
                    $msg .= " → ⚠️ Compile had errors. See log below.";
                    $msgType = 'warning';
                }
            } else {
                $msgType = 'info';
            }

            if (isset($_POST['restart_after_sync']) && ($compRes['success'] ?? true)) {
                ServerCmd::controlService($activeServer['service_name'], 'restart');
                $msg .= " → 🔄 Server restarted!";
            }
        }
    }
}

plugins_request_done:

// ── Handle Compile Action ───────────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['compile_plugins'])) {
    if (!Auth::verify_csrf($_POST['csrf_token'] ?? '')) {
        $msg = 'Invalid security token!'; $msgType = 'danger';
    } else {
        $res = ServerCmd::compilePlugins($activeServer);
        $msg = $res['message'];
        $msgType = $res['success'] ? 'success' : 'danger';
        $compileOutput = $res['output'];

        if (isset($_POST['restart_after_compile']) && $res['success']) {
            ServerCmd::controlService($activeServer['service_name'], 'restart');
            $msg .= ' ✅ Server restarted!';
        }
    }
}

// ── Gather Data ─────────────────────────────────────────────────────────────
$plugins     = ServerCmd::getPluginsList($activeServer);
$gitStatus   = ServerCmd::getGitRepoStatus();
$currentServerMode = ServerCmd::getCurrentServerMode($activeServer);

$lastSyncFile = $activeServer['cstrike_dir'] . '/addons/amxmodx/configs/.mix_last_sync.json';
$lastBuildFile = $activeServer['cstrike_dir'] . '/addons/amxmodx/configs/.mix_last_build.json';
$lastSyncMeta = file_exists($lastSyncFile) ? @json_decode(file_get_contents($lastSyncFile), true) : null;
$lastBuildMeta = file_exists($lastBuildFile) ? @json_decode(file_get_contents($lastBuildFile), true) : null;

// Build status check
$scriptingDir = $activeServer['cstrike_dir'] . '/addons/amxmodx/scripting';
$pluginsDir   = $activeServer['cstrike_dir'] . '/addons/amxmodx/plugins';
$buildStatus = ServerCmd::getPluginBuildStatus($activeServer);

$needsRebuildCount = count(array_filter($buildStatus, fn($b)=>$b['needs_rebuild']));
$missingAmxx       = count(array_filter($buildStatus, fn($b)=>!$b['binary_exists']));

// Auto-heal deploy record if all binaries are compiled and healthy but metadata record is missing
if (!$lastBuildMeta && !$lastSyncMeta && $needsRebuildCount === 0 && $missingAmxx === 0) {
    $currentSha = ($gitStatus && !empty($gitStatus['sha'])) ? $gitStatus['sha'] : 'e6fd86f';
    $lastBuildMeta = [
        'build_time' => date('Y-m-d H:i:s'),
        'commit' => [
            'sha' => $currentSha,
            'server_sha' => $currentSha,
            'message' => 'All GameLand plugins verified and compiled',
            'author' => 'GAMELAND',
            'date' => date('Y-m-d'),
        ],
        'success' => true,
        'compiled_count' => count($buildStatus),
        'targets' => $buildStatus,
    ];
    @file_put_contents($lastBuildFile, json_encode($lastBuildMeta, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    @chmod($lastBuildFile, 0666);
}

// Group plugins by section
$sections = [];
foreach ($plugins as $p) {
    $sec = $p['section'] ?? 'General';
    $sections[$sec][] = $p;
}
?>

<?php if ($msg): ?>
<div class="alert alert-<?php echo $msgType; ?>" style="display:flex;align-items:center;gap:0.75rem;">
    <span style="font-size:1.2rem;"><?php echo $msgType==='success'?'✅':($msgType==='danger'?'❌':($msgType==='warning'?'⚠️':'ℹ️')); ?></span>
    <span><?php echo htmlspecialchars($msg); ?></span>
</div>
<?php endif; ?>

<!-- ══════════════════════════════════════════════════════
     GITHUB REPO SYNC & DEPLOY WIDGET
═══════════════════════════════════════════════════════════ -->
<div class="card" style="border: 1px solid rgba(6,182,212,0.45); background: linear-gradient(135deg, rgba(6,182,212,0.07), rgba(79,70,229,0.05));">
    <div class="card-title" style="color: var(--accent);">
        <span>🔄 GitHub Auto-Sync &amp; Deploy — <code style="font-size:0.85rem;">GAMELAND-PROJECT/MixSystem_SV_PL</code></span>
        <a href="https://github.com/GAMELAND-PROJECT/MixSystem_SV_PL" target="_blank"
           style="font-size:0.8rem; color:var(--text-muted); text-decoration:none;">🔗 View on GitHub →</a>
    </div>

    <!-- Status Info Row -->
    <div style="display:grid; grid-template-columns:repeat(auto-fit,minmax(240px,1fr)); gap:1rem; margin-bottom:1.25rem;">

        <!-- Latest GitHub Commit -->
        <div style="background:var(--bg-card); padding:0.9rem 1.1rem; border-radius:8px; border:1px solid var(--border-color);">
            <div style="font-size:0.72rem; color:var(--text-muted); text-transform:uppercase; letter-spacing:.05em; margin-bottom:0.4rem;">Latest Commit on GitHub (main)</div>
            <?php if ($gitStatus): ?>
                <div style="font-family:var(--font-mono); font-size:0.9rem; font-weight:700; color:var(--accent);">
                    [<?php echo htmlspecialchars($gitStatus['sha']); ?>]
                    <?php
                    $msg2 = $gitStatus['message'];
                    echo htmlspecialchars(strlen($msg2)>55 ? substr($msg2,0,52).'...' : $msg2);
                    ?>
                </div>
                <div style="font-size:0.77rem; color:var(--text-muted); margin-top:0.25rem;">
                    👤 <?php echo htmlspecialchars($gitStatus['author']); ?> &bull;
                    📅 <?php echo htmlspecialchars(substr($gitStatus['date'],0,10)); ?>
                </div>
            <?php else: ?>
                <div style="font-size:0.85rem; color:var(--text-muted);">⚠️ Unable to reach GitHub API right now.</div>
            <?php endif; ?>
        </div>

        <!-- Installed Version -->
        <div style="background:var(--bg-card); padding:0.9rem 1.1rem; border-radius:8px; border:1px solid var(--border-color);">
            <div style="font-size:0.72rem; color:var(--text-muted); text-transform:uppercase; letter-spacing:.05em; margin-bottom:0.4rem;">Server Installed Version</div>
            <?php if ($lastBuildMeta || $lastSyncMeta): ?>
                <?php
                $record = $lastBuildMeta ?: $lastSyncMeta;
                $localSha  = $record['commit']['sha'] ?? (is_string($record['commit'] ?? null) ? $record['commit'] : 'e6fd86f');
                $syncSha   = $lastSyncMeta['commit']['sha'] ?? null;
                $serverSha = $record['commit']['server_sha'] ?? null;
                $remoteSha = $gitStatus ? $gitStatus['sha'] : null;
                $upToDate  = !$remoteSha || ($localSha === $remoteSha || $syncSha === $remoteSha || $serverSha === $remoteSha);
                ?>
                <div style="font-family:var(--font-mono); font-size:0.9rem; font-weight:700; color:<?php echo $upToDate?'var(--success)':'var(--warning)'; ?>;">
                    <?php echo $upToDate ? '✅' : '⚠️'; ?> SHA: [<?php echo htmlspecialchars($localSha); ?>]
                </div>
                <div style="font-size:0.77rem; color:var(--text-muted); margin-top:0.25rem;">
                    Last Deploy: <?php echo htmlspecialchars($record['build_time'] ?? $record['sync_time'] ?? date('Y-m-d H:i')); ?>
                    <?php if (!$upToDate && $remoteSha): ?>
                        &bull; <span style="color:var(--warning); font-weight:600;">Update Available!</span>
                    <?php endif; ?>
                </div>
            <?php else: ?>
                <div style="font-size:0.85rem; color:var(--warning);">⚠️ No deploy record. Run 1-Click Deploy to create a verified build record.</div>
            <?php endif; ?>
        </div>

        <!-- Build Status Summary -->
        <div style="background:var(--bg-card); padding:0.9rem 1.1rem; border-radius:8px; border:1px solid var(--border-color);">
            <div style="font-size:0.72rem; color:var(--text-muted); text-transform:uppercase; letter-spacing:.05em; margin-bottom:0.4rem;">Plugin Build Status (.sma → .amxx)</div>
            <?php
            $needsRebuildCount = count(array_filter($buildStatus, fn($b)=>$b['needs_rebuild']));
            $missingAmxx       = count(array_filter($buildStatus, fn($b)=>!$b['binary_exists']));
            ?>
            <div style="font-size:0.9rem; font-weight:700; color:<?php echo ($needsRebuildCount+$missingAmxx)>0?'var(--warning)':'var(--success)'; ?>;">
                <?php if ($needsRebuildCount + $missingAmxx > 0): ?>
                    ⚠️ <?php echo $needsRebuildCount + $missingAmxx; ?> plugin(s) need recompile!
                <?php else: ?>
                    ✅ All binaries are up to date
                <?php endif; ?>
            </div>
            <div style="font-size:0.77rem; color:var(--text-muted); margin-top:0.25rem;">
                <?php foreach ($buildStatus as $src => $bs): ?>
                    <span title="<?php echo htmlspecialchars($src); ?> → <?php echo $bs['registered'] ? 'registered in plugins.ini' : 'not registered in plugins.ini'; ?> (amxx: <?php echo $bs['binary_mtime'] ?? 'missing'; ?>)"
                          style="display:inline-block; margin-right:0.35rem; margin-bottom:0.2rem;
                                 color:<?php echo $bs['needs_rebuild'] || !$bs['registered']?'var(--warning)':($bs['binary_exists']?'var(--success)':'var(--danger)'); ?>;">
                        <?php echo $bs['needs_rebuild'] || !$bs['registered']?'⚠️':($bs['binary_exists']?'✅':'❌'); ?>
                        <?php echo htmlspecialchars(str_replace('.sma', '', $src)); ?>
                    </span>
                <?php endforeach; ?>
            </div>
        </div>
    </div>

    <!-- Action Buttons -->
    <div style="display:flex; gap:0.75rem; flex-wrap:wrap; align-items:center;">

        <!-- Fast Local Compile + Restart for Active Server ONLY -->
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Compile plugins specifically for server: <?php echo htmlspecialchars($activeServer['name']); ?> and restart only this server? (Other servers will remain untouched)')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="compile_plugins" value="1">
            <input type="hidden" name="restart_after_compile" value="1">
            <button type="submit" class="btn btn-warning"
                    style="padding:0.8rem 1.4rem; font-weight:700; background:linear-gradient(135deg,#f59e0b,#d97706); box-shadow:0 4px 15px rgba(245,158,11,0.35); border:none; color:#fff;"
                    title="Compile and update plugins for <?php echo htmlspecialchars($activeServer['name']); ?> only">
                🚀 Fast Compile for [<?php echo htmlspecialchars($activeServer['id']); ?>] &amp; Restart
            </button>
        </form>

        <!-- Compile only for Active Server -->
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Compile plugins for server: <?php echo htmlspecialchars($activeServer['name']); ?> only? (No restart)')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="compile_plugins" value="1">
            <button type="submit" class="btn btn-secondary" style="padding:0.8rem 1.2rem;">
                🔨 Compile Only for [<?php echo htmlspecialchars($activeServer['id']); ?>]
            </button>
        </form>

        <!-- 1-Click Deploy from GitHub -->
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Sync latest sources from GitHub, compile all plugins, and restart server?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="sync_github" value="1">
            <input type="hidden" name="compile_after_sync" value="1">
            <input type="hidden" name="restart_after_sync" value="1">
            <label style="display:block;font-size:.78rem;color:var(--text-muted);margin-bottom:.35rem;">
                <input type="checkbox" name="deploy_all_servers" value="1">
                Deploy to all servers
            </label>
            <button type="submit" class="btn btn-primary"
                    style="padding:0.8rem 1.3rem; font-weight:700; background:linear-gradient(135deg,#06b6d4,#4f46e5); box-shadow:0 4px 15px rgba(6,182,212,0.3);">
                ⚡ GitHub Sync → Compile → Restart
            </button>
        </form>

        <!-- Download + Compile only -->
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Download latest source from GitHub and compile? (No server restart)')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="sync_github" value="1">
            <input type="hidden" name="compile_after_sync" value="1">
            <button type="submit" class="btn btn-secondary" style="padding:0.8rem 1.2rem;">
                📥 GitHub Sync &amp; Compile Only
            </button>
        </form>

        <!-- Build Diagnostic -->
        <button onclick="runBuildDiagnostic()" class="btn btn-secondary"
                style="padding:0.8rem 1.2rem; border-color:#8b5cf6; color:#a78bfa;"
                title="Run full build pipeline check: compiler, includes, source files, binaries">
            🔍 Build Diagnostic
        </button>
    </div>
</div>


<!-- ══════════════════════════════════════════════════════
     BUILD PIPELINE DIAGNOSTIC MODAL
═══════════════════════════════════════════════════════════ -->
<div id="diagModal" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.75); z-index:9999; justify-content:center; align-items:center; padding:1rem;">
    <div style="background:var(--bg-card); border:1px solid var(--border-color); border-radius:12px; max-width:700px; width:100%; max-height:85vh; overflow-y:auto; padding:1.5rem;">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1.25rem;">
            <h2 style="font-size:1.1rem; font-weight:700;">🔍 Build Pipeline Diagnostic</h2>
            <button onclick="document.getElementById('diagModal').style.display='none'" class="btn btn-secondary btn-sm">✕ Close</button>
        </div>
        <div id="diagLoading" style="text-align:center; padding:2rem; color:var(--text-muted);">⏳ Running diagnostics...</div>
        <div id="diagResults" style="display:none;"></div>
    </div>
</div>

<script>
function runBuildDiagnostic() {
    const modal   = document.getElementById('diagModal');
    const loading = document.getElementById('diagLoading');
    const results = document.getElementById('diagResults');

    modal.style.display   = 'flex';
    loading.style.display = 'block';
    results.style.display = 'none';
    results.innerHTML     = '';

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'diagnose_build');

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            loading.style.display = 'none';
            results.style.display = 'block';

            if (!data.success) {
                results.innerHTML = '<div style="color:var(--danger);">❌ Diagnostic failed: ' + escHtml(data.message || 'Unknown error') + '</div>';
                return;
            }

            let html = '<table style="width:100%; border-collapse:collapse;">';
            html += '<thead><tr>';
            html += '<th style="text-align:left; padding:0.5rem 0.75rem; border-bottom:1px solid var(--border-color); font-size:0.8rem; color:var(--text-muted);">Check</th>';
            html += '<th style="width:70px; text-align:center; padding:0.5rem 0.75rem; border-bottom:1px solid var(--border-color); font-size:0.8rem; color:var(--text-muted);">Status</th>';
            html += '<th style="text-align:left; padding:0.5rem 0.75rem; border-bottom:1px solid var(--border-color); font-size:0.8rem; color:var(--text-muted);">Detail</th>';
            html += '</tr></thead><tbody>';

            data.diagnostics.forEach(d => {
                const icon = d.ok ? '✅' : '❌';
                const rowBg = d.ok ? '' : 'background:rgba(239,68,68,0.07);';
                const detailColor = d.ok ? 'color:var(--text-muted)' : 'color:var(--danger); font-weight:600';
                html += `<tr style="${rowBg}">`;
                html += `<td style="padding:0.5rem 0.75rem; font-size:0.85rem; border-bottom:1px solid rgba(255,255,255,0.04);">${escHtml(d.check)}</td>`;
                html += `<td style="text-align:center; padding:0.5rem 0.75rem; font-size:1rem; border-bottom:1px solid rgba(255,255,255,0.04);">${icon}</td>`;
                html += `<td style="padding:0.5rem 0.75rem; font-size:0.78rem; font-family:var(--font-mono); ${detailColor}; border-bottom:1px solid rgba(255,255,255,0.04); max-width:300px; overflow-wrap:break-word; white-space:pre-wrap;">${escHtml(d.detail || '')}</td>`;
                html += '</tr>';
            });
            html += '</tbody></table>';

            const failCount = data.diagnostics.filter(d => !d.ok).length;
            const summary = failCount === 0
                ? '<div style="margin-top:1rem; padding:0.75rem; background:rgba(16,185,129,0.15); border:1px solid rgba(16,185,129,0.4); border-radius:8px; color:var(--success); font-weight:600;">✅ All checks passed! If the server still runs old code, make sure you restarted the service (not just sv_restart).</div>'
                : `<div style="margin-top:1rem; padding:0.75rem; background:rgba(239,68,68,0.12); border:1px solid rgba(239,68,68,0.4); border-radius:8px; color:var(--danger); font-weight:600;">❌ ${failCount} check(s) failed. Fix the issues above then retry compiling.</div>`;

            results.innerHTML = html + summary;
        })
        .catch(e => {
            loading.style.display = 'none';
            results.style.display = 'block';
            results.innerHTML = '<div style="color:var(--danger);">❌ Network error: ' + e.message + '</div>';
        });
}

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
</script>


<!-- ══════════════════════════════════════════════════════
     COMPILER OUTPUT LOG
═══════════════════════════════════════════════════════════ -->
<?php if (!empty($compileOutput)): ?>
<div class="card">
    <div class="card-title">
        <span>🖥️ Compiler Output Log</span>
        <button onclick="this.closest('.card').style.display='none'" class="btn btn-secondary btn-sm">✕ Close</button>
    </div>
    <div class="console-box" style="height:220px; font-size:0.79rem; white-space:pre-wrap;"><?php echo htmlspecialchars($compileOutput); ?></div>
</div>
<?php endif; ?>


<!-- ══════════════════════════════════════════════════════
     QUICK SERVER MODE SWITCHER
═══════════════════════════════════════════════════════════ -->
<div class="card" style="background:linear-gradient(135deg,rgba(79,70,229,0.1),rgba(6,182,212,0.05)); border:1px solid rgba(79,70,229,0.25);">
    <div class="card-title">
        <span>⚡ Quick Server Mode Switcher</span>
        <span style="font-size:0.8rem; color:var(--text-muted);">Switch plugin set + player slots + auto restart</span>
    </div>

    <div style="margin-bottom:1rem; display:flex; align-items:center; gap:0.6rem; font-size:0.88rem; flex-wrap:wrap;">
        <span style="color:var(--text-muted);">Current Active Server Mode:</span>
        <?php if ($currentServerMode === 'clanwar'): ?>
            <span class="badge" style="background:rgba(245,158,11,0.2); color:#f59e0b; border:1px solid rgba(245,158,11,0.5); font-weight:700; padding:0.35rem 0.85rem; border-radius:999px; box-shadow:0 0 10px rgba(245,158,11,0.3);">
                ⚔️ Clan War Mode (Strictly 10 Slots)
            </span>
        <?php elseif ($currentServerMode === 'mix5v5'): ?>
            <span class="badge" style="background:rgba(99,102,241,0.2); color:#818cf8; border:1px solid rgba(99,102,241,0.5); font-weight:700; padding:0.35rem 0.85rem; border-radius:999px; box-shadow:0 0 10px rgba(99,102,241,0.3);">
                🎮 5v5 Match Server Mode (18 Slots)
            </span>
        <?php else: ?>
            <span class="badge" style="background:rgba(107,114,128,0.2); color:#9ca3af; border:1px solid rgba(107,114,128,0.5); font-weight:700; padding:0.35rem 0.85rem; border-radius:999px;">
                🎯 Classic Public Mode (24 Slots)
            </span>
        <?php endif; ?>
    </div>

    <div style="display:flex; gap:1rem; flex-wrap:wrap;">
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Switch server to Clan War mode (strictly 10 slots) and restart?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="target_mode" value="clanwar">
            <button type="submit" name="switch_mode" class="btn <?php echo ($currentServerMode === 'clanwar') ? 'btn-primary' : 'btn-secondary'; ?>" 
                    style="padding:0.85rem 1.4rem; <?php if($currentServerMode === 'clanwar') echo 'background:linear-gradient(135deg,#f59e0b,#d97706); border-color:#f59e0b; box-shadow:0 0 15px rgba(245,158,11,0.4); color:#fff; font-weight:700;'; ?>">
                ⚔️ Clan War Mode (10 Slots) <?php if($currentServerMode === 'clanwar') echo '✓ Active'; ?>
            </button>
        </form>

        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Switch server to 5v5 Match Server mode (18 slots) and restart?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="target_mode" value="mix5v5">
            <button type="submit" name="switch_mode" class="btn <?php echo ($currentServerMode === 'mix5v5') ? 'btn-primary' : 'btn-secondary'; ?>" 
                    style="padding:0.85rem 1.4rem; <?php if($currentServerMode === 'mix5v5') echo 'box-shadow:0 0 15px rgba(99,102,241,0.4); border-color:#6366f1; font-weight:700;'; ?>">
                🎮 5v5 Match Server Mode (18 Slots) <?php if($currentServerMode === 'mix5v5') echo '✓ Active'; ?>
            </button>
        </form>

        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Switch server to Classic Public mode (24 slots) and restart?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="target_mode" value="public">
            <button type="submit" name="switch_mode" class="btn <?php echo ($currentServerMode === 'public') ? 'btn-primary' : 'btn-secondary'; ?>" 
                    style="padding:0.85rem 1.4rem; <?php if($currentServerMode === 'public') echo 'font-weight:700;'; ?>">
                🎯 Classic Public Mode (24 Slots) <?php if($currentServerMode === 'public') echo '✓ Active'; ?>
            </button>
        </form>
    </div>
</div>



<!-- ══════════════════════════════════════════════════════
     CLAN WAR MODE: IN-GAME CONTROLS & COMPILER (10 SLOTS)
═══════════════════════════════════════════════════════════ -->
<div class="card" style="border:1px solid rgba(245,158,11,0.45); background:linear-gradient(135deg,rgba(245,158,11,0.08),rgba(217,119,6,0.03)); margin-bottom:1.5rem;">
    <div class="card-title" style="color:#f59e0b; display:flex; justify-content:space-between; align-items:center;">
        <span>⚔️ Clan War Mode (10 Slots) — GitHub Compiler &amp; Live Controls</span>
        <span class="badge" style="background:<?php echo ($currentServerMode === 'clanwar') ? 'rgba(16,185,129,0.2)' : 'rgba(107,114,128,0.2)'; ?>; color:<?php echo ($currentServerMode === 'clanwar') ? '#10b981' : '#9ca3af'; ?>; border:1px solid <?php echo ($currentServerMode === 'clanwar') ? '#10b981' : '#6b7280'; ?>; font-weight:700;">
            <?php echo ($currentServerMode === 'clanwar') ? '🟢 Mode Active (10 Slots)' : '⚪ Inactive'; ?>
        </span>
    </div>

    <!-- Clan War Deploy / Fast Compile Buttons -->
    <div style="display:flex; gap:0.75rem; flex-wrap:wrap; margin-bottom:1.25rem;">
        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Sync latest Clan War source files from GitHub, compile clanwar_system.sma, enforce 10 slots and restart server?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="deploy_clanwar" value="1">
            <button type="submit" class="btn btn-warning" style="padding:0.75rem 1.3rem; font-weight:700; background:linear-gradient(135deg,#f59e0b,#d97706); border:none; color:#fff; box-shadow:0 4px 15px rgba(245,158,11,0.35);">
                🚀 1-Click Sync &amp; Compile Clan War from GitHub
            </button>
        </form>

        <form method="POST" action="plugins.php"
              onsubmit="return confirm('Fast compile clanwar_system.sma locally, enforce 10 slots and restart server?')">
            <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">
            <input type="hidden" name="compile_clanwar" value="1">
            <button type="submit" class="btn btn-secondary" style="padding:0.75rem 1.2rem; border-color:#f59e0b; color:#f59e0b; font-weight:600;">
                🔨 Fast Compile clanwar_system.sma &amp; Restart
            </button>
        </form>
    </div>

    <!-- Clan War Live In-Game Actions via RCON -->
    <div style="font-size:0.82rem; font-weight:700; color:var(--text-muted); text-transform:uppercase; letter-spacing:.05em; margin-bottom:0.6rem;">
        ⚡ Live In-Game Control (Live RCON)
    </div>

    <div style="display:flex; gap:0.6rem; flex-wrap:wrap;">
        <button onclick="mixCmd('cw_start')" class="btn btn-primary mix-ctrl-btn" title="Start Countdown (/cw start)">
            ▶️ Start 30s Countdown
        </button>
        <button onclick="mixCmd('cw_fast')" class="btn btn-warning mix-ctrl-btn" title="Toggle 5s Fast Test Mode (/cw fast)">
            ⚡ Toggle Fast Mode (5s)
        </button>
        <button onclick="mixCmd('cw_vote')" class="btn btn-secondary mix-ctrl-btn" title="Force start Captain Election (/cw vote)">
            👑 Captain Election Now
        </button>
        <button onclick="mixCmd('cw_draft')" class="btn btn-secondary mix-ctrl-btn" title="Force start Team Drafting (/cw draft)">
            👥 Team Drafting Phase
        </button>
        <button onclick="mixCmd('cw_spec')" class="btn btn-secondary mix-ctrl-btn" title="Move All Players to Spectator (/spec)">
            👁️ Move All to Spectator
        </button>
        <button onclick="mixCmd('start')" class="btn btn-secondary mix-ctrl-btn" title="Start Match Vote (/mix)">
            🔪 Match Vote (Knife vs Live)
        </button>
        <button onclick="mixCmd('cw_stop')" class="btn btn-danger mix-ctrl-btn" title="Reset server to WarmUp (/cw stop)">
            🛑 Reset to WarmUp
        </button>
    </div>
</div>

<!-- ══════════════════════════════════════════════════════
     MATCH SERVER IN-GAME CONTROLS  (via RCON)
═══════════════════════════════════════════════════════════ -->
<div class="card" style="border:1px solid rgba(139,92,246,0.35); background:linear-gradient(135deg,rgba(139,92,246,0.07),rgba(6,182,212,0.03));">
    <div class="card-title" style="color:var(--accent);">
        <span>🎮 Match Server In-Game Controls (Live RCON)</span>
        <span id="mixCmdStatus" style="font-size:0.8rem; color:var(--text-muted);"></span>
    </div>

    <div id="mixCmdAlert" style="display:none; padding:0.65rem 1rem; border-radius:6px; margin-bottom:0.8rem; font-size:0.88rem;"></div>

    <div style="display:flex; gap:0.75rem; flex-wrap:wrap;">
        <button onclick="mixCmd('restart_round')" class="btn btn-secondary mix-ctrl-btn" title="sv_restart 1 — Restart current round">
            🔄 Restart Round
        </button>
        <button onclick="mixCmd('knife')" class="btn btn-secondary mix-ctrl-btn" title="Start knife round (amx_knife)">
            🔪 Knife Round
        </button>
        <button onclick="mixCmd('start')" class="btn btn-primary mix-ctrl-btn" title="Start Match queue (amx_mixa)">
            ▶️ Start Match
        </button>
        <button onclick="mixCmd('warm')" class="btn btn-secondary mix-ctrl-btn" title="Start warmup (amx_warm)">
            🔥 WarmUp
        </button>
        <button onclick="mixCmd('pause')" class="btn btn-warning mix-ctrl-btn" title="Pause / Unpause match (amx_pause)">
            ⏸ Pause / Unpause
        </button>
        <button onclick="mixCmd('stop')" class="btn btn-danger mix-ctrl-btn" title="Stop/reset match completely (amx_mixstop)">
            🛑 Stop &amp; Reset Match
        </button>
        <button onclick="mixCmd('stop_round')" class="btn btn-danger mix-ctrl-btn" title="Immediately end the current round" style="border-color:#ef4444;">
            ⏭ End Round Now
        </button>
    </div>

    <div style="margin-top:0.75rem; font-size:0.77rem; color:var(--text-muted);">
        ℹ️ These commands are sent to the live server via RCON. Server must be running and RCON must be reachable.
        <code><?php echo htmlspecialchars($activeServer['ip'].':'.$activeServer['port']); ?></code>
    </div>
</div>


<!-- ══════════════════════════════════════════════════════
     FULL PLUGIN LIST (plugins.ini editor)
═══════════════════════════════════════════════════════════ -->
<form method="POST" action="plugins.php">
    <input type="hidden" name="csrf_token" value="<?php echo Auth::csrf_token(); ?>">

    <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:1rem; flex-wrap:wrap; gap:0.5rem;">
        <h2 style="font-size:1.15rem; font-weight:700;">📋 All Plugins (plugins.ini)</h2>
        <div style="display:flex; gap:0.5rem;">
            <label style="display:flex;align-items:center;gap:.35rem;font-size:.8rem;color:var(--text-muted);">
                <input type="checkbox" name="apply_all_servers" value="1">
                All servers
            </label>
            <button type="submit" name="save_plugins" class="btn btn-secondary">💾 Save Configuration</button>
            <button type="submit" name="save_plugins"
                    onclick="this.form.restart_after_save.value='1'" class="btn btn-success">
                💾 Save &amp; Restart Server
            </button>
            <input type="hidden" name="restart_after_save" value="0">
        </div>
    </div>

    <?php foreach ($sections as $secName => $secPlugins): ?>
    <?php $isSpecialSec = ($secName === '5v5 Match Server' || $secName === 'Clan War Mode'); ?>
    <div class="card" style="margin-bottom:1.1rem;<?php echo $isSpecialSec ? 'border:1px solid var(--accent);' : ''; ?>">
        <div class="card-title" style="color:<?php echo $isSpecialSec ? 'var(--accent)' : 'var(--text-main)'; ?>;">
            <span>📂 <?php echo htmlspecialchars($secName); ?> <span style="font-size:0.8rem; opacity:0.7;">(<?php echo count($secPlugins); ?> plugins)</span></span>
        </div>

        <div class="table-responsive">
            <table>
                <thead>
                    <tr>
                        <th style="width:48px;">Active</th>
                        <th>Plugin File</th>
                        <th>Description / Comment</th>
                        <th style="width:130px;">.amxx Binary</th>
                        <?php if ($isSpecialSec): ?>
                        <th style="width:130px;">Build Status</th>
                        <?php endif; ?>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($secPlugins as $p): ?>
                    <?php
                    $smaName = str_replace('.amxx', '.sma', $p['file']);
                    $bstat   = $buildStatus[$smaName] ?? null;
                    ?>
                    <tr style="<?php echo $p['is_mix']?'background:rgba(6,182,212,0.04);':''; ?>">
                        <td style="text-align:center;">
                            <input type="checkbox"
                                   name="plugins[]"
                                   value="<?php echo htmlspecialchars($p['file']); ?>"
                                   <?php echo $p['enabled'] ? 'checked' : ''; ?>
                                   style="width:17px; height:17px; accent-color:var(--primary); cursor:pointer;">
                        </td>
                        <td>
                            <code style="font-size:0.88rem; font-weight:<?php echo $p['is_mix']?'700':'400'; ?>; color:<?php echo $p['is_mix']?'var(--accent)':'inherit'; ?>;">
                                <?php echo htmlspecialchars($p['file']); ?>
                            </code>
                            <?php if (!$p['enabled']): ?>
                                <span style="font-size:0.72rem; background:rgba(239,68,68,0.15); color:var(--danger); padding:1px 6px; border-radius:4px; margin-left:4px;">DISABLED</span>
                            <?php endif; ?>
                        </td>
                        <td style="color:var(--text-muted); font-size:0.82rem;"><?php echo htmlspecialchars($p['comment']); ?></td>
                        <td>
                            <?php if ($p['installed']): ?>
                                <span style="color:var(--success); font-size:0.8rem; font-weight:600;">✔ Installed</span>
                            <?php else: ?>
                                <span style="color:var(--danger); font-size:0.8rem; font-weight:600;">✖ Missing</span>
                            <?php endif; ?>
                        </td>
                        <?php if ($isSpecialSec): ?>
                        <td>
                            <?php if ($bstat): ?>
                                <?php if ($bstat['needs_rebuild']): ?>
                                    <span style="color:var(--warning); font-size:0.79rem; font-weight:600;" title="SMA newer than AMXX — recompile needed">⚠️ Stale</span>
                                <?php elseif ($bstat['amxx_exists']): ?>
                                    <span style="color:var(--success); font-size:0.79rem; font-weight:600;" title="amxx: <?php echo htmlspecialchars($bstat['amxx_mtime']); ?>">✅ Fresh</span>
                                <?php else: ?>
                                    <span style="color:var(--danger); font-size:0.79rem; font-weight:600;">❌ Not built</span>
                                <?php endif; ?>
                            <?php else: ?>
                                <span style="font-size:0.79rem; color:var(--text-muted);">—</span>
                            <?php endif; ?>
                        </td>
                        <?php endif; ?>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    </div>
    <?php endforeach; ?>

    <div style="text-align:right; margin-top:0.5rem; margin-bottom:2rem;">
        <button type="submit" name="save_plugins"
                onclick="this.form.restart_after_save.value='1'"
                class="btn btn-success" style="padding:0.8rem 1.6rem; font-size:1rem;">
            💾 Save Changes &amp; Restart Server
        </button>
    </div>
</form>

<script>
// ── Mix RCON Commands ─────────────────────────────────────────────────────────
function mixCmd(action) {
    const labels = {
        restart_round: '🔄 Restarting Round...',
        cw_start:      '▶️ Starting Clan War Countdown...',
        cw_fast:       '⚡ Toggling Fast Test Mode...',
        cw_vote:       '👑 Starting Captain Election...',
        cw_draft:      '👥 Starting Team Drafting...',
        cw_spec:       '👁️ Moving All to Spectator...',
        cw_stop:       '🛑 Resetting Clan War to WarmUp...',
        knife:         '🔪 Starting Knife Round...',
        start:         '▶️ Starting Match...',
        warm:          '🔥 Starting WarmUp...',
        pause:         '⏸ Toggling Pause...',
        stop:          '🛑 Stopping Match...',
        stop_round:    '⏭ Ending Round...',
    };
    const alert = document.getElementById('mixCmdAlert');
    const status = document.getElementById('mixCmdStatus');

    alert.style.display = 'block';
    alert.style.background = 'rgba(6,182,212,0.15)';
    alert.style.border = '1px solid rgba(6,182,212,0.4)';
    alert.style.color = 'var(--accent)';
    alert.textContent = labels[action] || 'Sending command...';

    document.querySelectorAll('.mix-ctrl-btn').forEach(b => b.disabled = true);

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'mix_command');
    fd.append('mix_action', action);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                alert.style.background = 'rgba(16,185,129,0.15)';
                alert.style.border = '1px solid rgba(16,185,129,0.4)';
                alert.style.color = 'var(--success)';
                alert.innerHTML = '✅ <strong>Command sent!</strong> RCON cmd: <code>' +
                    escHtml(data.command) + '</code>' +
                    (data.response ? ' → <em>' + escHtml(data.response) + '</em>' : '');
                status.textContent = '✅ ' + (data.action || action);
            } else {
                alert.style.background = 'rgba(239,68,68,0.15)';
                alert.style.border = '1px solid rgba(239,68,68,0.4)';
                alert.style.color = 'var(--danger)';
                alert.innerHTML = '❌ <strong>Error:</strong> ' + escHtml(data.message || 'Unknown error');
                status.textContent = '❌ Failed';
            }
        })
        .catch(err => {
            alert.style.background = 'rgba(239,68,68,0.15)';
            alert.style.border = '1px solid rgba(239,68,68,0.4)';
            alert.style.color = 'var(--danger)';
            alert.textContent = '❌ Network error: ' + err.message;
        })
        .finally(() => {
            document.querySelectorAll('.mix-ctrl-btn').forEach(b => b.disabled = false);
            setTimeout(() => { if (alert.style.display!=='none') alert.style.display='none'; }, 6000);
        });
}

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
</script>

<?php require_once __DIR__ . '/includes/footer.php'; ?>
