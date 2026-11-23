#!/bin/bash
# review.html, the page only the human reads.
#
# Layout of the generated file (mirrored by the Windows generator):
#   REPORT_HEAD_OPEN, REPORT_CSP, REPORT_HEAD   static text
#   <tbody id="rows" data-token="TOKEN" data-secret="SECRET">
#                                               the review token (8 hex digits)
#                                               and the selection secret (32);
#                                               the secret exists only here and
#                                               in the manifest, never on stdout
#   one REPORT_ROW line per item                the only place item data goes
#   REPORT_TAIL                                 static text, holds the script
# Item data is never written into the script: the page reads it from the
# table. NAME and FOLDER are HTML-escaped (& < > " ' become &amp; &lt; &gt;
# &quot; &#39;), every other value in a row is digits or a fixed group id.

readonly REPORT_CSP="<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\">"
readonly REPORT_ROW='<tr data-id="%s" data-size="%s" data-mtime="%s" data-group="%s"><td class="pick"><input type="checkbox" id="item-%s"></td><td class="name" dir="auto"><label for="item-%s">%s</label></td><td class="folder" dir="auto">%s</td><td class="size"></td><td class="date"></td><td class="group"></td></tr>\n'

readonly REPORT_HEAD_OPEN='<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">'

readonly REPORT_HEAD='<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>Disk cleanup review</title>
<style>
:root {
  --paper: #f4efe6; --card: #fffdf8; --ink: #1f1b16; --muted: #62594e; --rule: #d8cfc0;
  --accent: #0f5c4d; --accent-ink: #ffffff; --large: #6b3a8c; --old: #8a4b00;
  --picked: #e4f0ea; --focus: #1d4ed8; --shadow: 0 10px 30px rgba(31, 27, 22, 0.12);
  --display: ui-serif, "New York", "Iowan Old Style", Georgia, serif;
  --text: -apple-system, "Segoe UI", system-ui, sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root {
    --paper: #14130f; --card: #1d1b16; --ink: #f1ece2; --muted: #aaa193; --rule: #3a352c;
    --accent: #62d2b4; --accent-ink: #0b1a16; --large: #cda3e6; --old: #f0b25e;
    --picked: #1b2b25; --focus: #93c5fd; --shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--paper); color: var(--ink); font: 16px/1.5 var(--text); padding-bottom: 7rem; }
.wrap { max-width: 68rem; margin: 0 auto; padding: 0 1.5rem; }
.masthead { padding: 3rem 0 1.5rem; border-bottom: 3px double var(--rule); }
.kicker { margin: 0; font-size: 0.78rem; letter-spacing: 0.16em; text-transform: uppercase; color: var(--accent); font-weight: 700; }
h1 { margin: 0.4rem 0 0.6rem; font: 600 clamp(2rem, 1.2rem + 3vw, 3.4rem)/1.08 var(--display); letter-spacing: -0.01em; max-width: 18ch; }
.lede { margin: 0; max-width: 56ch; color: var(--muted); font-size: 1.05rem; }
.notes { list-style: none; counter-reset: note; margin: 1.75rem 0 0; padding: 0; display: grid; gap: 0.75rem; grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr)); }
.notes li { counter-increment: note; background: var(--card); border: 1px solid var(--rule); border-top: 4px solid var(--accent); padding: 0.9rem 1rem 1rem; font-size: 0.95rem; }
.notes li::before { content: "0" counter(note); display: block; font: 600 1.4rem/1 var(--display); color: var(--accent); margin-bottom: 0.45rem; }
.notes li:first-child { font-weight: 700; }
.notes li:last-child { border-top-color: var(--old); }
.notes li:last-child::before { color: var(--old); }
.tools { display: flex; flex-wrap: wrap; gap: 0.5rem; align-items: center; margin: 2rem 0 0.75rem; }
.tools .gap { flex: 1; }
.chip { font: inherit; font-size: 0.9rem; color: var(--ink); background: transparent; border: 1px solid var(--rule); border-radius: 999px; padding: 0.4rem 0.95rem; cursor: pointer; transition: background-color 150ms, color 150ms, transform 150ms; }
.chip:hover { border-color: var(--ink); }
.chip:active { transform: scale(0.97); }
.chip[aria-pressed="true"] { background: var(--ink); color: var(--paper); border-color: var(--ink); }
.sort { border-radius: 4px; border-style: dashed; }
table { width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--rule); box-shadow: var(--shadow); }
caption, .quiet { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
th { text-align: left; font-size: 0.72rem; letter-spacing: 0.12em; text-transform: uppercase; color: var(--muted); padding: 0.7rem 0.75rem; border-bottom: 2px solid var(--ink); }
td { padding: 0.7rem 0.75rem; border-bottom: 1px solid var(--rule); vertical-align: top; }
tbody tr { transition: background-color 150ms; }
tbody tr:hover { background: var(--paper); }
tbody tr.picked { background: var(--picked); box-shadow: inset 4px 0 0 var(--accent); }
.pick { width: 2.75rem; }
.pick input { width: 1.25rem; height: 1.25rem; margin: 0.15rem 0 0; accent-color: var(--accent); cursor: pointer; }
.name label { font-weight: 600; cursor: pointer; overflow-wrap: anywhere; unicode-bidi: isolate; }
.folder { color: var(--muted); font-size: 0.9rem; overflow-wrap: anywhere; max-width: 22rem; unicode-bidi: isolate; }
.size, .date, th.num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
.size { font: 600 1.05rem/1.4 var(--display); min-width: 7rem; }
.bar { display: block; height: 3px; margin-top: 0.3rem; background: var(--rule); }
.bar i { display: block; height: 100%; width: 100%; background: var(--accent); transform-origin: right; transform: scaleX(var(--share, 0)); }
.date { color: var(--muted); font-size: 0.9rem; }
.tag { display: inline-block; font-size: 0.75rem; font-weight: 700; border: 1px solid currentColor; padding: 0.1rem 0.5rem; white-space: nowrap; }
tr[data-group="large-files"] .tag { color: var(--large); }
tr[data-group="old-downloads"] .tag { color: var(--old); }
.empty, .warn { background: var(--card); border: 1px dashed var(--rule); padding: 1.5rem; margin: 1rem 0; }
.dock { position: fixed; left: 0; right: 0; bottom: 0; background: var(--card); border-top: 2px solid var(--ink); box-shadow: var(--shadow); }
.dock .wrap { display: flex; flex-wrap: wrap; align-items: center; gap: 0.75rem 1.5rem; padding-top: 0.9rem; padding-bottom: 0.9rem; }
#summary { margin: 0; flex: 1; min-width: 12rem; font: 600 1.15rem/1.3 var(--display); }
#saved { margin: 0; flex-basis: 100%; color: var(--accent); font-weight: 600; }
#save { font: inherit; font-weight: 700; color: var(--accent-ink); background: var(--accent); border: 0; border-radius: 4px; padding: 0.8rem 1.6rem; cursor: pointer; transition: transform 150ms, opacity 150ms; }
#save:hover:not(:disabled) { transform: translateY(-1px); }
#save:disabled { opacity: 0.45; cursor: not-allowed; }
:focus-visible { outline: 3px solid var(--focus); outline-offset: 2px; }
[hidden] { display: none !important; }
@media (max-width: 760px) { .group, th.kind { display: none; } .folder { max-width: 10rem; } }
@media (max-width: 560px) { .date, th.when { display: none; } .wrap { padding: 0 1rem; } }
@media (prefers-reduced-motion: reduce) { * { transition: none !important; } }
</style>
</head>
<body>
<header class="masthead"><div class="wrap">
<p class="kicker" data-i18n="kicker">Disk cleanup &middot; Review</p>
<h1 data-i18n="title">Choose what to move to the Trash</h1>
<p class="lede" data-i18n="lede">These are the largest files and the oldest downloads on this Mac. Tick the ones you no longer need.</p>
<ul class="notes">
<li data-i18n="noteSafe">Nothing is deleted from this page.</li>
<li data-i18n="noteFlow">Ticked items are moved to the Trash only after you press Save selection and tell the assistant to continue. Until you empty the Trash, you can put them back.</li>
<li data-i18n="noteCloud">Files in folders synced with iCloud, OneDrive or Dropbox are also removed from the cloud and from your other devices.</li>
</ul>
</div></header>
<main class="wrap">
<div class="tools" role="group" aria-label="Filter and sort" id="tools">
<button type="button" class="chip" data-filter="all" aria-pressed="true" data-i18n="filterAll">All</button>
<button type="button" class="chip" data-filter="large-files" aria-pressed="false" data-i18n="filterLarge">Large files</button>
<button type="button" class="chip" data-filter="old-downloads" aria-pressed="false" data-i18n="filterOld">Old items in Downloads</button>
<span class="gap"></span>
<button type="button" class="chip sort" id="sort" data-i18n="sortDesc">Largest first</button>
</div>
<noscript><p class="warn">This page needs JavaScript to save your selection.</p></noscript>
<table id="list">
<caption data-i18n="caption">Files you can choose to move to the Trash</caption>
<thead><tr>
<th scope="col"><span class="quiet" data-i18n="colPick">Pick</span></th>
<th scope="col" data-i18n="colName">Name</th>
<th scope="col" data-i18n="colFolder">Folder</th>
<th scope="col" class="num" data-i18n="colSize">Size</th>
<th scope="col" class="num when" data-i18n="colDate">Last changed</th>
<th scope="col" class="kind" data-i18n="colGroup">Kind</th>
</tr></thead>'

readonly REPORT_TAIL='</tbody>
</table>
<p class="empty" id="empty" hidden data-i18n="empty">No large files or old downloads were found. There is nothing to choose here.</p>
</main>
<footer class="dock"><div class="wrap">
<p id="summary" role="status" aria-live="polite"></p>
<button type="button" id="save" disabled data-i18n="save">Save selection</button>
<p id="saved" hidden data-i18n="saved">Saved to your Downloads folder as disk-cleanup-selection.json. Now go back to the assistant and tell it to continue.</p>
</div></footer>
<script>
(function () {
  "use strict";
  var TEXT = {
    en: {
      kicker: "Disk cleanup · Review", title: "Choose what to move to the Trash",
      lede: "These are the largest files and the oldest downloads on this Mac. Tick the ones you no longer need.",
      noteSafe: "Nothing is deleted from this page.",
      noteFlow: "Ticked items are moved to the Trash only after you press Save selection and tell the assistant to continue. Until you empty the Trash, you can put them back.",
      noteCloud: "Files in folders synced with iCloud, OneDrive or Dropbox are also removed from the cloud and from your other devices.",
      filterAll: "All", filterLarge: "Large files", filterOld: "Old items in Downloads",
      sortDesc: "Largest first", sortAsc: "Smallest first", caption: "Files you can choose to move to the Trash",
      colPick: "Pick", colName: "Name", colFolder: "Folder", colSize: "Size", colDate: "Last changed", colGroup: "Kind",
      groupLarge: "Large file", groupOld: "Old download", summaryNone: "Nothing ticked yet.",
      summaryOne: "Selected: 1 item, {size}", summary: "Selected: {n} items, {size}",
      summaryHidden: " ({hidden} of them hidden by the filter)", save: "Save selection",
      saved: "Saved to your Downloads folder as disk-cleanup-selection.json. Now go back to the assistant and tell it to continue.",
      empty: "No large files or old downloads were found. There is nothing to choose here."
    },
    id: {
      kicker: "Pembersihan disk · Tinjauan", title: "Pilih yang akan dipindahkan ke Tong Sampah",
      lede: "Ini adalah file terbesar dan unduhan terlama di Mac ini. Centang yang sudah tidak Anda perlukan.",
      noteSafe: "Tidak ada yang dihapus dari halaman ini.",
      noteFlow: "Item yang dicentang baru dipindahkan ke Tong Sampah setelah Anda menekan Simpan pilihan dan meminta asisten untuk melanjutkan. Selama Tong Sampah belum dikosongkan, item masih bisa dikembalikan.",
      noteCloud: "File di folder yang disinkronkan dengan iCloud, OneDrive, atau Dropbox juga terhapus dari cloud dan dari perangkat Anda yang lain.",
      filterAll: "Semua", filterLarge: "File besar", filterOld: "Item lama di Unduhan",
      sortDesc: "Terbesar dulu", sortAsc: "Terkecil dulu", caption: "File yang dapat Anda pilih untuk dipindahkan ke Tong Sampah",
      colPick: "Pilih", colName: "Nama", colFolder: "Folder", colSize: "Ukuran", colDate: "Terakhir diubah", colGroup: "Jenis",
      groupLarge: "File besar", groupOld: "Unduhan lama", summaryNone: "Belum ada yang dicentang.",
      summaryOne: "Dipilih: 1 item, {size}", summary: "Dipilih: {n} item, {size}",
      summaryHidden: " ({hidden} di antaranya tersembunyi oleh filter)", save: "Simpan pilihan",
      saved: "Tersimpan di folder Unduhan sebagai disk-cleanup-selection.json. Sekarang kembali ke asisten dan minta untuk melanjutkan.",
      empty: "Tidak ada file besar atau unduhan lama yang ditemukan. Tidak ada yang perlu dipilih."
    }
  };
  var SELECTION_FILE = "disk-cleanup-selection.json";
  var KB = 1024, MB = KB * 1024, GB = MB * 1024;
  var lang = String(navigator.language || "en").toLowerCase().indexOf("id") === 0 ? "id" : "en";
  var text = TEXT[lang];
  var body = document.getElementById("rows");
  var rows = Array.prototype.slice.call(body.rows);
  var token = body.getAttribute("data-token") || "";
  var secret = body.getAttribute("data-secret") || "";
  var save = document.getElementById("save");
  var sort = document.getElementById("sort");
  var summary = document.getElementById("summary");
  var saved = document.getElementById("saved");
  var descending = true;

  function number(value, digits) {
    return value.toLocaleString(lang, { minimumFractionDigits: digits, maximumFractionDigits: digits });
  }
  function sizeText(bytes) {
    if (bytes >= GB) { return number(bytes / GB, 1) + " GB"; }
    if (bytes >= MB) { return number(bytes / MB, 0) + " MB"; }
    return number(Math.max(1, Math.round(bytes / KB)), 0) + " KB";
  }
  function dateText(seconds) {
    return new Date(seconds * 1000).toLocaleDateString(lang, { year: "numeric", month: "short", day: "numeric" });
  }
  function sizeOf(row) { return Number(row.getAttribute("data-size")) || 0; }
  function boxOf(row) { return row.querySelector("input"); }

  function translate() {
    document.documentElement.lang = lang;
    Array.prototype.forEach.call(document.querySelectorAll("[data-i18n]"), function (node) {
      node.textContent = text[node.getAttribute("data-i18n")];
    });
  }
  function decorate() {
    var largest = rows.reduce(function (most, row) { return Math.max(most, sizeOf(row)); }, 1);
    rows.forEach(function (row) {
      var amount = document.createElement("span"), bar = document.createElement("span");
      var fill = document.createElement("i"), tag = document.createElement("span");
      amount.textContent = sizeText(sizeOf(row));
      bar.className = "bar";
      fill.style.setProperty("--share", String(sizeOf(row) / largest));
      bar.appendChild(fill);
      row.cells[3].appendChild(amount);
      row.cells[3].appendChild(bar);
      row.cells[4].textContent = dateText(Number(row.getAttribute("data-mtime")));
      tag.className = "tag";
      tag.textContent = row.getAttribute("data-group") === "large-files" ? text.groupLarge : text.groupOld;
      row.cells[5].appendChild(tag);
    });
    document.getElementById("empty").hidden = rows.length > 0;
    document.getElementById("list").hidden = rows.length === 0;
    document.getElementById("tools").hidden = rows.length === 0;
  }
  function update() {
    var count = 0, bytes = 0, hidden = 0;
    rows.forEach(function (row) {
      var ticked = boxOf(row).checked;
      row.classList.toggle("picked", ticked);
      if (ticked) { count += 1; bytes += sizeOf(row); }
      if (ticked && row.hidden) { hidden += 1; }
    });
    var line = count === 0 ? text.summaryNone : (count === 1 ? text.summaryOne : text.summary);
    if (hidden > 0) { line += text.summaryHidden; }
    summary.textContent = line.replace("{n}", String(count)).replace("{size}", sizeText(bytes))
      .replace("{hidden}", String(hidden));
    save.disabled = count === 0 || !/^[0-9a-f]{8}$/.test(token) || !/^[0-9a-f]{32}$/.test(secret);
    saved.hidden = true;
  }
  function filter(group) {
    rows.forEach(function (row) {
      row.hidden = group !== "all" && row.getAttribute("data-group") !== group;
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-filter]"), function (chip) {
      chip.setAttribute("aria-pressed", String(chip.getAttribute("data-filter") === group));
    });
    update();
  }
  function reorder() {
    descending = !descending;
    rows.sort(function (a, b) { return descending ? sizeOf(b) - sizeOf(a) : sizeOf(a) - sizeOf(b); });
    rows.forEach(function (row) { body.appendChild(row); });
    sort.textContent = descending ? text.sortDesc : text.sortAsc;
  }
  function download() {
    var ids = rows.filter(function (row) { return boxOf(row).checked; })
      .map(function (row) { return Number(row.getAttribute("data-id")); })
      .sort(function (a, b) { return a - b; });
    if (ids.length === 0) { return; }
    var content = "{\"token\":\"" + token + "\",\"secret\":\"" + secret + "\",\"ids\":[" + ids.join(",") + "]}";
    var anchor = document.createElement("a");
    var address = URL.createObjectURL(new Blob([content], { type: "application/json" }));
    anchor.href = address;
    anchor.download = SELECTION_FILE;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    setTimeout(function () { URL.revokeObjectURL(address); }, 1000);
    saved.hidden = false;
  }

  translate();
  decorate();
  update();
  body.addEventListener("change", update);
  Array.prototype.forEach.call(document.querySelectorAll("[data-filter]"), function (chip) {
    chip.addEventListener("click", function () { filter(chip.getAttribute("data-filter")); });
  });
  sort.addEventListener("click", reorder);
  save.addEventListener("click", download);
}());
</script>
</body>
</html>'

