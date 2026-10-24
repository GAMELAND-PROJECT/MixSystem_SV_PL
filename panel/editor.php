<?php
$pageTitle = 'Online Web IDE & Cloud Compiler';
$activeNav = 'editor';
require_once __DIR__ . '/includes/header.php';

$requestedFile = $_GET['file'] ?? 'addons/amxmodx/scripting/clanwar_system.sma';
$targetServerId = $_GET['server_id'] ?? ($activeServer['id'] ?? 'main');
?>

<style>
/* ══════════════════════════════════════════════════════════════════════════
   GameLand Web IDE & Cloud Compiler Styles
   ══════════════════════════════════════════════════════════════════════════ */
.ide-wrapper {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    margin-bottom: 2rem;
}

.ide-toolbar {
    background: var(--bg-card);
    border: 1px solid var(--border-color);
    border-radius: 10px;
    padding: 0.75rem 1rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-wrap: wrap;
    gap: 0.75rem;
    box-shadow: 0 4px 18px rgba(0, 0, 0, 0.35);
}

.ide-toolbar-group {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
}

.ide-select {
    background: #0f1422;
    border: 1px solid #2a3754;
    color: #e2e8f0;
    padding: 0.45rem 0.8rem;
    border-radius: 6px;
    font-size: 0.85rem;
    outline: none;
    transition: border-color 0.2s;
    max-width: 320px;
}
.ide-select:focus {
    border-color: #38bdf8;
    box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.2);
}

.ide-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.45rem 0.85rem;
    border-radius: 6px;
    font-size: 0.82rem;
    font-weight: 600;
    cursor: pointer;
    border: 1px solid transparent;
    transition: all 0.2s ease;
    text-decoration: none;
}
.ide-btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
}

