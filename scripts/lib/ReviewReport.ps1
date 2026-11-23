# The review report: one self-contained local page that only the user sees.
# Everything in the three static parts below is constant text. Item data appears in
# exactly one shape: an HTML table row built by ConvertTo-ReviewRow, where every
# string that came from the disk goes through ConvertTo-HtmlText. Item data is never
# written into the script block.

$script:HTML_ESCAPES = @(
    @('&', '&amp;'),
    @('<', '&lt;'),
    @('>', '&gt;'),
    @('"', '&quot;'),
    @("'", '&#39;')
)
$script:SIZE_UNITS = @('B', 'KB', 'MB', 'GB', 'TB')
$script:SIZE_UNIT_STEP = 1024
$script:SIZE_NUMBER_FORMAT = '0.0'
$script:REPORT_DATE_FORMAT = 'yyyy-MM-dd'
$script:HOME_DISPLAY_PREFIX = '~'
$script:REPORT_GROUP_TEXT = @{
    'large-files'   = @{ Key = 'gLarge'; Label = 'Large files' }
    'old-downloads' = @{ Key = 'gOld'; Label = 'Old items in Downloads' }
}

$script:REPORT_HEAD = @'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<title>Disk cleanup review</title>
<style>
:root{--paper:#f5efe3;--card:#fffaf0;--ink:#1f1b14;--soft:#574f43;--line:#d6cab4;--mark:#0a5a52;--mark-ink:#ffffff;--warn:#8a3b12;--stripe:#efe6d3}
@media (prefers-color-scheme:dark){:root{--paper:#16140f;--card:#201d16;--ink:#efe8d8;--soft:#bdb4a1;--line:#3b362b;--mark:#7ad6c8;--mark-ink:#0c1614;--warn:#f0b48a;--stripe:#1c1912}}
*{box-sizing:border-box}
body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 "Segoe UI",system-ui,-apple-system,sans-serif}
main{max-width:1100px;margin:0 auto;padding:44px 24px 150px}
.kicker{margin:0;font-size:12px;font-weight:700;letter-spacing:.16em;text-transform:uppercase;color:var(--mark)}
h1{margin:6px 0 10px;font:700 clamp(28px,4.4vw,46px)/1.08 Georgia,"Times New Roman",serif;letter-spacing:-.01em}
.lead{max-width:62ch;margin:0 0 24px;color:var(--soft)}
.notes{list-style:none;margin:0 0 32px;padding:0;display:grid;gap:12px;grid-template-columns:repeat(auto-fit,minmax(250px,1fr))}
.notes li{padding:14px 16px;background:var(--card);border:1px solid var(--line);border-left:5px solid var(--mark);border-radius:2px 12px 12px 2px}
.notes li.warn{border-left-color:var(--warn)}
.tools{display:flex;flex-wrap:wrap;gap:14px;align-items:flex-end;margin:0 0 14px}
.tools label{display:block;font-size:13px;font-weight:600;color:var(--soft)}
select,button{font:inherit;color:inherit;border-radius:8px;border:1px solid var(--line);background:var(--card);padding:9px 14px;min-height:42px}
button{cursor:pointer;font-weight:600}
button:hover,select:hover{border-color:var(--mark)}
:focus-visible{outline:3px solid var(--mark);outline-offset:2px}
.sheet{background:var(--card);border:1px solid var(--line);border-radius:14px;overflow-x:auto;box-shadow:0 18px 40px -28px rgba(0,0,0,.55)}
table{width:100%;border-collapse:collapse;font-variant-numeric:tabular-nums}
th{padding:12px 14px;text-align:left;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--soft);background:var(--card);border-bottom:2px solid var(--line)}
td{padding:10px 14px;border-bottom:1px solid var(--line);vertical-align:top}
tbody tr:nth-child(even){background:var(--stripe)}
tbody tr:hover{box-shadow:inset 4px 0 0 var(--mark)}
tbody tr.on{box-shadow:inset 4px 0 0 var(--mark)}
tbody tr.on .name{font-weight:700}
.name,.folder{overflow-wrap:anywhere;unicode-bidi:isolate}
.name label{cursor:pointer}
.folder{color:var(--soft);font-size:14px}
.num{text-align:right;white-space:nowrap}
td.num{font-weight:600}
.when,.group{white-space:nowrap;color:var(--soft);font-size:14px}
input[type=checkbox]{width:22px;height:22px;accent-color:var(--mark);cursor:pointer}
.empty{padding:28px;text-align:center;color:var(--soft)}
.dock{position:fixed;left:0;right:0;bottom:0;background:var(--card);border-top:3px solid var(--ink);box-shadow:0 -14px 30px -20px rgba(0,0,0,.6)}
.dock div{max-width:1100px;margin:0 auto;padding:14px 24px;display:flex;flex-wrap:wrap;gap:12px 20px;align-items:center;justify-content:space-between}
.dock p{margin:0}
#summary{font:700 20px/1.2 Georgia,"Times New Roman",serif}
#saved{flex-basis:100%;font-size:14px}
#save{background:var(--mark);color:var(--mark-ink);border-color:var(--mark);padding:11px 22px}
#save:disabled{opacity:.45;cursor:not-allowed}
.vh{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
[hidden]{display:none!important}
@media (max-width:720px){.group,.when{display:none}main{padding:28px 14px 170px}}
@media (prefers-reduced-motion:no-preference){tbody tr,button,select{transition:box-shadow .15s,border-color .15s}}
</style>
</head>
'@

$script:REPORT_INTRO = @'
<main>
<header>
<p class="kicker" data-t="kicker">Disk cleanup</p>
<h1 data-t="title">Choose what you no longer need</h1>
<p class="lead" data-t="lead">This list was made on your computer and stays on your computer. The assistant cannot see file names, only how many items you pick and their total size.</p>
<ul class="notes">
<li data-t="n1">Nothing is deleted from this page. Ticking a box only marks an item.</li>
<li data-t="n2">Ticked items are moved to the Recycle Bin only after you press Save selection and tell the assistant to continue. You can still restore them from the Recycle Bin.</li>
<li class="warn" data-t="n3">Careful with synced folders: a file inside OneDrive, iCloud or Dropbox is also removed from the cloud and from your other devices.</li>
</ul>
</header>
<noscript><p class="empty">This page needs JavaScript to save your selection.</p></noscript>
<div class="tools">
<div><label for="filter" data-t="show">Show</label>
<select id="filter">
<option value="" data-t="all">Everything</option>
<option value="large-files" data-t="gLarge">Large files</option>
<option value="old-downloads" data-t="gOld">Old items in Downloads</option>
</select></div>
<button type="button" id="order" data-t="orderDown">Order: largest first</button>
</div>
<div class="sheet">
<table id="list">
<caption class="vh" data-t="caption">Files you may want to move to the Recycle Bin</caption>
<thead><tr>
<th scope="col" data-t="hPick">Pick</th>
<th scope="col" data-t="hName">Name</th>
<th scope="col" data-t="hFolder">Folder</th>
<th scope="col" class="num" data-t="hSize">Size</th>
<th scope="col" class="when" data-t="hDate">Last changed</th>
<th scope="col" class="group" data-t="hGroup">Group</th>
</tr></thead>
<tbody id="rows">
'@

$script:REPORT_TAIL = @'
</tbody>
</table>
<p class="empty" id="empty" hidden data-t="empty">No large files or old downloads were found. There is nothing to choose.</p>
</div>
</main>
<footer class="dock"><div>
<p id="summary" aria-live="polite"></p>
<button type="button" id="save" disabled data-t="save">Save selection</button>
<p id="saved" role="status" hidden data-t="saved">Saved to your Downloads folder as disk-cleanup-selection.json. Now tell the assistant to continue.</p>
</div></footer>
<script>
(function () {
  'use strict';
  var text = {
    en: {
      kicker: 'Disk cleanup',
      title: 'Choose what you no longer need',
      lead: 'This list was made on your computer and stays on your computer. The assistant cannot see file names, only how many items you pick and their total size.',
      n1: 'Nothing is deleted from this page. Ticking a box only marks an item.',
      n2: 'Ticked items are moved to the Recycle Bin only after you press Save selection and tell the assistant to continue. You can still restore them from the Recycle Bin.',
      n3: 'Careful with synced folders: a file inside OneDrive, iCloud or Dropbox is also removed from the cloud and from your other devices.',
      show: 'Show', all: 'Everything', gLarge: 'Large files', gOld: 'Old items in Downloads',
      orderDown: 'Order: largest first', orderUp: 'Order: smallest first',
      caption: 'Files you may want to move to the Recycle Bin',
      hPick: 'Pick', hName: 'Name', hFolder: 'Folder', hSize: 'Size', hDate: 'Last changed', hGroup: 'Group',
      empty: 'No large files or old downloads were found. There is nothing to choose.',
      summary: 'Selected: {n} items, {s}', unseen: ' ({n} of them hidden by the filter)', save: 'Save selection',
      saved: 'Saved to your Downloads folder as disk-cleanup-selection.json. Now tell the assistant to continue.'
    },
    id: {
      kicker: 'Pembersihan disk',
      title: 'Pilih yang sudah tidak Anda perlukan',
      lead: 'Daftar ini dibuat di komputer Anda dan tetap di komputer Anda. Asisten tidak dapat melihat nama file, hanya jumlah item yang Anda pilih dan total ukurannya.',
      n1: 'Tidak ada yang dihapus dari halaman ini. Mencentang kotak hanya menandai item.',
      n2: 'Item yang dicentang baru dipindahkan ke Recycle Bin setelah Anda menekan Simpan pilihan dan meminta asisten untuk melanjutkan. Anda masih bisa memulihkannya dari Recycle Bin.',
      n3: 'Hati-hati dengan folder yang disinkronkan: file di dalam OneDrive, iCloud, atau Dropbox juga terhapus dari cloud dan dari perangkat Anda yang lain.',
      show: 'Tampilkan', all: 'Semua', gLarge: 'File besar', gOld: 'Item lama di Downloads',
      orderDown: 'Urutan: terbesar dulu', orderUp: 'Urutan: terkecil dulu',
      caption: 'File yang mungkin ingin Anda pindahkan ke Recycle Bin',
      hPick: 'Pilih', hName: 'Nama', hFolder: 'Folder', hSize: 'Ukuran', hDate: 'Terakhir diubah', hGroup: 'Kelompok',
      empty: 'Tidak ditemukan file besar atau unduhan lama. Tidak ada yang perlu dipilih.',
      summary: 'Dipilih: {n} item, {s}', unseen: ' ({n} di antaranya tersembunyi oleh filter)', save: 'Simpan pilihan',
      saved: 'Tersimpan di folder Downloads sebagai disk-cleanup-selection.json. Sekarang minta asisten untuk melanjutkan.'
    }
  };
  var language = String(navigator.language || 'en').toLowerCase().indexOf('id') === 0 ? 'id' : 'en';
  var words = text[language];
  document.documentElement.lang = language;
  var marked = document.querySelectorAll('[data-t]');
  for (var i = 0; i < marked.length; i += 1) {
    var word = words[marked[i].getAttribute('data-t')];
    if (word) { marked[i].textContent = word; }
  }
  var token = String(document.body.getAttribute('data-token'));
  var secret = String(document.body.getAttribute('data-secret'));
  var valid = /^[0-9a-f]{8}$/.test(token) && /^[0-9a-f]{32}$/.test(secret);
  var body = document.getElementById('rows');
  var rows = Array.prototype.slice.call(body.getElementsByTagName('tr'));
  var filter = document.getElementById('filter');
  var order = document.getElementById('order');
  var save = document.getElementById('save');
  var summary = document.getElementById('summary');
  var saved = document.getElementById('saved');
  var largestFirst = true;

  function box(row) { return row.getElementsByTagName('input')[0]; }
  function size(row) { return Number(row.getAttribute('data-size')); }
  function picked() { return rows.filter(function (row) { return box(row).checked; }); }
  function human(bytes) {
    var units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit += 1; }
    return (unit === 0 ? String(value) : value.toFixed(1)) + ' ' + units[unit];
  }
  function refresh() {
    var chosen = picked();
    var total = 0;
    var unseen = 0;
    rows.forEach(function (row) { row.className = box(row).checked ? 'on' : ''; });
    chosen.forEach(function (row) {
      total += size(row);
      if (row.hidden) { unseen += 1; }
    });
    var line = words.summary.replace('{n}', String(chosen.length)).replace('{s}', human(total));
    if (unseen > 0) { line += words.unseen.replace('{n}', String(unseen)); }
    summary.textContent = line;
    save.disabled = chosen.length === 0;
    if (!valid) { save.disabled = true; }
    saved.hidden = true;
  }
  if (rows.length === 0) {
    document.getElementById('list').hidden = true;
    document.getElementById('empty').hidden = false;
  }
  body.addEventListener('change', refresh);
  filter.addEventListener('change', function () {
    rows.forEach(function (row) {
      row.hidden = filter.value !== '' && row.getAttribute('data-group') !== filter.value;
    });
    refresh();
  });
  order.addEventListener('click', function () {
    largestFirst = !largestFirst;
    order.textContent = largestFirst ? words.orderDown : words.orderUp;
    rows.sort(function (a, b) { return largestFirst ? size(b) - size(a) : size(a) - size(b); });
    rows.forEach(function (row) { body.appendChild(row); });
  });
  save.addEventListener('click', function () {
    var ids = picked().map(function (row) { return parseInt(row.getAttribute('data-id'), 10); });
    if (ids.length === 0 || !valid) { return; }
    ids.sort(function (a, b) { return a - b; });
    var content = '{"token":"' + token + '","secret":"' + secret + '","ids":[' + ids.join(',') + ']}';
    var link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([content], { type: 'application/json' }));
    link.download = 'disk-cleanup-selection.json';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    saved.hidden = false;
  });
  refresh();
}());
</script>
</body>
</html>
'@