# Reads manifest item lines and prints one REPORT_ROW per valid line.
report_rows() {
  REVIEW_HOME=$HOME_PHYS awk -F '\t' -v row="$REPORT_ROW" \
    -v large="$REVIEW_GROUP_LARGE" -v old="$REVIEW_GROUP_DOWNLOADS" '
    function escaped(value) {
      gsub(/&/, "\\&amp;", value)
      gsub(/</, "\\&lt;", value)
      gsub(/>/, "\\&gt;", value)
      gsub(/"/, "\\&quot;", value)
      gsub(/\047/, "\\&#39;", value)
      return value
    }
    BEGIN { home = ENVIRON["REVIEW_HOME"] }
    NF != 6 || $1 !~ /^[0-9]+$/ || $2 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ { next }
    ($5 != large && $5 != old) || index($6, home "/") != 1 { next }
    {
      relative = substr($6, length(home) + 1)
      name = relative
      sub(/^.*\//, "", name)
      folder = "~" substr(relative, 1, length(relative) - length(name) - 1)
      printf row, $1, $2, $4, $5, $1, $1, escaped(name), escaped(folder)
    }'
}

# report_write TOKEN SECRET ITEMS
report_write() {
  is_token "$1" && is_secret "$2" && review_file_is_writable "$REVIEW_REPORT" || return 1
  (
    umask 077
    {
      printf '%s\n%s\n%s\n<tbody id="rows" data-token="%s" data-secret="%s">\n' \
        "$REPORT_HEAD_OPEN" "$REPORT_CSP" "$REPORT_HEAD" "$1" "$2"
      [ -z "$3" ] || printf '%s\n' "$3" | report_rows
      printf '%s\n' "$REPORT_TAIL"
    } > "$REVIEW_REPORT"
  ) 2> /dev/null || return 1
  chmod "$PRIVATE_FILE_MODE" "$REVIEW_REPORT" 2> /dev/null
}