.ide-btn-primary {
    background: linear-gradient(135deg, #0284c7, #2563eb);
    color: #fff;
    border-color: rgba(56, 189, 248, 0.4);
    box-shadow: 0 2px 10px rgba(2, 132, 199, 0.3);
}
.ide-btn-primary:hover:not(:disabled) {
    background: linear-gradient(135deg, #0369a1, #1d4ed8);
    box-shadow: 0 4px 14px rgba(2, 132, 199, 0.45);
}

.ide-btn-compile {
    background: linear-gradient(135deg, #10b981, #059669);
    color: #fff;
    border-color: rgba(16, 185, 129, 0.5);
    box-shadow: 0 2px 12px rgba(16, 185, 129, 0.35);
    font-weight: 700;
}
.ide-btn-compile:hover:not(:disabled) {
    background: linear-gradient(135deg, #059669, #047857);
    box-shadow: 0 4px 16px rgba(16, 185, 129, 0.5);
}

.ide-btn-secondary {
    background: #1a2234;
    color: #cbd5e1;
    border: 1px solid #2a3754;
}
.ide-btn-secondary:hover:not(:disabled) {
    background: #232d45;
    border-color: #38bdf8;
    color: #fff;
}

.ide-btn-danger {
    background: rgba(239, 68, 68, 0.15);
    color: #f87171;
    border: 1px solid rgba(239, 68, 68, 0.35);
}
.ide-btn-danger:hover:not(:disabled) {
    background: rgba(239, 68, 68, 0.3);
    color: #fff;
}

.ide-badge-status {
    padding: 0.2rem 0.55rem;
    border-radius: 4px;
    font-size: 0.72rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}
.ide-badge-clean { background: rgba(16, 185, 129, 0.15); color: #34d399; border: 1px solid rgba(16, 185, 129, 0.3); }
.ide-badge-dirty { background: rgba(245, 158, 11, 0.2); color: #fbbf24; border: 1px solid rgba(245, 158, 11, 0.4); }

.ide-main {
    display: grid;
    grid-template-columns: 1fr;
    gap: 0.75rem;
}

.ide-editor-container {
    background: #121724;
    border: 1px solid var(--border-color);
    border-radius: 10px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    min-height: 580px;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.4);
}

.ide-editor-header {
    background: #0d121c;
    border-bottom: 1px solid #1e283d;
    padding: 0.5rem 0.9rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
    font-size: 0.82rem;
}

.ide-filepath-display {
    font-family: var(--font-mono);
    color: #7dd3fc;
    font-weight: 600;
    display: flex;
    align-items: center;
    gap: 0.4rem;
}

.ide-editor-surface {
    flex: 1;
    height: 580px;
    width: 100%;
    font-family: var(--font-mono);
    font-size: 14px;
}

/* Fallback textarea */
.ide-textarea-fallback {
    width: 100%;
    height: 100%;
    background: #0f1422;
    color: #e2e8f0;
    border: none;
    padding: 1rem;
    font-family: var(--font-mono);
    font-size: 13.5px;
    line-height: 1.5;
    outline: none;
    resize: vertical;
    white-space: pre;
    tab-size: 4;
}

/* Compiler Terminal Console */
.ide-terminal {
    background: #070a10;
    border: 1px solid #1f293d;
    border-radius: 10px;
    overflow: hidden;
    box-shadow: 0 4px 18px rgba(0, 0, 0, 0.5);
    margin-top: 0.5rem;
    display: none;
}
.ide-terminal.open {
    display: block;
}

.ide-terminal-header {
    background: #0b0f19;
    border-bottom: 1px solid #192233;
    padding: 0.5rem 0.9rem;
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.ide-terminal-body {
    padding: 0.85rem 1rem;
    font-family: var(--font-mono);
    font-size: 0.82rem;
    line-height: 1.5;
    max-height: 280px;
    overflow-y: auto;
    color: #94a3b8;
    white-space: pre-wrap;
    background: #05080e;
}

.ide-terminal-line-error {
    color: #f87171;
    font-weight: 600;
    background: rgba(239, 68, 68, 0.1);
    padding: 2px 4px;
    border-radius: 3px;
    cursor: pointer;
}
.ide-terminal-line-error:hover {
    text-decoration: underline;
    background: rgba(239, 68, 68, 0.25);
}

.ide-terminal-line-warn {
    color: #facc15;
}
.ide-terminal-line-success {
    color: #4ade80;
    font-weight: 700;
}

/* Modal Drawer */
.ide-modal-backdrop {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.8);
    backdrop-filter: blur(4px);
    z-index: 9999;
    justify-content: center;
    align-items: center;
    padding: 1rem;
}
.ide-modal-backdrop.open {
    display: flex;
}

.ide-modal-card {
    background: #141a29;
    border: 1px solid var(--border-color);
    border-radius: 12px;
    max-width: 680px;
    width: 100%;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.7);
}

.ide-modal-header {
    padding: 1rem 1.25rem;
    border-bottom: 1px solid var(--border-color);
    display: flex;
    justify-content: space-between;
    align-items: center;
}

.ide-modal-body {
    padding: 1.25rem;
    overflow-y: auto;
    flex: 1;
}
</style>

<div class="ide-wrapper">

    <!-- Top Info Notification Banner -->
    <div style="background: linear-gradient(135deg, rgba(56, 189, 248, 0.1), rgba(99, 102, 241, 0.08)); border: 1px solid rgba(56, 189, 248, 0.3); border-radius: 10px; padding: 0.75rem 1.2rem; display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 0.6rem;">
        <div style="display:flex; align-items:center; gap:0.6rem;">
            <span style="font-size:1.3rem;">⚡</span>
            <div>
                <strong style="color: #38bdf8; font-size: 0.95rem;">GameLand Cloud Web IDE &amp; 1-Click Compiler</strong>
                <div style="font-size: 0.8rem; color: var(--text-muted);">
                    ویرایش آنلاین پلاگین‌های پاون، فایل‌های زبان و کانفیگ‌ها با کامپایلر ابری AMX Mod X و سیستم پشتیبان‌گیری خودکار.
                </div>
            </div>
        </div>
        <div style="font-size: 0.78rem; color: #94a3b8; display: flex; gap: 0.6rem; align-items: center;">
            <span style="background: #1e293b; padding: 2px 7px; border-radius: 4px; border: 1px solid #334155;">Ctrl+S: ذخیره</span>
            <span style="background: #1e293b; padding: 2px 7px; border-radius: 4px; border: 1px solid #334155;">Ctrl+B: کامپایل</span>
        </div>
    </div>

    <!-- Main Toolbar -->
    <div class="ide-toolbar">
        <!-- Left: Server & File Selection -->
        <div class="ide-toolbar-group">
            <!-- Server Selector -->
            <label style="font-size:0.75rem; color:var(--text-muted); font-weight:600;">سرور:</label>
            <select id="serverSelect" class="ide-select" onchange="onServerChange(this.value)">
                <?php foreach ($SERVERS as $sId => $s): ?>
                    <option value="<?php echo htmlspecialchars($sId); ?>" <?php echo ($sId === $targetServerId) ? 'selected' : ''; ?>>
                        <?php echo htmlspecialchars($s['name']); ?> (<?php echo (int)$s['port']; ?>)
                    </option>
                <?php endforeach; ?>
            </select>

            <!-- File Selector -->
            <label style="font-size:0.75rem; color:var(--text-muted); font-weight:600;">سورس / فایل:</label>
            <select id="fileSelect" class="ide-select" onchange="onFileSelectChange(this.value)" style="min-width:240px;">
                <option value="">در حال دریافت لیست فایل‌ها...</option>
            </select>

            <!-- Status Indicator -->
            <span id="dirtyIndicator" class="ide-badge-status ide-badge-clean">ذخیره شده</span>
        </div>

        <!-- Right: Actions -->
        <div class="ide-toolbar-group">
            <!-- Snippets -->
            <select id="snippetsSelect" class="ide-select" onchange="insertSnippet(this.value)" style="max-width:140px;" title="درج سریع کدهای پرکاربرد AMXX">
                <option value="">🧩 قطعه‌کدها...</option>
                <option value="chat_color">پیام چت رنگی</option>
                <option value="set_task">تسک تاخیری (set_task)</option>
                <option value="register_clcmd">دستور کلاینت (register_clcmd)</option>
                <option value="register_cvar">سی‌وار سرور (register_cvar)</option>
                <option value="play_sound">پخش صدا (client_cmd spk)</option>
                <option value="dhud_message">بنر روی صفحه (dhud)</option>
            </select>

            <!-- Backups Button -->
            <button id="btnBackups" onclick="openBackupsModal()" class="ide-btn ide-btn-secondary" title="مشاهده تاریخچه پشتیبان‌ها">
                🕒 نسخه‌ها (<span id="backupCount">0</span>)
            </button>

            <!-- Save Button -->
            <button id="btnSave" onclick="saveActiveFile(false)" class="ide-btn ide-btn-primary" title="ذخیره فایل (Ctrl+S)">
                💾 ذخیره
            </button>

            <!-- Compile Button (Only for .sma) -->
            <button id="btnCompile" onclick="saveAndCompile()" class="ide-btn ide-btn-compile" title="ذخیره و کامپایل ابری (Ctrl+B)">
                ⚡ کامپایل ۱-کلیکه
            </button>

            <!-- Quick Options Dropdown / Toggle -->
            <label style="display:flex; align-items:center; gap:0.35rem; font-size:0.78rem; color:#cbd5e1; cursor:pointer;" title="پس از کامپایل موفق سرور ری‌استارت شود">
                <input type="checkbox" id="chkRestartAfter" checked style="accent-color:#10b981;">
                ری‌استارت سرور
            </label>

            <label style="display:flex; align-items:center; gap:0.35rem; font-size:0.78rem; color:#cbd5e1; cursor:pointer;" title="فایل کامپایل‌شده به تمام سرورهای فعال منتقل شود">
                <input type="checkbox" id="chkPropagateAll" style="accent-color:#38bdf8;">
                سینک همگانی
            </label>
        </div>
    </div>

    <!-- Main Workspace -->
    <div class="ide-main">
        <!-- Editor Card -->
        <div class="ide-editor-container">
            <div class="ide-editor-header">
                <div class="ide-filepath-display">
                    <span id="currentFileIcon">📄</span>
                    <span id="currentFilePath">در حال بارگذاری...</span>
                    <span id="fileSizeBadge" style="font-size:0.75rem; color:var(--text-muted); font-weight:normal;"></span>
                </div>
                <div style="display:flex; align-items:center; gap:0.8rem; font-size:0.78rem; color:var(--text-muted);">
                    <span id="lastSavedTime"></span>
                    <select id="fontSizeSelect" onchange="changeFontSize(this.value)" class="ide-select" style="padding:2px 6px; font-size:0.75rem;">
                        <option value="13">13px</option>
                        <option value="14" selected>14px</option>
                        <option value="16">16px</option>
                        <option value="18">18px</option>
                    </select>
                </div>
            </div>

            <!-- Code Editor Surface -->
            <div id="aceEditor" class="ide-editor-surface"></div>
            <textarea id="fallbackEditor" class="ide-textarea-fallback" style="display:none;" spellcheck="false"></textarea>
        </div>

        <!-- Terminal Output Console -->
        <div id="ideTerminal" class="ide-terminal">
            <div class="ide-terminal-header">
                <div style="display:flex; align-items:center; gap:0.5rem;">
                    <span style="font-size:1rem;">🖥️</span>
                    <strong style="font-size:0.85rem; color:#38bdf8;">خروجی کامپایلر ابری (AMX Mod X Compiler Terminal)</strong>
                    <span id="terminalStatusBadge" class="ide-badge-status ide-badge-clean" style="display:none;"></span>
                </div>
                <div style="display:flex; gap:0.4rem;">
                    <button onclick="clearTerminal()" class="ide-btn ide-btn-secondary" style="padding:2px 8px; font-size:0.72rem;">پاک کردن</button>
                    <button onclick="toggleTerminal(false)" class="ide-btn ide-btn-secondary" style="padding:2px 8px; font-size:0.72rem;">✕ بستن</button>
                </div>
            </div>
            <div id="terminalBody" class="ide-terminal-body">آماده کامپایل. برای شروع روی دکمه «⚡ کامپایل ۱-کلیکه» کلیک کنید.</div>
        </div>
    </div>
</div>

<!-- Backups Modal Drawer -->
<div id="backupsModal" class="ide-modal-backdrop" onclick="if(event.target===this) closeBackupsModal();">
    <div class="ide-modal-card">
        <div class="ide-modal-header">
            <div style="display:flex; align-items:center; gap:0.5rem;">
                <span style="font-size:1.1rem;">🕒</span>
                <strong style="font-size:0.95rem; color:#e2e8f0;">تاریخچه نسخه‌ها و پشتیبان‌های خودکار</strong>
            </div>
            <button onclick="closeBackupsModal()" class="ide-btn ide-btn-secondary" style="padding:2px 8px;">✕</button>
        </div>
        <div class="ide-modal-body">
            <div style="font-size:0.82rem; color:var(--text-muted); margin-bottom:1rem;">
                قبل از هر بار ذخیره، یک نسخه پشتیبان با برچسب زمان ساخته می‌شود تا در صورت بروز هرگونه مشکل بتوانید فوراً به نسخه قبل بازگردید.
            </div>
            <div id="backupsListContainer">
                <div style="text-align:center; padding:2rem; color:var(--text-muted);">در حال دریافت تاریخچه...</div>
            </div>
        </div>
    </div>
</div>

<!-- Load Ace Editor CDN -->
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.7/ace.js"></script>

<script>
// ══════════════════════════════════════════════════════════════════════════
// Web IDE Client Controller
// ══════════════════════════════════════════════════════════════════════════
let activeFileRelPath = "<?php echo addslashes($requestedFile); ?>";
let activeServerId = "<?php echo addslashes($targetServerId); ?>";
let isDirty = false;
let editorMode = 'ace'; // 'ace' or 'fallback'
let aceInstance = null;
let fileMetaCache = {};

// Initialize Editor
document.addEventListener('DOMContentLoaded', function() {
    initEditor();
    loadFileList(activeServerId, activeFileRelPath);
    setupKeyboardShortcuts();
});

function initEditor() {
    const aceEl = document.getElementById('aceEditor');
    const fallbackEl = document.getElementById('fallbackEditor');

    if (window.ace) {
        try {
            aceInstance = ace.edit("aceEditor");
            aceInstance.setTheme("ace/theme/tomorrow_night_eighties");
            aceInstance.session.setMode("ace/mode/c_cpp");
            aceInstance.setShowPrintMargin(false);
            aceInstance.session.setUseWrapMode(true);
            aceInstance.session.setTabSize(4);
            aceInstance.setFontSize(14);

            aceInstance.on('input', function() {
                if (!isDirty) {
                    markDirty(true);
                }
            });
            editorMode = 'ace';
        } catch (e) {
            console.warn('Ace init failed, falling back to textarea', e);
            fallbackToTextarea();
        }
    } else {
        fallbackToTextarea();
    }
}

function fallbackToTextarea() {
    editorMode = 'fallback';
    document.getElementById('aceEditor').style.display = 'none';
    const fb = document.getElementById('fallbackEditor');
    fb.style.display = 'block';
    fb.addEventListener('input', function() {
        if (!isDirty) markDirty(true);
    });
}

function getEditorContent() {
    if (editorMode === 'ace' && aceInstance) {
        return aceInstance.getValue();
    }
    return document.getElementById('fallbackEditor').value;
}

function setEditorContent(text, fileType) {
    if (editorMode === 'ace' && aceInstance) {
        aceInstance.setValue(text, -1);
        // Set mode based on file type
        let mode = 'ace/mode/c_cpp';
        if (fileType === 'ini' || fileType === 'cfg') mode = 'ace/mode/ini';
        else if (fileType === 'txt') mode = 'ace/mode/text';
        aceInstance.session.setMode(mode);
    } else {
        document.getElementById('fallbackEditor').value = text;
    }
    markDirty(false);
}

function markDirty(dirty) {
    isDirty = dirty;
    const badge = document.getElementById('dirtyIndicator');
    if (dirty) {
        badge.className = 'ide-badge-status ide-badge-dirty';
        badge.textContent = 'تغییرات ذخیره‌نشده *';
    } else {
        badge.className = 'ide-badge-status ide-badge-clean';
        badge.textContent = 'ذخیره شده';
    }
}

function changeFontSize(px) {
    if (editorMode === 'ace' && aceInstance) {
        aceInstance.setFontSize(parseInt(px, 10));
    } else {
        document.getElementById('fallbackEditor').style.fontSize = px + 'px';
    }
}

// ── File Management ──────────────────────────────────────────────────────────

function loadFileList(serverId, selectFileAfter) {
    const sel = document.getElementById('fileSelect');
    sel.innerHTML = '<option value="">در حال دریافت لیست فایل‌ها...</option>';

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_list_files');
    fd.append('server_id', serverId);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (!data.success) {
                sel.innerHTML = '<option value="">خطا در بارگذاری فایل‌ها</option>';
                alert('خطا در دریافت لیست فایل‌ها: ' + (data.message || 'نامشخص'));
                return;
            }

            sel.innerHTML = '';
            const groups = {};
            data.files.forEach(f => {
                const g = f.group || 'سایر';
                if (!groups[g]) groups[g] = [];
                groups[g].push(f);
                fileMetaCache[f.rel_path] = f;
            });

            let fileFound = false;
            for (const [grpName, grpFiles] of Object.entries(groups)) {
                const optGroup = document.createElement('optgroup');
                optGroup.label = grpName;
                grpFiles.forEach(f => {
                    const opt = document.createElement('option');
                    opt.value = f.rel_path;
                    opt.textContent = f.name + (f.size ? ' (' + formatBytes(f.size) + ')' : '');
                    if (f.rel_path === selectFileAfter) {
                        opt.selected = true;
                        fileFound = true;
                    }
                    optGroup.appendChild(opt);
                });
                sel.appendChild(optGroup);
            }

            // If selected file wasn't found, pick the first one
            if (!fileFound && data.files.length > 0) {
                sel.value = data.files[0].rel_path;
            }

            // Load the selected file
            if (sel.value) {
                loadFileContent(sel.value);
            }
        })
        .catch(err => {
            sel.innerHTML = '<option value="">خطای ارتباطی</option>';
            console.error('List files error:', err);
        });
}

function onServerChange(newServerId) {
    if (isDirty && !confirm('شما تغییرات ذخیره‌نشده دارید. آیا مایل به جابجایی سرور هستید؟')) {
        document.getElementById('serverSelect').value = activeServerId;
        return;
    }
    activeServerId = newServerId;
    loadFileList(activeServerId, activeFileRelPath);
}

function onFileSelectChange(relPath) {
    if (isDirty && !confirm('تغییراتی در فایل فعلی ذخیره نشده است. آیا می‌خواهید فایل جدید را باز کنید؟')) {
        document.getElementById('fileSelect').value = activeFileRelPath;
        return;
    }
    loadFileContent(relPath);
}

function loadFileContent(relPath) {
    activeFileRelPath = relPath;
    document.getElementById('currentFilePath').textContent = relPath;
    document.getElementById('currentFileIcon').textContent = getFileIcon(relPath);

    // Toggle compile button visibility
    const isSma = relPath.endsWith('.sma');
    const compileBtn = document.getElementById('btnCompile');
    compileBtn.style.display = isSma ? 'inline-flex' : 'none';

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_load_file');
    fd.append('server_id', activeServerId);
    fd.append('file_path', relPath);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (!data.success) {
                alert('خطا در باز کردن فایل: ' + (data.message || 'نامشخص'));
                return;
            }

            const ext = relPath.split('.').pop().toLowerCase();
            setEditorContent(data.content, ext);

            document.getElementById('fileSizeBadge').textContent = formatBytes(data.size);
            document.getElementById('lastSavedTime').textContent = 'آخرین ویرایش: ' + (data.mtime_str || 'نامشخص');
            document.getElementById('backupCount').textContent = (data.backups || []).length;
        })
        .catch(err => {
            alert('خطای شبکه در دریافت محتوای فایل: ' + err.message);
        });
}

