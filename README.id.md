# disk-cleanup

[English](README.md) | **Bahasa Indonesia**

Agent Skill yang membuat asisten AI kamu (Claude Code, Codex CLI, Cursor, Gemini CLI, dan lainnya) bisa
mengosongkan ruang penyimpanan di macOS dan Windows tanpa pernah melihat file kamu.

Kamu cukup bilang "laptop saya penuh". Asisten menjalankan satu skrip, menampilkan tabel berisi apa saja
yang bisa dibersihkan beserta ukurannya, menanyakan mana yang kamu mau, lalu membersihkan yang kamu
pilih saja.

## Apa yang dilakukan

- Mencari sampah yang aman dihapus: cache aplikasi, file sementara, log lama, cache browser, dan cache
  peninggalan alat pengembang (npm, pip, Homebrew, Xcode, Docker, dan lain-lain).
- Menampilkan ukuran tiap kategori sebelum ada yang dihapus. Tidak ada yang dihapus sebelum kamu memilih.
- Kalau diminta, mencari folder `node_modules` di proyek yang sudah berbulan-bulan tidak disentuh.
- Berjalan tanpa hak administrator dan tanpa perlu memasang apa pun.

Skill ini tidak mencari file besar, file duplikat, atau unduhan lama. Untuk itu nama file kamu harus
dibaca, dan skill ini memang dirancang agar tidak pernah melakukannya.

## Jaminan privasi

Ada dua jenis jaminan di sini, dan kekuatannya tidak sama. Mohon baca keduanya.

### Dipaksakan oleh skrip

Ini berlaku apa pun yang dilakukan AI, karena skripnya memang ditulis begitu dan diperiksa oleh tes.

- **AI hanya menerima angka total.** Skrip mencetak satu dokumen JSON berisi nama kategori, ukuran,
  jumlah, dan status. Skrip tidak pernah mencetak nama file, nama folder, path, nama pengguna, nama
  komputer, atau nama proyek. Pesan error berupa teks tetap, tanpa sisipan apa pun.
- **Daftar lokasi yang tetap.** Skrip hanya bisa membersihkan kategori yang tercantum di bawah. Tidak
  ada mode "bersihkan semuanya" dan tidak ada cara menyuruhnya menghapus folder tertentu.
- **Penghapusan berpengaman.** Setiap penghapusan lewat satu rutin yang menolak apa pun di luar folder
  home kamu, apa pun yang terlalu dekat dengan pangkal folder itu, folder yang di dalamnya ada folder
  terlindungi, dan semua symbolic link. Link tidak pernah diikuti.
- **Alat pengembang ditanya dulu.** Sebelum perintah pembersih bawaan sebuah alat (npm, Yarn, pnpm,
  pip, Go, Homebrew) dijalankan, skrip menanyakan dulu ke alat itu di mana cache-nya. Kalau lokasinya
  bukan lokasi standar, misalnya karena ada pengaturan yang mengarahkannya ke Documents, kategori itu
  dilaporkan tidak tersedia dan tidak ada yang dijalankan atau dihapus.
- **Folder home tidak bisa ditukar.** Di macOS skrip mencari sendiri folder home asli akunmu dan
  menolak jalan kalau `HOME` menunjuk ke folder di dalamnya.
- **Pindai dulu, baru bersihkan.** `clean` hanya bisa jalan dengan token dari pemindaian dalam 15
  menit terakhir, hanya untuk kategori yang dilaporkan pemindaian itu, dan tokennya hanya berlaku
  sekali. Tempat sampah baru dikosongkan kalau ada flag tambahan yang eksplisit.
- **Tanpa sudo, tanpa hak administrator.** Skrip tidak pernah menaikkan hak akses, tidak pernah
  menutup aplikasi kamu, dan tidak pernah mengubah izin. Kalau sebuah aplikasi sedang terbuka,
  cache-nya dilewati.
- **Tanpa jaringan.** Skrip tidak mengirim apa pun ke mana pun. (Beberapa perintah bawaan alat
  pengembang ikut dipanggil, misalnya `npm cache clean`; semuanya bekerja secara lokal.)

### Instruksi untuk AI, tidak bisa dipaksakan secara teknis