# The one escaping rule of the report: the five characters that can change the
# meaning of HTML text or of a quoted attribute are replaced, the ampersand first.
function ConvertTo-HtmlText {
    param([string]$Text)
    $escaped = [string]$Text
    foreach ($pair in $script:HTML_ESCAPES) {
        $escaped = $escaped.Replace([string]$pair[0], [string]$pair[1])
    }
    return $escaped
}

function Format-ByteSize {
    param([long]$Bytes)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $value = [double]$Bytes
    $unit = 0
    while (($value -ge $script:SIZE_UNIT_STEP) -and ($unit -lt ($script:SIZE_UNITS.Count - 1))) {
        $value = $value / $script:SIZE_UNIT_STEP
        $unit += 1
    }
    if ($unit -eq 0) { return ($Bytes.ToString($culture) + ' ' + $script:SIZE_UNITS[0]) }
    return ($value.ToString($script:SIZE_NUMBER_FORMAT, $culture) + ' ' + $script:SIZE_UNITS[$unit])
}

# Manifest paths always use the backslash. The path is cut by hand because the .NET
# path helpers reject or reinterpret characters this code must be able to print.
function Get-ReviewLeafName {
    param([string]$Path)
    return $Path.Substring($Path.LastIndexOf('\') + 1)
}

# The folder of an item, shown relative to the user profile with a ~ prefix.
function Get-ReviewDisplayFolder {
    param([string]$Path, [string]$HomeRoot)
    $cut = $Path.LastIndexOf('\')
    if ($cut -lt 0) { return $script:HOME_DISPLAY_PREFIX }
    $parent = $Path.Substring(0, $cut)
    $root = $HomeRoot.TrimEnd('\')
    if (-not $parent.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) { return $script:HOME_DISPLAY_PREFIX }
    return ($script:HOME_DISPLAY_PREFIX + $parent.Substring($root.Length))
}

function Format-ReviewDate {
    param([long]$Ticks)
    $stamp = New-Object -TypeName System.DateTime -ArgumentList $Ticks, ([System.DateTimeKind]::Utc)
    return $stamp.ToLocalTime().ToString($script:REPORT_DATE_FORMAT, [System.Globalization.CultureInfo]::InvariantCulture)
}

# One table row per item. Numbers are written from typed values, the group comes
# from a fixed table, and the two strings that come from the disk (name and folder)
# are escaped and placed in element text only. Their cells set their own text
# direction, so a right-to-left name cannot reorder the cells next to it. Only the
# checkbox and the label around the name tick a row.
function ConvertTo-ReviewRow {
    param($Item, [string]$HomeRoot)
    $group = $script:REPORT_GROUP_TEXT[[string]$Item.Group]
    if ($null -eq $group) { throw 'unknown review group' }
    $id = ([int]$Item.Id).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $bytes = ([long]$Item.Size).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    $name = ConvertTo-HtmlText -Text (Get-ReviewLeafName -Path ([string]$Item.Path))
    $folder = ConvertTo-HtmlText -Text (Get-ReviewDisplayFolder -Path ([string]$Item.Path) -HomeRoot $HomeRoot)
    $cells = @(
        ('<tr data-id="' + $id + '" data-size="' + $bytes + '" data-group="' + (ConvertTo-HtmlText -Text ([string]$Item.Group)) + '">'),
        ('<td><input type="checkbox" id="pick' + $id + '"></td>'),
        ('<td class="name" dir="auto"><label for="pick' + $id + '">' + $name + '</label></td>'),
        ('<td class="folder" dir="auto">' + $folder + '</td>'),
        ('<td class="num">' + (ConvertTo-HtmlText -Text (Format-ByteSize -Bytes ([long]$Item.Size))) + '</td>'),
        ('<td class="when">' + (ConvertTo-HtmlText -Text (Format-ReviewDate -Ticks ([long]$Item.MtimeTicks))) + '</td>'),
        ('<td class="group" data-t="' + $group['Key'] + '">' + $group['Label'] + '</td></tr>')
    )
    return ($cells -join '')
}

# The token and the selection secret are written as attributes of the body; both
# are checked to be plain hex first, and the page checks them again when it reads them.
function Get-ReviewReportHtml {
    param([string]$Token, [string]$Secret, [object[]]$Items = @(), [string]$HomeRoot)
    if ($Token -cnotmatch $script:TOKEN_PATTERN) { Invoke-CleanupFailure -Code 'INTERNAL' }
    if ($Secret -cnotmatch $script:REVIEW_SECRET_PATTERN) { Invoke-CleanupFailure -Code 'INTERNAL' }
    $lineFeed = [string][char]10
    $builder = New-Object -TypeName System.Text.StringBuilder
    [void]$builder.Append($script:REPORT_HEAD).Append($lineFeed)
    [void]$builder.Append('<body data-token="' + $Token + '" data-secret="' + $Secret + '">').Append($lineFeed)
    [void]$builder.Append($script:REPORT_INTRO).Append($lineFeed)
    foreach ($item in $Items) {
        [void]$builder.Append((ConvertTo-ReviewRow -Item $item -HomeRoot $HomeRoot)).Append($lineFeed)
    }
    [void]$builder.Append($script:REPORT_TAIL).Append($lineFeed)
    return $builder.ToString()
}