// ── Save & Compile ───────────────────────────────────────────────────────────

function saveActiveFile(isCompiling = false, onSaveComplete = null) {
    const content = getEditorContent();
    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_save_file');
    fd.append('server_id', activeServerId);
    fd.append('file_path', activeFileRelPath);
    fd.append('content', content);
    fd.append('create_backup', '1');

    const saveBtn = document.getElementById('btnSave');
    saveBtn.disabled = true;
    saveBtn.textContent = '⏳ در حال ذخیره...';

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            saveBtn.disabled = false;
            saveBtn.textContent = '💾 ذخیره';

            if (!data.success) {
                alert('❌ خطا در ذخیره فایل: ' + (data.message || 'نامشخص'));
                return;
            }

            markDirty(false);
            document.getElementById('lastSavedTime').textContent = 'آخرین ویرایش: ' + (data.mtime_str || 'الان');
            document.getElementById('fileSizeBadge').textContent = formatBytes(data.size);

            if (!isCompiling) {
                showTransientMessage('✅ فایل با موفقیت ذخیره شد و نسخه پشتیبان ایجاد گردید.');
            }

            // Update backups count
            refreshBackupsCount();

            if (typeof onSaveComplete === 'function') {
                onSaveComplete();
            }
        })
        .catch(err => {
            saveBtn.disabled = false;
            saveBtn.textContent = '💾 ذخیره';
            alert('❌ خطای ارتباطی هنگام ذخیره فایل: ' + err.message);
        });
}

