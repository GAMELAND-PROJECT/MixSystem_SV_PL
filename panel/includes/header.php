<?php
require_once __DIR__ . '/../config.php';
require_once __DIR__ . '/Auth.php';
require_once __DIR__ . '/Rcon.class.php';
require_once __DIR__ . '/ServerCmd.php';

Auth::check();
$activeServer = get_active_server();
$serverStatus = ServerCmd::getServiceStatus($activeServer['service_name'], (int)($activeServer['port'] ?? 0), $activeServer['id'] ?? '');
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo htmlspecialchars($pageTitle ?? 'Dashboard'); ?> - GameLand Web Panel</title>
    <link rel="stylesheet" href="assets/style.css">
    <script>
        window.CSRF_TOKEN = "<?php echo Auth::csrf_token(); ?>";

        window.createGlobalCheckpoint = function() {
            const label = prompt('یادداشت یا برچسب برای چک‌پوینت سرتاسری (اختیاری):', 'Global Checkpoint (Admins & Servers)');
            if (label === null) return;
            const fd = new FormData();
            fd.append('csrf_token', window.CSRF_TOKEN);
            fd.append('action', 'checkpoint_create');
            fd.append('label', label || 'Global Checkpoint');

            fetch('api.php', { method: 'POST', body: fd })
                .then(r => r.json())
                .then(d => {
                    if (d.success) {
                        alert('✅ چک‌پوینت سرتاسری با موفقیت ثبت شد!\nتعداد سرورها: ' + d.checkpoint.server_count + '\nتعداد ادمین‌ها: ' + d.checkpoint.admin_count);
                        if (typeof loadCheckpoints === 'function') loadCheckpoints();
                    } else {
                        alert('❌ خطا در ساخت چک‌پوینت: ' + (d.message || 'خطا'));
                    }
                })
                .catch(e => alert('❌ خطای ارتباط: ' + e.message));
        };

        window.restoreLatestGlobalCheckpoint = function() {
            if (!confirm('⚠️ آیا مطمئن هستید؟\n\nتمامی ادمین‌ها و تنظیمات سرورها به «آخرین چک‌پوینت» بازگردانده خواهند شد.\n(پلاگین‌ها بدون تغییر باقی می‌مانند)')) return;
            const fd = new FormData();
            fd.append('csrf_token', window.CSRF_TOKEN);
            fd.append('action', 'checkpoint_restore');
            fd.append('checkpoint_id', 'latest');

            fetch('api.php', { method: 'POST', body: fd })
                .then(r => r.json())
                .then(d => {
                    if (d.success) {
                        alert('✅ ' + (d.message || 'با موفقیت به آخرین چک‌پوینت بازگردانده شد!'));
                        location.reload();
                    } else {
                        alert('❌ خطا در بازگردانی: ' + (d.message || 'چک‌پوینتی یافت نشد'));
                    }
                })
                .catch(e => alert('❌ خطای ارتباط: ' + e.message));
        };
    </script>
</head>
<body>

<nav class="navbar">
    <div style="display: flex; align-items: center; gap: 1rem; flex-wrap: wrap;">
        <a href="dashboard.php" class="nav-brand">
            <span class="badge-gl">GAMELAND</span>
            <span>CS 1.6 Panel</span>
        </a>

        <!-- Multi-Server Switcher -->
        <select class="server-selector" onchange="switchServer(this.value)">
            <?php foreach ($SERVERS as $sId => $s): ?>
                <option value="<?php echo htmlspecialchars($sId); ?>" <?php echo ($sId === $activeServer['id']) ? 'selected' : ''; ?>>
                    <?php echo htmlspecialchars($s['name']); ?> (Port: <?php echo $s['port']; ?>)
                </option>
            <?php endforeach; ?>
        </select>

        <!-- Global Checkpoint Controls -->
        <div style="display:flex; align-items:center; gap:0.4rem;">
            <button onclick="createGlobalCheckpoint()" class="btn btn-sm"
                    style="background:linear-gradient(135deg,#f59e0b,#ea580c); color:#fff; font-weight:700; border:none; padding:0.35rem 0.75rem; border-radius:6px; box-shadow:0 2px 8px rgba(245,158,11,0.3); font-size:0.8rem; cursor:pointer;"
                    title="ثبت چک‌پوینت سرتاسری از تمام ادمین‌ها و سرورها">
                💾 Global Checkpoint
            </button>
            <button onclick="restoreLatestGlobalCheckpoint()" class="btn btn-sm btn-secondary"
                    style="border:1px solid #f59e0b; color:#fbbf24; font-weight:600; padding:0.35rem 0.65rem; border-radius:6px; font-size:0.8rem; cursor:pointer;"
                    title="بازگردانی تمام ادمین‌ها و سرورها به آخرین چک‌پوینت">
                ↺ Restore Latest
            </button>
        </div>
    </div>

    <div class="nav-menu">
        <a href="dashboard.php" class="nav-link <?php echo ($activeNav ?? '') === 'dashboard' ? 'active' : ''; ?>">Dashboard</a>
        <a href="servers.php" class="nav-link <?php echo ($activeNav ?? '') === 'servers' ? 'active' : ''; ?>">Servers</a>
        <a href="plugins.php" class="nav-link <?php echo ($activeNav ?? '') === 'plugins' ? 'active' : ''; ?>" style="color: var(--accent);">Plugins & Modes</a>
        <a href="editor.php" class="nav-link <?php echo ($activeNav ?? '') === 'editor' ? 'active' : ''; ?>" style="color: #38bdf8; font-weight: 700; text-shadow: 0 0 10px rgba(56, 189, 248, 0.4);">⚡ Web IDE</a>
        <a href="console.php" class="nav-link <?php echo ($activeNav ?? '') === 'console' ? 'active' : ''; ?>">RCON Console</a>
        <a href="maps.php" class="nav-link <?php echo ($activeNav ?? '') === 'maps' ? 'active' : ''; ?>">Maps & Players</a>
        <a href="bans.php" class="nav-link <?php echo ($activeNav ?? '') === 'bans' ? 'active' : ''; ?>">Bans</a>
        <a href="admins.php" class="nav-link <?php echo ($activeNav ?? '') === 'admins' ? 'active' : ''; ?>">Admin Manager</a>
        <a href="logout.php" class="nav-link" style="color: var(--danger);">Logout</a>
    </div>
</nav>

<div class="container">
