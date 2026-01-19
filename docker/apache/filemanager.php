<?php
declare(strict_types=1);

/**
 * Bilingual File Manager (EN/RU)
 *
 * Modes (FILEMANAGER_MODE):
 * - admin: shows entire /data folder, everything under auth
 * - protected: shows subdomain folder, files accessible without auth
 * - public: shows subdomain folder, files accessible without auth
 */

$MODE = getenv('FILEMANAGER_MODE') ?: 'public';
$LANG = getenv('FILEMANAGER_LANG') ?: 'en';
$BASE_DOMAIN = getenv('BASE_DOMAIN') ?: 'example.com';
$PROTOCOL = 'https';

// Translations
$i18n = [
    'en' => [
        'not_found' => 'Not Found',
        'path_not_found' => 'Path not found',
        'subdomain_not_found' => 'Subdomain not found',
        'error' => 'Error',
        'admin_panel' => 'Admin Panel',
        'admin_badge' => 'Admin',
        'protected_badge' => 'Protected',
        'back' => 'Back',
        'name' => 'Name',
        'size' => 'Size',
        'files_in_dir' => 'Files',
        'modified' => 'Modified',
        'action' => 'Action',
        'copy' => 'Copy link',
        'copied' => 'Copied!',
        'link_copied' => 'Link copied!',
        'item' => 'item',
        'items_few' => 'items',
        'items_many' => 'items',
        'gb' => 'GB',
        'mb' => 'MB',
        'kb' => 'KB',
        'b' => 'B',
    ],
    'ru' => [
        'not_found' => 'Не найдено',
        'path_not_found' => 'Путь не найден',
        'subdomain_not_found' => 'Поддомен не найден',
        'error' => 'Ошибка',
        'admin_panel' => 'Админ-панель',
        'admin_badge' => 'Админ',
        'protected_badge' => 'Защищённый',
        'back' => 'Назад',
        'name' => 'Имя',
        'size' => 'Размер',
        'files_in_dir' => 'Файлов',
        'modified' => 'Изменён',
        'action' => 'Действие',
        'copy' => 'Скопировать ссылку',
        'copied' => 'Готово!',
        'link_copied' => 'Ссылка скопирована!',
        'item' => 'элемент',
        'items_few' => 'элемента',
        'items_many' => 'элементов',
        'gb' => 'ГБ',
        'mb' => 'МБ',
        'kb' => 'КБ',
        'b' => 'Б',
    ],
];

$t = $i18n[$LANG] ?? $i18n['en'];

// Determine base folder depending on mode
if ($MODE === 'admin') {
    $BASE = '/data';
    $SUBDOMAIN = null;
} else {
    $host = $_SERVER['HTTP_HOST'] ?? '';
    $hostParts = explode('.', $host);
    $SUBDOMAIN = $hostParts[0] ?? '';
    $BASE = '/data/' . $SUBDOMAIN;

    if (!$SUBDOMAIN || !is_dir($BASE)) {
        http_response_code(404);
        echo "<h1>{$t['subdomain_not_found']}</h1>";
        exit;
    }
}