function saveAndCompile() {
    if (!activeFileRelPath.endsWith('.sma')) {
        alert('تنها فایل‌های سورس .sma امکان کامپایل دارند.');
        return;
    }

    saveActiveFile(true, function() {
        triggerCompiler();
    });
}

function triggerCompiler() {
    const compileBtn = document.getElementById('btnCompile');
    const term = document.getElementById('ideTerminal');
    const termBody = document.getElementById('terminalBody');
    const termBadge = document.getElementById('terminalStatusBadge');

    toggleTerminal(true);
    termBadge.style.display = 'inline-block';
    termBadge.className = 'ide-badge-status ide-badge-dirty';
    termBadge.textContent = 'در حال کامپایل...';
    termBody.innerHTML = '⚙️ [Cloud Compiler] Executing amxxpc for ' + escHtml(activeFileRelPath) + '...\n';

    compileBtn.disabled = true;
    compileBtn.innerHTML = '⏳ در حال کامپایل...';

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_compile');
    fd.append('server_id', activeServerId);
    fd.append('sma_file', activeFileRelPath.split('/').pop());
    fd.append('propagate_to_all', document.getElementById('chkPropagateAll').checked ? '1' : '0');
    fd.append('restart_after', document.getElementById('chkRestartAfter').checked ? '1' : '0');

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            compileBtn.disabled = false;
            compileBtn.innerHTML = '⚡ کامپایل ۱-کلیکه';

            if (data.success) {
                termBadge.className = 'ide-badge-status ide-badge-clean';
                termBadge.textContent = 'کامپایل موفق ✔';
            } else {
                termBadge.className = 'ide-badge-status ide-badge-dirty';
                termBadge.style.background = 'rgba(239, 68, 68, 0.2)';
                termBadge.style.color = '#f87171';
                termBadge.textContent = 'خطای کامپایل ✖';
            }

            renderCompilerOutput(data.output || '', data.message || '');
        })
        .catch(err => {
            compileBtn.disabled = false;
            compileBtn.innerHTML = '⚡ کامپایل ۱-کلیکه';
            termBadge.className = 'ide-badge-status ide-badge-dirty';
            termBadge.textContent = 'خطای شبکه';
            termBody.innerHTML += '\n❌ Network error: ' + escHtml(err.message);
        });
}