Skill ini memerintahkan AI untuk mematuhi aturan berikut. Asisten yang baik akan patuh, tetapi skrip
tidak bisa mencegah asisten yang punya akses penuh ke terminal kamu melakukan hal lain. Pengaman yang
sebenarnya adalah permintaan izin dari agent kamu sendiri: izinkan skrip cleanup, dan curigai perintah
lain yang muncul selama proses pembersihan.

- AI tidak boleh menjelajahi disk kamu sendiri (`ls`, `find`, `du`, `Get-ChildItem`, dan sejenisnya).
- AI tidak boleh membaca log penghapusan (yang opsional) maupun folder state milik skrip.
- AI tidak boleh menghapus apa pun sendiri atau membersihkan kategori yang tidak kamu setujui.

### Catatan soal `--deep`

Pemindaian biasa hanya melihat ke dalam lokasi cache yang sudah dikenal. Pemindaian mendalam (deep
scan) berbeda: untuk menemukan folder `node_modules` lama, skrip menelusuri folder home kamu (atau
folder proyek yang kamu sebutkan), termasuk Documents dan Desktop. Yang dibaca hanya struktur folder
dan tanggal modifikasi, bukan isi file, dan tidak ada yang diubah. Nama-nama yang terlihat tetap berada
di dalam skrip; AI tetap hanya menerima jumlah dan ukuran. Deep scan hanya berjalan kalau kamu memintanya.

### Log opsional

Kalau kamu ingin catatan tentang apa saja yang dihapus, skrip bisa menulis file log di komputermu
sendiri (`--log`, bawaannya mati). File itu memang berisi path. AI hanya diberi tahu bahwa log itu ada
dan di folder mana, bukan isinya.

## Cara memasang

Pilih salah satu dari tiga cara. Setelah terpasang, mulai ulang agent AI kamu.

### 1. Dengan skills CLI

Butuh Node.js.

```bash
npx skills add awankkaley/disk-cleanup -g
```

`-g` memasangnya untuk akun kamu sehingga bisa dipakai di semua proyek. Tambahkan `-a claude-code`
(atau `codex`, `cursor`, `gemini-cli`, ...) untuk memilih agent, atau biarkan CLI yang bertanya.

### 2. Installer satu baris

macOS (Terminal):

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.sh | bash
```

Windows (PowerShell):

```powershell
irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.ps1 | iex
```

Installer mengunduh rilis v1.0.0, mencari agent AI yang ada di komputermu, lalu menyalin tiga hal ke
folder skills tiap agent: `SKILL.md`, `scripts/`, dan `LICENSE`. Installer tidak menjalankan
pembersihan, tidak butuh hak administrator, dan tidak menulis ke tempat lain.

Untuk memasang hanya ke agent tertentu:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.sh | bash -s -- --agent claude,cursor
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.ps1))) -Agent claude,cursor
```

Nama agent: `claude`, `codex`, `cursor`, `gemini`, `copilot`, `opencode`, `amp`, `goose`, `agents`.

### 3. Salin manual