function h(string $s): string
{
    return htmlspecialchars($s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function url_path(string $rel): string
{
    $segments = array_map('rawurlencode', array_filter(explode('/', $rel), fn($p) => $p !== ''));
    return implode('/', $segments);
}

function sanitize_rel(string $p): string
{
    $p = str_replace("\0", '', $p);
    $p = preg_replace('#/+#', '/', $p);
    $parts = [];
    foreach (explode('/', trim($p, '/')) as $seg) {
        if ($seg === '' || $seg === '.')
            continue;
        if ($seg === '..')
            continue;
        $parts[] = $seg;
    }
    return implode('/', $parts);
}

function format_size(int $bytes, array $t): string
{
    if ($bytes >= 1073741824) {
        return number_format($bytes / 1073741824, 2) . ' ' . $t['gb'];
    } elseif ($bytes >= 1048576) {
        return number_format($bytes / 1048576, 2) . ' ' . $t['mb'];
    } elseif ($bytes >= 1024) {
        return number_format($bytes / 1024, 2) . ' ' . $t['kb'];
    }
    return $bytes . ' ' . $t['b'];
}

function dir_file_count(string $dir): int
{
    $items = @scandir($dir);
    if ($items === false) return 0;
    return count(array_filter($items, fn($f) => $f !== '.' && $f !== '..' && !str_starts_with($f, '.')));
}

function pluralize(int $n, array $t): string
{
    if ($GLOBALS['LANG'] === 'ru') {
        $mod10 = $n % 10;
        $mod100 = $n % 100;
        if ($mod10 === 1 && $mod100 !== 11) return $t['item'];
        if ($mod10 >= 2 && $mod10 <= 4 && ($mod100 < 10 || $mod100 >= 20)) return $t['items_few'];
        return $t['items_many'];
    }
    return $n === 1 ? $t['item'] : $t['items_many'];
}

/**
 * Generate download URL for file
 * For admin mode: first folder = subdomain, link points to subdomain.domain/path
 * For files in root of admin: link points to admin.domain/files/filename
 */
function get_download_url(string $rel, ?string $subdomain, string $domain, string $protocol, string $mode): string
{
    if ($mode === 'admin') {
        // Split path: first part = subdomain, rest = file path
        $parts = explode('/', $rel, 2);
        $firstFolder = $parts[0];
        $restPath = $parts[1] ?? '';

        if ($restPath !== '') {
            // File is inside a subdomain folder -> link to subdomain
            return "{$protocol}://{$firstFolder}.{$domain}/" . url_path($restPath);
        } else {
            // File is in root /data -> link to admin/files/
            $adminSubdomain = getenv('ADMIN_SUBDOMAIN') ?: 'admin';
            return "{$protocol}://{$adminSubdomain}.{$domain}/files/" . url_path($rel);
        }
    } else {
        return "{$protocol}://{$subdomain}.{$domain}/" . url_path($rel);
    }
}

$rel = isset($_GET['path']) ? sanitize_rel((string) $_GET['path']) : '';
$abs = rtrim($BASE . ($rel === '' ? '' : '/' . $rel), '/');

if (!is_dir($abs)) {
    http_response_code(404);
    echo "<h1>{$t['not_found']}</h1><p>{$t['path_not_found']}: " . h($rel) . "</p>";
    exit;
}

$sort = $_GET['sort'] ?? 'name';
$order = $_GET['order'] ?? 'asc';
$sort = in_array($sort, ['name', 'size', 'count', 'mtime'], true) ? $sort : 'name';
$order = ($order === 'desc') ? 'desc' : 'asc';

$entries = [];
try {
    $dir = new DirectoryIterator($abs);
    foreach ($dir as $fi) {
        if ($fi->isDot())
            continue;
        $name = $fi->getFilename();
        if (str_starts_with($name, '.'))
            continue;
        $full = $abs . '/' . $name;
        $mtime = @filemtime($full) ?: 0;

        if ($fi->isDir()) {
            $entries[] = [
                'type' => 'dir',
                'name' => $name,
                'mtime' => $mtime,
                'count' => dir_file_count($full),
            ];
        } elseif ($fi->isFile()) {
            $entries[] = [
                'type' => 'file',
                'name' => $name,
                'mtime' => $mtime,
                'size' => @filesize($full) ?: 0,
            ];
        }
    }
} catch (Throwable $e) {
    http_response_code(500);
    echo "<h1>{$t['error']}</h1><pre>" . h($e->getMessage()) . "</pre>";
    exit;
}

usort($entries, function (array $a, array $b) use ($sort, $order): int {
    if ($a['type'] !== $b['type']) {
        return $a['type'] === 'dir' ? -1 : 1;
    }
    $cmp = 0;
    if ($sort === 'name') {
        $cmp = strcasecmp($a['name'], $b['name']);
    } elseif ($sort === 'size') {
        $sa = $a['type'] === 'file' ? ($a['size'] ?? 0) : -1;
        $sb = $b['type'] === 'file' ? ($b['size'] ?? 0) : -1;
        $cmp = $sa <=> $sb;
    } elseif ($sort === 'count') {
        $ca = $a['type'] === 'dir' ? ($a['count'] ?? 0) : -1;
        $cb = $b['type'] === 'dir' ? ($b['count'] ?? 0) : -1;
        $cmp = $ca <=> $cb;
    } elseif ($sort === 'mtime') {
        $cmp = ($a['mtime'] ?? 0) <=> ($b['mtime'] ?? 0);
    }
    return $order === 'desc' ? -$cmp : $cmp;
});

function sort_link(string $label, string $key, string $currentSort, string $currentOrder, string $rel): string
{
    $nextOrder = ($currentSort === $key && $currentOrder === 'asc') ? 'desc' : 'asc';
    $q = http_build_query(['path' => $rel, 'sort' => $key, 'order' => $nextOrder]);
    $arrow = $currentSort === $key ? ($currentOrder === 'asc' ? '↑' : '↓') : '';
    return '<a href="?' . $q . '">' . h($label) . ' ' . $arrow . '</a>';
}

$parentRel = '';
if ($rel !== '') {
    $parentRel = dirname($rel);
    if ($parentRel === '.' || $parentRel === DIRECTORY_SEPARATOR)
        $parentRel = '';
}

$pageTitle = $MODE === 'admin' ? $t['admin_panel'] : h($SUBDOMAIN);
$htmlLang = $LANG === 'ru' ? 'ru' : 'en';
?>
<!doctype html>
<html lang="<?= $htmlLang ?>">
<head>
    <meta charset="utf-8">
    <title><?= $pageTitle ?>: /<?= h($rel) ?></title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        * { box-sizing: border-box; }
        html, body { height: 100%; }
        body {
            font: 16px/1.5 system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Arial, sans-serif;
            margin: 0;
            background: #fafafa;
        }
        .container {
            max-width: 1000px;
            margin: 32px auto;
            padding: 0 20px;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            table-layout: fixed;
        }
        th, td {
            padding: 12px 14px;
            border-bottom: 1px solid #eee;
            vertical-align: middle;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        th a { text-decoration: none; color: #000; }
        .name a { color: #0068c9; text-decoration: none; }
        .name a:hover { text-decoration: underline; }
        .meta { color: #666; }
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border: 1px solid #999;
            border-radius: 999px;
            font-size: 14px;
            color: #444;
        }
        .badge.admin { background: #fee; border-color: #c00; color: #900; }
        .badge.protected { background: #ffc; border-color: #aa0; color: #660; }
        .header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 16px;
            gap: 16px;
            flex-wrap: wrap;
        }
        .header-left {
            display: flex;
            align-items: center;
            gap: 16px;
        }
        .path {
            font-weight: 600;
            font-size: 18px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        col.col-name { width: auto; }
        col.col-size { width: 110px; }
        col.col-count { width: 100px; }
        col.col-mod { width: 160px; }
        col.col-action { width: 170px; }
        thead th:nth-child(2),
        thead th:nth-child(3),
        thead th:nth-child(4),
        tbody td:nth-child(2),
        tbody td:nth-child(3),
        tbody td:nth-child(4) {
            text-align: right;
            font-variant-numeric: tabular-nums;
        }
        .copy-btn {
            padding: 6px 14px;
            font-size: 14px;
            background: #0068c9;
            color: #fff;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            transition: background 0.2s;
            white-space: nowrap;
        }
        .copy-btn:hover { background: #0050a0; }
        .copy-btn:active { background: #003d7a; }
        .copy-btn.copied { background: #28a745; }
        .toast {
            position: fixed;
            bottom: 24px;
            left: 50%;
            transform: translateX(-50%);
            background: #333;
            color: #fff;
            padding: 14px 28px;
            border-radius: 10px;
            font-size: 15px;
            opacity: 0;
            transition: opacity 0.3s;
            z-index: 1000;
        }
        .toast.show { opacity: 1; }
        .back-link {
            display: inline-block;
            margin-bottom: 20px;
            font-size: 16px;
            color: #0068c9;
            text-decoration: none;
        }
        .back-link:hover { text-decoration: underline; }
        @media (max-width: 800px) {
            col.col-count, th:nth-child(3), td:nth-child(3) { display: none; }
            col.col-mod, th:nth-child(4), td:nth-child(4) { display: none; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="header-left">
                <div class="path">/<?= h($rel) ?></div>
                <?php if ($MODE === 'admin'): ?>
                <span class="badge admin"><?= h($t['admin_badge']) ?></span>
                <?php elseif ($MODE === 'protected'): ?>
                <span class="badge protected"><?= h($t['protected_badge']) ?></span>
                <?php endif; ?>
            </div>
            <div class="badge"><?= count($entries) ?> <?= pluralize(count($entries), $t) ?></div>
        </div>

        <?php if ($rel !== ''): ?>
            <a class="back-link" href="?<?= http_build_query(['path' => $parentRel, 'sort' => $sort, 'order' => $order]) ?>">← <?= h($t['back']) ?></a>
        <?php endif; ?>

        <table>
            <colgroup>
                <col class="col-name">
                <col class="col-size">
                <col class="col-count">
                <col class="col-mod">
                <col class="col-action">
            </colgroup>
            <thead>
                <tr>
                    <th class="name"><?= sort_link($t['name'], 'name', $sort, $order, $rel) ?></th>
                    <th><?= sort_link($t['size'], 'size', $sort, $order, $rel) ?></th>
                    <th><?= sort_link($t['files_in_dir'], 'count', $sort, $order, $rel) ?></th>
                    <th><?= sort_link($t['modified'], 'mtime', $sort, $order, $rel) ?></th>
                    <th><?= h($t['action']) ?></th>
                </tr>
            </thead>
            <tbody>
            <?php foreach ($entries as $e):
                $childRel = ltrim($rel . '/' . $e['name'], '/');
                $modified = $e['mtime'] ? date('d.m.Y H:i', $e['mtime']) : '';

                if ($e['type'] === 'dir'):
            ?>
                <tr>
                    <td class="name">📁 <a href="?<?= http_build_query(['path' => $childRel, 'sort' => $sort, 'order' => $order]) ?>"><?= h($e['name']) ?></a></td>
                    <td class="meta">—</td>
                    <td class="meta"><?= (int)($e['count'] ?? 0) ?></td>
                    <td class="meta"><?= h($modified) ?></td>
                    <td></td>
                </tr>
            <?php else:
                $size = format_size((int)($e['size'] ?? 0), $t);
                $downloadUrl = get_download_url($childRel, $SUBDOMAIN, $BASE_DOMAIN, $PROTOCOL, $MODE);
            ?>
                <tr>
                    <td class="name">📄 <?= h($e['name']) ?></td>
                    <td class="meta"><?= h($size) ?></td>
                    <td class="meta">—</td>
                    <td class="meta"><?= h($modified) ?></td>
                    <td>
                        <button class="copy-btn" data-url="<?= h($downloadUrl) ?>" onclick="copyLink(this)"><?= h($t['copy']) ?></button>
                    </td>
                </tr>
            <?php endif; endforeach; ?>
            </tbody>
        </table>
    </div>

    <div class="toast" id="toast"><?= h($t['link_copied']) ?></div>

    <script>
    const COPIED_TEXT = <?= json_encode($t['copied']) ?>;
    const COPY_TEXT = <?= json_encode($t['copy']) ?>;

    function copyLink(btn) {
        const url = btn.dataset.url;
        navigator.clipboard.writeText(url).then(() => {
            btn.textContent = COPIED_TEXT;
            btn.classList.add('copied');
            showToast();
            setTimeout(() => {
                btn.textContent = COPY_TEXT;
                btn.classList.remove('copied');
            }, 2000);
        }).catch(() => {
            const textarea = document.createElement('textarea');
            textarea.value = url;
            document.body.appendChild(textarea);
            textarea.select();
            document.execCommand('copy');
            document.body.removeChild(textarea);
            btn.textContent = COPIED_TEXT;
            btn.classList.add('copied');
            showToast();
            setTimeout(() => {
                btn.textContent = COPY_TEXT;
                btn.classList.remove('copied');
            }, 2000);
        });
    }

    function showToast() {
        const toast = document.getElementById('toast');
        toast.classList.add('show');
        setTimeout(() => toast.classList.remove('show'), 2000);
    }
    </script>
</body>
</html>