function renderCompilerOutput(output, summaryMsg) {
    const termBody = document.getElementById('terminalBody');
    termBody.innerHTML = '';

    const lines = output.split('\n');
    lines.forEach(line => {
        const div = document.createElement('div');
        div.textContent = line;

        // Check for error line like: clanwar_system.sma(123) : error 017: undefined symbol ...
        const errorMatch = line.match(/\.sma\((\d+)\)\s*:\s*error\s+(\d+)/i);
        if (errorMatch) {
            const lineNum = parseInt(errorMatch[1], 10);
            div.className = 'ide-terminal-line-error';
            div.title = 'کلیک برای پرش به خط ' + lineNum + ' در ادیتور';
            div.onclick = function() {
                jumpToLine(lineNum);
            };
        } else if (line.includes('warning ')) {
            div.className = 'ide-terminal-line-warn';
        } else if (line.includes('Done.') || line.includes('Total requirements:')) {
            div.className = 'ide-terminal-line-success';
        }
        termBody.appendChild(div);
    });

    if (summaryMsg) {
        const sumDiv = document.createElement('div');
        sumDiv.style.marginTop = '0.75rem';
        sumDiv.style.padding = '0.4rem 0.6rem';
        sumDiv.style.background = 'rgba(255, 255, 255, 0.05)';
        sumDiv.style.borderRadius = '4px';
        sumDiv.style.fontWeight = 'bold';
        sumDiv.textContent = '📣 ' + summaryMsg;
        termBody.appendChild(sumDiv);
    }
}