Unduh [rilis v1.0.0](https://github.com/awankkaley/disk-cleanup/releases/tag/v1.0.0), ekstrak, lalu
salin `SKILL.md`, `scripts/`, dan `LICENSE` ke folder bernama `disk-cleanup` di lokasi yang sesuai
dengan agent kamu:

| Agent | Folder |
| --- | --- |
| Claude Code | `~/.claude/skills/disk-cleanup/` |
| OpenAI Codex CLI | `~/.agents/skills/disk-cleanup/` |
| Cursor | `~/.cursor/skills/disk-cleanup/` |
| Gemini CLI | `~/.gemini/skills/disk-cleanup/` |
| GitHub Copilot CLI | `~/.copilot/skills/disk-cleanup/` |
| OpenCode | `~/.config/opencode/skills/disk-cleanup/` |
| Amp, Goose, dan agent lain yang membaca folder bersama | `~/.agents/skills/disk-cleanup/` |

Di Windows, `~` adalah folder pengguna kamu, misalnya `C:\Users\<kamu>`.

## Cara memakai

Buka agent AI kamu dan minta dengan bahasa sehari-hari. Contohnya:

- "Laptop saya hampir penuh. Tolong bantu kosongkan ruang."
- "Bersihkan file sampah di laptop ini."
- "Kalau cache dibersihkan, bisa dapat berapa GB?"
- "Carikan folder node_modules lama yang bisa dihapus."
- "Sekalian kosongkan tempat sampah."

Asisten akan memindai, menampilkan tabel, lalu menunggu pilihanmu. Contoh percakapan:

> **Kamu:** Laptop saya hampir penuh.
>
> **Asisten:** Mac kamu sudah saya pindai. Sekitar 14,2 GB bisa dikosongkan dengan aman:
>
> | Item | Ukuran | Risiko | Yang akan terasa |
> | --- | --- | --- | --- |
> | Cache build Xcode | 6,1 GB | aman | Build berikutnya lebih lama. |
> | Cache Chrome | 3,4 GB | aman | Halaman web sedikit lebih lambat dimuat, sekali saja. |
> | Cache npm | 2,2 GB | aman | Paket diunduh lagi saat dibutuhkan. |
> | ... | | | |
>
> Cache Safari dilewati karena Safari sedang terbuka. Mau saya bersihkan item yang direkomendasikan?
>
> **Kamu:** Ya, semua kecuali Xcode.

Agent kamu akan meminta izin untuk menjalankan skrip. Itu wajar. Untuk pembersihan ini, seharusnya
tidak ada perintah lain yang perlu dijalankan.

## Apa saja yang dibersihkan

Tingkat risiko: **aman** berarti aplikasinya akan membuat ulang sendiri; **perlu dibangun ulang**
berarti kamu harus menjalankan sebuah perintah untuk mengembalikannya; **permanen** berarti hilang
selamanya.

| ID kategori | Isinya | Platform | Risiko |
| --- | --- | --- | --- |
| `app-caches` | Cache aplikasi | macOS, Windows | aman |
| `temp-files` | File sementara yang lebih tua dari 7 hari | macOS, Windows | aman |
| `logs` | File log dan laporan crash yang lebih tua dari 7 hari | macOS | aman |
| `crash-dumps` | Crash dump aplikasi | Windows | aman |
| `thumbnail-cache` | Cache thumbnail dan ikon Explorer | Windows | aman |
| `store-app-caches` | Cache aplikasi Microsoft Store (hanya file sementara dan cache internet) | Windows | aman |
| `trash` | Tempat sampah / Recycle Bin (hanya kalau kamu minta secara eksplisit) | macOS, Windows | permanen |
| `browser-chrome` | Cache Chrome | macOS, Windows | aman |
| `browser-edge` | Cache Edge | macOS, Windows | aman |
| `browser-firefox` | Cache Firefox | macOS, Windows | aman |
| `browser-brave` | Cache Brave | macOS, Windows | aman |
| `browser-opera` | Cache Opera | macOS, Windows | aman |
| `browser-arc` | Cache Arc | macOS, Windows | aman |
| `browser-safari` | Cache Safari | macOS | aman |
| `npm-cache` | Cache npm | macOS, Windows | aman |
| `yarn-cache` | Cache Yarn | macOS, Windows | aman |
| `pnpm-store` | Paket tak terpakai di store pnpm | macOS, Windows | aman |
| `pip-cache` | Cache pip | macOS, Windows | aman |
| `gradle-cache` | Cache Gradle | macOS, Windows | aman |
| `cargo-cache` | Cache registry Cargo | macOS, Windows | aman |
| `go-cache` | Cache build Go | macOS, Windows | aman |
| `docker-dangling` | Image Docker yang menggantung (dangling) | macOS, Windows | aman |
| `homebrew-cache` | Unduhan Homebrew | macOS | aman |
| `cocoapods-cache` | Cache CocoaPods | macOS | aman |
| `xcode-derived-data` | Cache build Xcode | macOS | aman |
| `xcode-device-support` | File device support Xcode yang tidak dipakai 90+ hari | macOS | aman |
| `xcode-simulators-unavailable` | Simulator yang sudah tidak bisa dipakai Xcode | macOS | aman |
| `node-modules-stale` | `node_modules` di proyek yang menganggur (hanya deep scan) | macOS, Windows | perlu dibangun ulang |

Penghapusan bersifat permanen. Yang dibersihkan tidak dipindahkan ke tempat sampah atau Recycle Bin.

Untuk browser, hanya cache yang dihapus. Di Windows, `app-caches` mencakup daftar tetap aplikasi yang
dikenal (Slack, Discord, Teams, Spotify, VS Code), dan `store-app-caches` hanya mencakup folder
`TempState` dan `INetCache` milik tiap aplikasi Store; `LocalCache` tidak disentuh.

Untuk `pnpm-store`, hasil scan tidak menampilkan ukuran. pnpm hanya membuang paket yang sudah tidak
dipakai proyek mana pun, jadi berapa ruang yang kosong baru ketahuan setelah dibersihkan.

Alat pengembang yang cache-nya dipindah ke lokasi tidak standar akan tampil sebagai tidak tersedia dan
dilewati. Kalau mau, bersihkan sendiri dengan perintah bawaan alat itu.

Sebuah folder `node_modules` dianggap menganggur hanya jika proyeknya punya `package.json` dan lockfile
(jadi bisa dipulihkan dengan satu perintah install) dan tidak ada apa pun di proyek itu yang diubah
selama minimal 30 hari. Batas waktunya kamu yang menentukan.

### Yang tidak pernah disentuh

- Documents, Desktop, Downloads, Pictures, Movies, Music, dan folder cloud drive (iCloud, OneDrive,
  Dropbox, Google Drive).
- Cookie, riwayat, kata sandi tersimpan, sesi, bookmark, dan ekstensi browser.
- Xcode Archives, volume Docker dan image yang bertag, cache modul Go.
- Apa pun yang butuh hak administrator.
- Cache aplikasi yang sedang terbuka.

## Pemakaian manual lewat CLI

Skripnya bisa kamu jalankan sendiri tanpa AI. Keluarannya berupa JSON.

macOS:

```bash
bash scripts/cleanup.sh scan
bash scripts/cleanup.sh clean --token <token> --categories npm-cache,browser-chrome
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 clean --token <token> --categories npm-cache,browser-chrome
```

| Perintah | Opsi |
| --- | --- |
| `scan` | `--deep` ikut mencari `node_modules` yang menganggur (lambat). `--min-age-days N` batas umur file sementara dan log, bawaan 7. `--projects-dir PATH` lokasi yang ditelusuri deep scan, bawaannya folder home. |
| `clean` | `--token ID` dari hasil scan (wajib). `--categories id1,id2` (wajib). `--empty-trash` diperlukan untuk `trash`. `--min-idle-days N` untuk `node-modules-stale`, bawaan sekaligus minimum 30. `--log` menulis daftar path yang dihapus ke file lokal. |
| `--help`, `--version` | |

Token hasil scan berlaku 15 menit dan hanya untuk satu kali clean.

## Opsional: Full Disk Access di macOS

macOS melindungi beberapa folder, termasuk cache Safari. Tanpa izin tambahan, kategori Safari akan
berstatus "tidak ada izin" dan dilewati. Kategori lain tetap berjalan normal.

Kalau kamu ingin cache Safari ikut dibersihkan, buka System Settings > Privacy & Security > Full Disk
Access, lalu aktifkan aplikasi terminal tempat agent AI kamu berjalan. Izin ini memberi terminal
tersebut, dan semua yang berjalan di dalamnya, akses ke jauh lebih banyak bagian disk kamu. Jadi
lakukan hanya kalau kamu merasa nyaman dengan itu. Skill ini tidak pernah memintanya dan tidak pernah
mengubahnya.

## Cara menghapus skill

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.sh | bash -s -- --uninstall
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.0.0/install.ps1))) -Uninstall
```

Kalau dulu memasang lewat skills CLI: `npx skills remove disk-cleanup -g`. Kalau menyalin manual, hapus
folder `disk-cleanup` dari folder skills agent kamu.

`install.sh` hanya mau menimpa atau menghapus folder `disk-cleanup` yang memang skill ini (`SKILL.md`-nya
berisi `name: disk-cleanup`). Kalau ternyata ada folder lain dengan nama yang sama, installer berhenti
dan tidak mengubah apa pun.

Skrip menyimpan satu folder state kecil (token scan terakhir dan log yang pernah kamu minta). Folder itu
juga boleh dihapus: `~/Library/Application Support/disk-cleanup` di macOS, `%LOCALAPPDATA%\disk-cleanup`
di Windows.

## Pertanyaan umum

**Apakah aman?**
Kategori yang direkomendasikan adalah cache dan file sementara yang akan dibuat ulang sendiri oleh
aplikasinya. Paling-paling yang terasa adalah aplikasi atau proses build jadi lebih lambat saat pertama
kali dipakai lagi. Yang lebih berisiko diberi label dan tidak pernah dipilih secara otomatis.

**Bisakah pembersihan dibatalkan?**
Tidak. File dihapus, bukan dipindahkan ke tempat sampah. Itu sebabnya skill ini hanya menyasar hal-hal
yang bisa dibuat ulang, dan mengosongkan tempat sampah butuh persetujuan eksplisit dari kamu.

**Apakah AI bisa melihat nama file saya?**
Lewat skill ini, tidak; skrip hanya melaporkan angka total. Skill ini juga memerintahkan AI agar tidak
melihat-lihat sendiri, tetapi bagian itu sifatnya instruksi, bukan gembok. Lihat "Jaminan privasi".

**Kenapa ada kategori yang dilewati?**
Biasanya karena aplikasinya sedang terbuka (tutup dulu, lalu minta scan ulang), karena alatnya tidak
terpasang, karena macOS menolak akses (lihat Full Disk Access), atau karena sebuah alat pengembang
menyimpan cache-nya di lokasi tidak standar, yang tidak akan disentuh skrip.

**Ruang yang kosong ternyata lebih sedikit dari hasil scan.**
Sebagian file sedang dipakai atau dilindungi sehingga tidak bisa dihapus; itu dilaporkan sebagai
"partial" (sebagian). Aplikasi juga langsung mengisi cache-nya lagi.

**Bisa dipakai di Linux?**
Tidak. Installer tetap akan menyalin skill-nya, tetapi skripnya hanya mendukung macOS dan Windows.

**Apakah saya akan ter-logout dari situs web?**
Tidak. Cookie, sesi, dan kata sandi tersimpan tidak disentuh, hanya cache browser.

**Kenapa tidak bisa mencari file besar saya?**
Menampilkan daftar file besar berarti memperlihatkan nama file kamu ke AI. Untuk itu pakai Finder
(macOS: menu Apple > About This Mac > More Info > Storage Settings) atau Windows Settings > System >
Storage.

## Berkontribusi

Issue dan pull request dipersilakan. Aturan yang paling penting:

- Keluaran skrip tidak boleh memuat path, nama file, nama pengguna, atau string runtime lainnya. Label
  dan pesan adalah konstanta tetap.
- Setiap penghapusan harus lewat satu rutin hapus yang berpengaman.
- `scripts/cleanup.sh` harus jalan di bash 3.2 bawaan macOS; `scripts/cleanup.ps1` harus jalan di
  Windows PowerShell 5.1. Tanpa dependensi tambahan.

**Menambah aplikasi Windows ke `app-caches`.** Di `scripts/cleanup.ps1` ada tabel data berisi aplikasi
yang dikenal. Tambahkan satu baris berisi nama proses aplikasi dan folder cache-nya di bawah `%APPDATA%`
atau `%LOCALAPPDATA%`. Hanya subfolder `Cache`, `Code Cache`, `GPUCache`, dan `CachedData` yang
diperbolehkan. Tambahkan tes di `tests/` yang membuktikan cache-nya terhapus dan file non-cache di
sebelahnya tetap ada.

**Menambah kategori.** Tambahkan ke daftar kategori di kedua skrip kalau konsepnya ada di kedua
platform, dengan id yang stabil, teks label dan impact yang tetap, serta tingkat risiko. Utamakan
perintah pembersihan resmi dari alatnya. Tambahkan tes untuk: pelaporan ukuran, pembersihan, status
dilewati, dan pemeriksaan privasi. Setelah itu tambahkan baris ke tabel di `SKILL.md`, `README.md`, dan
`README.id.md`.

**Menjalankan tes.** Tes memakai folder home palsu dan alat tiruan; file aslimu tidak pernah disentuh.

```bash
brew install bats-core shellcheck
shellcheck -s bash install.sh scripts/cleanup.sh scripts/lib/*.sh
bats tests/
```

```powershell
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser
Invoke-Pester -Path tests
```

Untuk mencoba installer dari checkout tanpa mengunduh: `./install.sh --local .` (checkout-nya tidak
boleh salinan yang sudah terpasang; installer menolak kalau sumber dan tujuannya saling tumpang tindih).

## Lisensi

[MIT](LICENSE) © 2026 awankkaley