function jumpToLine(lineNum) {
    if (editorMode === 'ace' && aceInstance) {
        aceInstance.gotoLine(lineNum, 0, true);
        aceInstance.focus();
    }
}

function toggleTerminal(show) {
    const term = document.getElementById('ideTerminal');
    if (show) term.classList.add('open');
    else term.classList.remove('open');
}

function clearTerminal() {
    document.getElementById('terminalBody').innerHTML = '';
}

// ── Backups & Revert ─────────────────────────────────────────────────────────

function openBackupsModal() {
    document.getElementById('backupsModal').classList.add('open');
    loadBackupsList();
}

function closeBackupsModal() {
    document.getElementById('backupsModal').classList.remove('open');
}

function loadBackupsList() {
    const container = document.getElementById('backupsListContainer');
    container.innerHTML = '<div style="text-align:center; padding:1.5rem; color:var(--text-muted);">⏳ در حال بارگذاری لیست نسخه‌ها...</div>';

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_list_backups');
    fd.append('server_id', activeServerId);
    fd.append('file_path', activeFileRelPath);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (!data.success || !data.backups || data.backups.length === 0) {
                container.innerHTML = '<div style="text-align:center; padding:2rem; color:var(--text-muted);">هنوز هیچ نسخه پشتیبانی برای این فایل ثبت نشده است.<br><small style="opacity:0.7;">با هر بار ذخیره، یک نسخه خودکار در این قسمت اضافه خواهد شد.</small></div>';
                return;
            }

            let html = '<table style="width:100%; border-collapse:collapse; font-size:0.85rem;">';
            html += '<thead><tr style="border-bottom:1px solid var(--border-color); color:var(--text-muted); text-align:left;">';
            html += '<th style="padding:0.5rem;">زمان پشتیبان</th>';
            html += '<th style="padding:0.5rem;">حجم</th>';
            html += '<th style="padding:0.5rem; text-align:right;">عملیات</th>';
            html += '</tr></thead><tbody>';

            data.backups.forEach(b => {
                html += '<tr style="border-bottom:1px solid rgba(255,255,255,0.04);">';
                html += '<td style="padding:0.6rem 0.5rem; font-family:var(--font-mono);">' + escHtml(b.date_str) + '</td>';
                html += '<td style="padding:0.6rem 0.5rem; color:var(--text-muted);">' + formatBytes(b.size) + '</td>';
                html += '<td style="padding:0.6rem 0.5rem; text-align:right;">';
                html += '<button onclick="restoreBackup(\'' + escHtml(b.filename) + '\')" class="ide-btn ide-btn-secondary" style="padding:3px 10px; font-size:0.75rem; color:#38bdf8; border-color:rgba(56,189,248,0.3);">';
                html += '↺ بازگردانی این نسخه';
                html += '</button>';
                html += '</td>';
                html += '</tr>';
            });

            html += '</tbody></table>';
            container.innerHTML = html;
            document.getElementById('backupCount').textContent = data.backups.length;
        })
        .catch(err => {
            container.innerHTML = '<div style="color:var(--danger); padding:1rem;">خطا در دریافت پشتیبان‌ها: ' + escHtml(err.message) + '</div>';
        });
}

function restoreBackup(backupName) {
    if (!confirm('آیا مطمئن هستید که می‌خواهید فایل را به نسخه [' + backupName + '] بازگردانید؟')) {
        return;
    }

    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_restore_backup');
    fd.append('server_id', activeServerId);
    fd.append('file_path', activeFileRelPath);
    fd.append('backup_name', backupName);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (!data.success) {
                alert('❌ خطا در بازگردانی نسخه: ' + (data.message || 'نامشخص'));
                return;
            }

            const ext = activeFileRelPath.split('.').pop().toLowerCase();
            setEditorContent(data.content, ext);
            closeBackupsModal();
            showTransientMessage('✅ نسخه با موفقیت بازگردانده شد.');
        })
        .catch(err => {
            alert('خطای شبکه در بازگردانی نسخه: ' + err.message);
        });
}

function refreshBackupsCount() {
    const fd = new FormData();
    fd.append('csrf_token', window.CSRF_TOKEN);
    fd.append('action', 'ide_list_backups');
    fd.append('server_id', activeServerId);
    fd.append('file_path', activeFileRelPath);

    fetch('api.php', { method: 'POST', body: fd })
        .then(r => r.json())
        .then(data => {
            if (data.success && data.backups) {
                document.getElementById('backupCount').textContent = data.backups.length;
            }
        });
}

// ── Snippets Injection ───────────────────────────────────────────────────────

function insertSnippet(type) {
    if (!type) return;
    const snippets = {
        'chat_color': 'client_print_color(id, print_team_default, "^4[GameLand]^1 Your message here");\n',
        'set_task': 'set_task(1.0, "MyFunctionCallback", 1337);\n',
        'register_clcmd': 'register_clcmd("say /mycmd", "Cmd_MyCommand");\n',
        'register_cvar': 'new pCvarMySetting;\npCvarMySetting = register_cvar("amx_my_setting", "1");\n',
        'play_sound': 'client_cmd(id, "spk buttons/bell1.wav");\n',
        'dhud_message': 'set_dhudmessage(0, 180, 255, -1.0, 0.25, 0, 6.0, 3.0);\nshow_dhudmessage(0, "GameLand Match Server");\n'
    };

    const text = snippets[type] || '';
    if (text) {
        if (editorMode === 'ace' && aceInstance) {
            aceInstance.insert(text);
            aceInstance.focus();
        } else {
            const fb = document.getElementById('fallbackEditor');
            const pos = fb.selectionStart;
            fb.value = fb.value.substring(0, pos) + text + fb.value.substring(fb.selectionEnd);
            fb.selectionStart = fb.selectionEnd = pos + text.length;
            fb.focus();
        }
        markDirty(true);
    }
    document.getElementById('snippetsSelect').value = '';
}

// ── Keyboard Shortcuts ───────────────────────────────────────────────────────

function setupKeyboardShortcuts() {
    window.addEventListener('keydown', function(e) {
        if ((e.ctrlKey || e.metaKey) && (e.key === 's' || e.key === 'S')) {
            e.preventDefault();
            saveActiveFile(false);
        } else if ((e.ctrlKey || e.metaKey) && (e.key === 'b' || e.key === 'B')) {
            e.preventDefault();
            saveAndCompile();
        } else if (e.key === 'F9') {
            e.preventDefault();
            saveAndCompile();
        } else if (e.key === 'Escape') {
            closeBackupsModal();
        }
    });
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function getFileIcon(path) {
    if (path.endsWith('.sma')) return '⚡';
    if (path.endsWith('.inc')) return '📚';
    if (path.endsWith('.txt')) return '💬';
    if (path.endsWith('.ini') || path.endsWith('.cfg')) return '⚙️';
    return '📄';
}

function formatBytes(bytes) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

function escHtml(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function showTransientMessage(msg) {
    const div = document.createElement('div');
    div.style.position = 'fixed';
    div.style.bottom = '20px';
    div.style.right = '20px';
    div.style.background = '#1e293b';
    div.style.border = '1px solid #38bdf8';
    div.style.color = '#fff';
    div.style.padding = '0.75rem 1.25rem';
    div.style.borderRadius = '8px';
    div.style.boxShadow = '0 4px 20px rgba(0,0,0,0.5)';
    div.style.zIndex = '10000';
    div.style.fontSize = '0.85rem';
    div.style.fontWeight = 'bold';
    div.textContent = msg;
    document.body.appendChild(div);
    setTimeout(() => {
        div.style.transition = 'opacity 0.4s ease';
        div.style.opacity = '0';
        setTimeout(() => div.remove(), 400);
    }, 3000);
}
</script>

<?php require_once __DIR__ . '/includes/footer.php'; ?>
