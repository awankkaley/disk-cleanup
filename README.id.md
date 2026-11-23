# disk-cleanup

[English](README.md) | **Bahasa Indonesia**

disk-cleanup membuat asisten AI di komputermu bisa melegakan penyimpanan Mac atau laptop Windows
tanpa pernah melihat isi file kamu. Sampah peninggalan aplikasi dibersihkan, lalu kamu sendiri, dan
hanya kamu, yang memilih file besar dan unduhan lama mana yang mau dibuang.

**Buat siapa:** siapa saja yang laptopnya sering muncul peringatan "penyimpanan hampir penuh". Tidak
perlu bisa ngoding. Asal bisa ngobrol dengan aplikasi AI dan klik "Allow", kamu bisa pakai.

## Gambaran pemakaiannya

1. Kamu bilang ke aplikasi AI: "Laptop saya penuh, tolong bantu legakan."
2. Aplikasinya minta izin menjalankan skrip pembersih. Kamu izinkan.
3. Beberapa detik kemudian muncul daftar singkat, misalnya:

   > Sekitar 14 GB bisa dikosongkan dengan aman.
   >
   > | Apa | Ukuran | Efeknya buat kamu |
   > | --- | --- | --- |
   > | File sementara Chrome | 3,4 GB | Halaman web sedikit lebih lambat, sekali saja. |
   > | File sementara aplikasi | 6,1 GB | Dibuat ulang sendiri oleh aplikasinya. |
   > | Installer update iPhone lama | 4,7 GB | Diunduh lagi kalau suatu saat perlu. |
   >
   > Mau saya bersihkan?

4. Kamu jawab "ya", atau "semua kecuali Chrome". Yang dibersihkan hanya yang kamu pilih.
5. Masih kurang lega? Minta tinjau file besar. Sebuah halaman terbuka di browsermu sendiri, isinya
   file-file terbesar dan unduhan lama. Centang yang boleh dibuang, tekan "Selesai memilih", lalu
   file-file itu dipindahkan ke Tempat Sampah (Trash). AI tidak pernah melihat halaman itu.

Tidak ada yang dibersihkan sebelum kamu melihat daftarnya dan bilang ya.

## Aplikasi apa yang saya butuhkan?

Skill ini menjalankan sebuah skrip kecil **di komputermu sendiri**. Jadi hanya bisa dipakai di
aplikasi AI yang memang bisa melakukan itu. Situs chat dan aplikasi di HP tidak bisa: kode mereka
jalan di server perusahaannya, dan dari sana disk kamu tidak kelihatan.

| Aplikasi | Bisa? | Catatan |
| --- | --- | --- |
| **Aplikasi desktop Claude, tab Code** (Mac, Windows) | **Bisa** | Pilihan paling gampang. Perlu paket Claude berbayar (Pro ke atas). Pakai sesi "Local". |
| **Aplikasi desktop ChatGPT** (yang di dalamnya ada Codex; Mac, Windows) | **Bisa** | Menjalankan perintah di komputermu, dengan batasan: dia akan minta persetujuan dulu karena file yang dibersihkan ada di luar folder proyek. |
| **Cursor** (Mac, Windows) | **Bisa** | Editor kode yang punya agen AI. Ada paket gratis dengan pemakaian terbatas. |
| **Claude Code** (terminal) | **Bisa** | Pasangnya cukup satu perintah; lihat [Claude Code](#claude-code). |
| Codex CLI, GitHub Copilot CLI, Gemini CLI, OpenCode | Bisa | Alat berbasis terminal untuk developer. Lihat [Untuk developer](#untuk-developer). |
| Aplikasi desktop Claude, tab **Chat**; situs claude.ai; aplikasi Claude di HP | **Tidak** | Skill dijalankan di sandbox milik Anthropic, yang tidak bisa menjangkau disk kamu. |
| Aplikasi desktop Claude, **Cowork** | **Tidak** | Bekerja di lingkungan terisolasi dan hanya melihat folder yang kamu hubungkan, bukan tempat sampah-sampah itu berada. |
| Situs chatgpt.com; aplikasi ChatGPT di HP | **Tidak** | Tugas di cloud berjalan tanpa akses ke file di komputermu. |
| Aplikasi dan situs Gemini | **Tidak** | Kami tidak menemukan cara resmi untuk menjalankan skrip di komputermu dari sana. |

Tabel ini mengikuti dokumentasi resmi tiap perusahaan per November 2026 (tautannya ada di
[bagian paling bawah](#sumber-tabel-aplikasi)). Aplikasi AI cepat sekali berubah; kalau aplikasimu
bisa menjalankan perintah di komputermu dan mendukung "Agent Skills", semestinya bisa.

Yang didukung hanya macOS dan Windows. Linux, HP, dan tablet tidak.

## Cara memasang

Setelah terpasang, mulai obrolan baru (atau tutup lalu buka lagi aplikasinya) supaya skill-nya terbaca.

### Claude Code

```bash
npx skills add awankkaley/disk-cleanup -g
```

Sudah, itu saja (perlu Node.js). Kamu juga bisa langsung minta ke Claude: "Tolong jalankan
`npx skills add awankkaley/disk-cleanup -g`."

Opsional: kalau lebih suka satu perintah per mode (`/disk-cleanup:scan`, `/disk-cleanup:review`, ...),
pasang versi plugin-nya dengan `/plugin marketplace add awankkaley/disk-cleanup` lalu
`/plugin install disk-cleanup@awankkaley-disk-cleanup`. Pilih salah satu, jangan dua-duanya.

### Aplikasi desktop Claude

Hanya tab **Code** yang bisa membersihkan disk: tab itu adalah Claude Code yang berjalan di
komputermu sendiri. Tab **Chat** dan **Cowork** bekerja di sandbox dan tidak bisa menjangkau disk,
jadi skill ini tidak jalan di sana. Langkah berikut menganggap kamu sudah memakai aplikasi desktop
Claude dengan paket Claude berbayar.

1. Pasang skill-nya. Kalau sudah ada Node.js, pakai perintah Claude Code di atas. Kalau belum, buka
   Terminal (Mac: tekan Command+Spasi, ketik `Terminal`, tekan Enter) atau PowerShell (Windows: klik
   Start, ketik `PowerShell`, tekan Enter), tempel baris yang sesuai komputermu, lalu tekan Enter.

   Mac:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent claude
   ```

   Windows:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent claude
   ```

   Kalau sudah muncul tulisan "Done", tutup jendelanya lalu buka ulang aplikasi Claude. Installer ini
   hanya menyalin skill ke folder skills milik Claude. Tidak ada yang dibersihkan, dan kamu tidak akan
   dimintai kata sandi.
2. Klik tab **Code** di bagian atas sidebar. Di bawah kotak pesan, klik pilihan paling kiri dan pilih
   entri teratas di kelompok **Local**. Setelah itu pilih **Open folder…** dan pilih folder mana saja,
   misalnya folder kosong yang baru kamu buat. Folder itu tidak dipakai untuk bersih-bersih;
   aplikasinya saja yang butuh satu folder.
3. Ketik: `Laptop saya hampir penuh, tolong bantu legakan.` atau `/disk-cleanup`.

### Aplikasi desktop ChatGPT (Codex)

1. Buka Terminal atau PowerShell seperti dijelaskan di atas.
2. Tempel baris yang sesuai komputermu, lalu tekan Enter.

   Mac:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent codex
   ```

   Windows:

   ```powershell
   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent codex
   ```

3. Buka ulang aplikasinya. Di obrolan lokal (local chat), ketik `@` lalu pilih **disk-cleanup**, atau
   langsung saja bilang: "Laptop saya penuh, tolong bantu legakan."
4. Saat aplikasinya minta persetujuan untuk menjalankan skrip pembersih, setujui. Skrip ini bekerja di
   luar folder proyek, makanya dengan pengaturan bawaan aplikasinya akan bertanya dulu.

### Cursor

Langkahnya sama seperti ChatGPT, hanya `codex` di ujung baris diganti `cursor`. Setelah itu buka
Agent chat di Cursor, ketik `/`, lalu pilih **disk-cleanup**.

### Lebih dari satu aplikasi, atau aplikasi lain

Buang bagian paling belakang, dan installer akan memasang skill ini ke semua aplikasi AI yang
didukung dan ditemukan di komputermu:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash
```

```powershell
irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1 | iex
```

Untuk developer: opsi installer lainnya dan cara salin manual ada di
[Cara pasang lainnya](#cara-pasang-lainnya).

## Cara memakai

### Cukup minta saja

Tidak ada perintah yang perlu dihafal. Buka aplikasi AI-mu dan tulis saja maumu, pakai bahasa
sehari-hari:

- "Laptop saya hampir penuh. Tolong bantu legakan."
- "Kosongkan 10 GB."
- "Kira-kira bisa lega berapa GB? Jangan hapus apa-apa dulu."
- "Tampilkan file-file terbesar dan unduhan lama saya, biar saya pilih sendiri yang mau dibuang."
- "Sekalian kosongkan Tempat Sampah."

Asisten akan minta izin menjalankan skrip pembersih. Itu wajar, izinkan saja. Untuk bersih-bersih
ini seharusnya tidak ada perintah lain yang perlu dijalankan, jadi waspadalah kalau dia meminta
yang lain.

### Atau ketik perintah

Ketik `/disk-cleanup`, boleh ditambah satu kata di belakangnya:

| Kamu ketik | Yang terjadi |
| --- | --- |
| `/disk-cleanup` | Memeriksa apa saja yang bisa dibersihkan, menampilkan daftar beserta ukurannya, lalu bertanya mana yang mau dibersihkan. |
| `/disk-cleanup 10gb` | Sama, tapi langsung diusulkan pilihan paling hemat yang cukup untuk melegakan sebanyak itu. Tetap bertanya dulu. |
| `/disk-cleanup scan-only` | Menampilkan daftar dan totalnya, lalu selesai. Tidak ada yang dibersihkan. |
| `/disk-cleanup review` | Membuka halaman pribadi di browsermu berisi file besar dan unduhan lama, supaya kamu bisa memilih mana yang dipindahkan ke Tempat Sampah. Lihat bagian berikutnya. |
| `/disk-cleanup deep` | Untuk developer: sekalian mencari folder `node_modules` lama di proyek yang sudah berbulan-bulan tidak disentuh. |
| `/disk-cleanup help` | Menjelaskan pilihan-pilihan ini. Tidak menjalankan apa pun. |

Di aplikasi desktop ChatGPT tidak ada perintah garis miring: ketik `@`, pilih disk-cleanup, lalu
tambahkan katanya di belakang (atau minta saja dengan bahasa biasa). Di aplikasi lain ada sedikit
perbedaan; lihat [Perintah di tiap aplikasi](#perintah-di-tiap-aplikasi).

Memang sengaja tidak ada pilihan untuk langsung membersihkan. `/disk-cleanup clean all` pun tetap
memeriksa dulu, menampilkan daftar, lalu menunggu pilihanmu.

## Review: file besar dan unduhan lama

Yang bikin laptop penuh biasanya bukan file sementara, melainkan beberapa video besar, installer
lama, dan folder Downloads yang bertahun-tahun tidak pernah ditengok. Mana yang boleh dibuang, cuma
kamu yang tahu. Karena itu bagian ini dikerjakan kamu sendiri, bukan AI.

1. Minta "tampilkan file terbesar dan unduhan lama saya", atau ketik `/disk-cleanup review`.
2. Sebuah halaman terbuka di browsermu. Isinya file berukuran 100 MB ke atas di seluruh folder home
   kamu, dan file di Downloads yang sudah 90 hari atau lebih tidak berubah, lengkap dengan nama,
   folder, ukuran, dan tanggal. Bisa diurutkan menurut ukuran dan disaring per kelompok.
3. Centang yang sudah tidak kamu perlukan. Totalnya langsung terlihat ("dipilih: 12 item, 8,4 GB").
4. Tekan tombol **Selesai memilih** (di browser berbahasa Inggris: **Done choosing**). Browser akan
   menyimpan file kecil bernama `disk-cleanup-selection.json`; lewat file itulah pilihanmu sampai ke
   skrip. Kalau browser bertanya mau disimpan di mana, pilih **Downloads**. Setelah itu halaman
   menampilkan "Pilihan Anda tersimpan". Berubah pikiran? Tekan "Ubah pilihan", perbaiki centangnya,
   lalu tekan tombolnya lagi; file yang paling baru yang dipakai.
5. Kembali ke aplikasi AI dan ketik "selesai".
6. File yang kamu centang dipindahkan ke Tempat Sampah (Trash di macOS, Recycle Bin di Windows).
   Asisten memberi tahu berapa file dan berapa besar totalnya.

Yang perlu kamu tahu:

- **AI tidak bisa melihat halaman itu.** Halamannya berupa file di komputermu sendiri yang dibuka
  langsung oleh browser. Tidak dikirim ke AI atau ke mana pun, dan halaman itu tidak memuat apa-apa
  dari internet. Yang disampaikan ke asisten hanya jumlah item yang ditemukan dan total ukurannya,
  lalu setelahnya berapa yang dipindahkan. File pilihan yang tersimpan hanya berisi dua kode dan
  nomor-nomor item, tanpa nama file.
- **Downloads atau Desktop.** Skrip mencari file yang tersimpan langsung di dalam folder Downloads,
  dan kalau kamu tidak sengaja menyimpannya di Desktop, langsung di Desktop. Tidak di tempat lain.
- **Tidak ada yang terhapus dari halaman itu.** Mencentang dan menyimpan belum mengubah apa-apa.
  File baru dipindahkan setelah kamu bilang "selesai" di obrolan.
- **File masih bisa dikembalikan.** Semuanya ada di Tempat Sampah atau Recycle Bin. Di Mac, buka
  Trash lalu seret filenya keluar, atau klik kanan dan pilih "Put Back" kalau macOS menyediakannya.
  Di Windows, buka Recycle Bin, klik kanan filenya, pilih "Restore".
- **Ruang baru benar-benar lega setelah Tempat Sampah dikosongkan.** Kosongkan sendiri, atau minta
  asisten ("sekalian kosongkan Tempat Sampah"). Mengosongkannya permanen dan berlaku untuk semua isi
  Tempat Sampah.
- **Hati-hati dengan folder cloud.** Kalau filenya ada di folder yang disinkronkan dengan iCloud
  Drive, OneDrive, Dropbox, atau Google Drive, memindahkannya ke Tempat Sampah juga menghapusnya dari
  cloud dan dari perangkatmu yang lain. File yang hanya ada di cloud (belum diunduh ke komputer ini)
  tidak ditampilkan, karena membuangnya tidak menambah ruang di sini.
- **File yang berubah tidak disentuh.** Kalau sebuah file diubah, dipindah, atau diganti setelah
  halamannya dibuat, file itu dilewati.
- **Halamannya berlaku satu jam** dan hanya untuk sekali pakai. Lewat dari itu, minta review baru.
  Halaman yang sudah kedaluwarsa beserta daftar di baliknya dihapus otomatis saat skill ini
  dijalankan lagi.
- **Yang tidak pernah ditampilkan:** apa pun di dalam aplikasi, folder sistem `Library` atau
  `AppData`, folder tersembunyi, dan library yang oleh macOS ditampilkan sebagai satu item, misalnya
  library Photos.

### macOS akan meminta izin

Saat pertama kali, macOS bisa memunculkan pesan seperti **"Claude" would like to access files in your
Downloads folder** (namanya mengikuti aplikasi tempat asistenmu berjalan), begitu juga untuk
Documents dan Desktop.

- Klik **Allow** kalau folder itu mau ikut ditinjau.
- Klik **Don't Allow** kalau tidak. Review tetap jalan untuk folder lainnya.
- Mau mengubah jawabanmu nanti: System Settings > Privacy & Security > Files and Folders.

**Folder Downloads wajib diizinkan.** Halaman review menyimpan pilihanmu di sana, jadi kalau aplikasinya
tidak boleh membuka Downloads, asisten tidak bisa membaca apa yang kamu centang dan review tidak bisa
diselesaikan. Asisten akan mengingatkan sebelum kamu mulai mencentang. Cara membetulkannya: buka
System Settings > Privacy & Security > Files and Folders, cari aplikasi tempat kamu memakai asisten
(misalnya Terminal, Claude, atau Cursor), lalu nyalakan **Downloads Folder** dan **Desktop Folder**.
Setelah itu minta asisten mencoba lagi; review-nya masih berlaku selama satu jam.

Saat pertama kali file dipindahkan ke Trash, akan muncul pesan kedua: **"Terminal" wants access to
control "Finder"** (namanya lagi-lagi mengikuti aplikasimu). Klik **OK** (izinkan). Dengan begitu
file dipindahkan lewat Finder, jadi kamu bisa mengembalikannya kapan saja: buka Trash, klik kanan
filenya, lalu pilih **Put Back**. Kalau kamu klik **Don't Allow**, file tetap masuk ke Trash, tapi
harus kamu seret sendiri kembali ke foldernya. Mau mengubahnya nanti: System Settings > Privacy &
Security > Automation.

Kalau halamannya tidak terbuka sendiri, asisten akan memberi tahu lokasinya supaya bisa kamu buka
sendiri: `~/Library/Application Support/disk-cleanup/review.html` di macOS (di Finder: Go > Go to
Folder, lalu tempel bagian foldernya), atau `%LOCALAPPDATA%\disk-cleanup\review.html` di Windows
(tempel di kolom alamat File Explorer).

## Jaminan privasi

Ada dua jenis jaminan di sini, dan kekuatannya tidak sama. Mohon baca dua-duanya.

### Dijamin oleh skripnya

Ini berlaku apa pun yang dilakukan AI, karena skripnya memang ditulis begitu dan diperiksa oleh tes.

- **Skrip hanya mencetak angka total.** Semua yang diserahkan skrip ke AI berupa satu dokumen JSON
  berisi nama kategori, ukuran, jumlah, dan status. Skrip tidak pernah mencetak nama file, nama
  folder, path, nama pengguna, nama komputer, atau nama proyek. Pesan error berupa teks tetap, tanpa
  sisipan apa pun. Ini berlaku juga untuk review: AI hanya mendapat jumlah item dan ukurannya.
- **Lokasi yang dibersihkan sudah ditentukan.** Pembersih hanya bisa membersihkan kategori yang
  tercantum di bawah. Tidak ada mode "bersihkan semuanya" dan tidak ada cara menyuruhnya menghapus
  folder tertentu.
- **File pribadi hanya dari daftar review, dan hanya ke Tempat Sampah.** Sebuah file pribadi baru
  dipindahkan kalau disebut di pilihan yang tersimpan, memang ada di daftar review itu, masih
  memenuhi aturan yang membuatnya masuk daftar (masih sebesar itu, atau masih file lama yang
  letaknya langsung di Downloads), filenya masih sama (ukuran dan tanggalnya tidak berubah), dan
  letaknya di dalam folder home kamu di luar lokasi yang dilindungi. File itu dipindahkan ke Tempat
  Sampah atau Recycle Bin, tidak pernah dihapus permanen, apa pun yang terjadi. Yang **tidak** bisa
  dibuktikan skrip adalah bahwa pilihan itu benar-benar kamu sendiri yang menyimpan: lihat
  [Siapa yang menyimpan pilihan](#siapa-yang-menyimpan-pilihan) di bawah.
- **Penghapusan berpengaman.** Setiap penghapusan permanen lewat satu rutin yang menolak apa pun di
  luar folder home kamu, apa pun yang terlalu dekat dengan pangkal folder itu, folder yang di
  dalamnya ada folder terlindungi, dan semua symbolic link. Link tidak pernah diikuti.
- **Alat developer ditanya dulu.** Sebelum perintah pembersih bawaan sebuah alat (npm, Yarn, pnpm,
  pip, Go, Homebrew) dijalankan, skrip menanyakan dulu ke alat itu di mana cache-nya. Kalau bukan di
  lokasi standar, kategori itu dilaporkan tidak tersedia dan tidak ada yang dijalankan atau dihapus.
- **Folder home tidak bisa ditukar.** Di macOS skrip mencari sendiri folder home asli akunmu dan
  menolak jalan kalau `HOME` menunjuk ke folder di dalamnya.
- **Periksa dulu, baru bersihkan.** Pembersihan hanya bisa jalan dengan kode dari pemeriksaan dalam
  15 menit terakhir, hanya untuk kategori yang dilaporkan pemeriksaan itu, dan kodenya hanya berlaku
  sekali. Tempat Sampah baru dikosongkan kalau ada flag tambahan yang eksplisit. Review punya kode
  sendiri yang berlaku satu jam dan sekali pakai.
- **Tanpa sudo, tanpa hak administrator.** Skrip tidak pernah menaikkan hak akses, tidak pernah
  menutup aplikasimu, dan tidak pernah mengubah izin. Kalau sebuah aplikasi sedang terbuka, file
  sementaranya dilewati.
- **Tanpa jaringan.** Skrip tidak mengirim apa pun ke mana pun, dan halaman review tidak memuat
  apa-apa dari internet. (Beberapa perintah bawaan alat developer ikut dipanggil, misalnya
  `npm cache clean`; semuanya bekerja secara lokal.)

### Instruksi untuk AI, tidak bisa dipaksakan secara teknis

Skill ini memerintahkan AI untuk mematuhi aturan berikut. Asisten yang baik akan patuh, tetapi skrip
tidak bisa mencegah asisten yang punya akses luas ke komputermu melakukan hal lain. Pengaman yang
sebenarnya adalah permintaan izin dari aplikasi AI-mu sendiri: izinkan skrip pembersih, dan curigai
perintah lain yang muncul selama bersih-bersih.

- AI tidak boleh menjelajahi disk kamu sendiri (`ls`, `find`, `du`, `Get-ChildItem`, dan sejenisnya).
- AI tidak boleh membuka halaman review, daftar di baliknya, maupun pilihan yang kamu simpan.
- AI tidak boleh membuat atau mengubah file pilihan. Yang sah hanya klik tombol "Selesai memilih"
  ("Done choosing") darimu sendiri.
- AI tidak boleh memintamu menempelkan nama file, dan tidak boleh memilihkan file untukmu.
- AI tidak boleh membaca log penghapusan (yang opsional) maupun folder state milik skrip.
- AI tidak boleh menghapus apa pun sendiri atau membersihkan kategori yang tidak kamu setujui.

### Siapa yang menyimpan pilihan

Skrip tidak bisa melihat siapa yang mengeklik. Yang dilakukannya sebagai gantinya:

- Setiap review punya kode kedua yang lebih panjang (kode rahasia pilihan). Skrip tidak pernah
  mencetaknya, jadi AI tidak pernah diberi kode itu. Kode ini hanya ada di dalam halaman review dan
  daftar di baliknya, dan halaman itulah yang menuliskannya ke file yang disimpan tombol "Selesai
  memilih". File pilihan tanpa kode rahasia yang benar ditolak dan tidak ada yang dipindahkan.
- Daftar di balik halaman diberi checksum. Kalau daftar itu diubah setelah review dibuat, tidak ada
  yang dipindahkan. Setiap file juga diperiksa ulang terhadap aturan yang membuatnya masuk daftar.

Yang **tidak** dijamin: asisten berjalan atas nama akunmu, jadi secara teknis ia mampu membaca
halaman atau daftar itu, mengambil kode rahasianya, lalu menulis file pilihan sendiri. Skill ini
melarang persis hal itu, sehingga melakukannya adalah pelanggaran aturan yang terang-terangan dan
bukan sesuatu yang bisa terjadi tanpa sengaja. Tetap saja, ini aturan, bukan gembok. Pengaman yang
sebenarnya adalah permintaan izin dari aplikasi AI-mu: selama review, perintah yang perlu kamu
izinkan hanya `review` dan `review-apply`.

### File yang memang berisi nama file kamu

Supaya jelas: selama sebuah review masih terbuka, ada dua file di disk kamu yang memuat nama dan
lokasi file-file yang ditampilkan, yaitu halamannya sendiri (`review.html`) dan daftar di baliknya.
Keduanya disimpan di folder state milik skrip dan hanya bisa dibaca oleh akun penggunamu sendiri.
Keduanya dihapus begitu pilihanmu dijalankan, saat tertimpa review baru, dan, kalau review-nya tidak
kamu selesaikan, saat perintah disk-cleanup apa pun dijalankan setelah review itu berumur lebih dari
satu jam. Kalau skill ini tidak pernah dijalankan lagi, dua file itu tetap ada sampai folder
state-nya kamu hapus (lihat [Cara menghapus skill](#cara-menghapus-skill)). AI diperintahkan untuk
tidak membacanya, tetapi **secara teknis tidak dicegah**, karena asisten berjalan atas nama kamu.

Log penghapusan yang opsional juga begitu: kalau kamu minta catatan tentang apa saja yang
dibersihkan, skrip menulis file log di komputermu sendiri (`--log`, bawaannya mati). File itu berisi
path. AI hanya diberi tahu bahwa log itu ada dan di folder mana, bukan isinya.

### Deep scan dan review menelusuri folder home

Pemeriksaan biasa hanya melihat ke lokasi file sementara yang sudah dikenal. Ada dua mode opsional
yang melihat lebih jauh, dan hanya kalau kamu minta: review, dan deep scan untuk mencari
`node_modules` lama (buat developer). Dua-duanya menelusuri folder home kamu, termasuk Documents dan
Desktop. Yang dibaca hanya nama, ukuran, dan tanggal, bukan isi file, dan tidak ada yang diubah. Apa
yang terlihat tetap tinggal di dalam skrip (dan, untuk review, di halaman yang hanya kamu buka).

## Apa saja yang dibersihkan

**Aman dibersihkan** (akan dibuat ulang sendiri oleh aplikasinya):

- File sementara aplikasi, termasuk Slack, Discord, Microsoft Teams (classic), dan VS Code. Hanya
  file sementaranya: pesan, pengaturan, dan unduhan tidak disentuh.
- File sementara browser: Chrome, Edge, Firefox, Brave, Opera, Arc, dan Safari. Hanya cache-nya,
  jadi kamu tidak akan ter-logout dari mana pun.
- File sementara dan log lama yang umurnya lebih dari 7 hari.
- Di Mac: installer update iPhone dan iPad yang pernah diunduh. Cadangan (backup) perangkatmu tidak
  disentuh.
- Di Windows: crash dump, cache thumbnail, dan file sementara aplikasi Microsoft Store.
- Unduhan dan sisa build alat developer (npm, pip, Homebrew, Xcode, Docker, dan lain-lain), hanya
  ditampilkan kalau memang ada di komputermu.

Yang dibersihkan di sini dihapus permanen, tidak dipindahkan ke Tempat Sampah. Itu sebabnya bagian
ini hanya mencakup hal-hal yang akan muncul lagi dengan sendirinya.

**Hanya kalau kamu minta:**

- Tempat Sampah / Recycle Bin: baru dikosongkan kalau kamu memintanya secara tegas.
- File besar dan unduhan lama milikmu: hanya yang kamu centang di halaman review, dan itu pun hanya
  dipindahkan ke Tempat Sampah.
- Folder `node_modules` lama (developer, deep scan).

Daftar lengkap beserta id-nya ada di [Kategori](#kategori).

### Yang tidak pernah disentuh

- File pribadimu di Documents, Desktop, Downloads, Pictures, Movies, Music, dan folder cloud drive
  (iCloud, OneDrive, Dropbox, Google Drive), dengan satu pengecualian: file yang **kamu centang
  sendiri** di halaman review, dan itu pun hanya dipindahkan ke Tempat Sampah.
- Cookie, riwayat, kata sandi tersimpan, sesi, bookmark, dan ekstensi browser.
- Pesan chat, pengaturan aplikasi, library foto, cadangan perangkat.
- Xcode Archives, volume Docker dan image yang bertag, cache modul Go.
- Apa pun yang butuh hak administrator.
- File sementara aplikasi yang sedang terbuka.

## Pertanyaan umum

**Aman, nggak?**
Yang direkomendasikan adalah file sementara yang akan dibuat ulang sendiri oleh aplikasinya.
Paling-paling sebuah aplikasi terasa lebih lambat saat pertama dibuka lagi. Yang lebih berisiko
diberi tanda dan tidak pernah dipilih otomatis. File milikmu sendiri hanya disentuh kalau kamu yang
mencentangnya.

**Bisa dibatalkan?**
File sementara: tidak, karena langsung dihapus. Makanya yang disasar hanya hal-hal yang bisa
terbentuk lagi. File dari review: bisa, selama Tempat Sampah atau Recycle Bin belum dikosongkan.

**Apakah AI bisa melihat nama file saya?**
Lewat skill ini, tidak. Skrip hanya melaporkan angka total, dan halaman review dibuka oleh
browsermu, bukan oleh AI. Skill ini juga memerintahkan AI agar tidak melihat-lihat sendiri dan tidak
membuka file review, tetapi bagian itu sifatnya instruksi, bukan gembok. Lihat
[Jaminan privasi](#jaminan-privasi).

**Saya sudah tekan "Selesai memilih" dan bilang "selesai", tapi asisten bilang pilihannya tidak ketemu.**
Browsermu menyimpan filenya di tempat selain Downloads atau Desktop, atau sempat bertanya mau
disimpan di mana lalu kamu batalkan. Tekan "Selesai memilih" sekali lagi (kalau halamannya
menampilkan "Pilihan Anda tersimpan", tekan "Ubah pilihan" dulu), dan kalau ditanya, pilih
Downloads dan biarkan namanya seperti yang disarankan.

**Sudah buang file lewat review, kok ruang kosongnya tidak bertambah?**
Filenya masih di Tempat Sampah. Ruangnya baru kembali setelah Tempat Sampah dikosongkan.

**Kenapa ada yang dilewati?**
Biasanya karena aplikasinya sedang terbuka (tutup dulu, lalu minta lagi), karena macOS menolak
akses, atau karena sebuah alat developer menyimpan filenya di lokasi tidak standar, yang tidak akan
disentuh skrip.

**Hasilnya lebih sedikit dari yang dijanjikan.**
Sebagian file sedang dipakai atau dilindungi sehingga tidak bisa dihapus. Aplikasi juga langsung
mengisi lagi file sementaranya.

**Apakah saya akan ter-logout dari situs web?**
Tidak. Cookie, sesi, dan kata sandi tersimpan tidak disentuh.

**Bisa cari file duplikat atau merapikan foto?**
Tidak. Untuk itu AI harus membaca nama file kamu. Review menampilkan file besar dan unduhan lama,
dan kamu yang memutuskan.

**Bisa dipakai di Linux, HP, atau tablet?**
Tidak. Hanya komputer macOS dan Windows.

## Cara menghapus skill

- Plugin Claude Code: `claude plugin uninstall disk-cleanup@awankkaley-disk-cleanup`, lalu
  `claude plugin marketplace remove awankkaley-disk-cleanup`.
- Dipasang lewat installer satu baris:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --uninstall
  ```

  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Uninstall
  ```

- Dipasang lewat skills CLI: `npx skills remove disk-cleanup -g`.
- Disalin manual: hapus folder `disk-cleanup` dari folder skills agent kamu.

Installer hanya mau menimpa atau menghapus folder `disk-cleanup` yang memang skill ini (`SKILL.md`-nya
berisi `name: disk-cleanup`), dan hanya file perintah yang memuat baris penandanya sendiri. Apa pun
yang lain dengan nama yang sama tidak disentuh.

Skrip menyimpan satu folder state kecil (kode terakhir, review yang belum selesai, dan log yang pernah
kamu minta). Folder itu boleh dihapus: `~/Library/Application Support/disk-cleanup` di macOS,
`%LOCALAPPDATA%\disk-cleanup` di Windows.

---

# Untuk developer

## Perintah di tiap aplikasi

| Agent | Pindai, lalu pilih | Laporan saja | Review file | Deep scan |
| --- | --- | --- | --- | --- |
| Claude Code, plugin | `/disk-cleanup:scan` | `/disk-cleanup:scan-only` | `/disk-cleanup:review` | `/disk-cleanup:deep` |
| Claude desktop (tab Code) dan Claude Code, skill | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| Aplikasi desktop ChatGPT (Codex) | `@`, pilih disk-cleanup | tambah `scan-only` | tambah `review` | tambah `deep` |
| Codex CLI | `$disk-cleanup` | `$disk-cleanup scan-only` | `$disk-cleanup review` | `$disk-cleanup deep` |
| Cursor | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| GitHub Copilot CLI | `/disk-cleanup` | `/disk-cleanup scan-only` | `/disk-cleanup review` | `/disk-cleanup deep` |
| Gemini CLI ¹ | `/disk-cleanup:scan` | `/disk-cleanup:scan-only` | `/disk-cleanup:review` | `/disk-cleanup:deep` |
| OpenCode ¹ | `/disk-cleanup/scan` | `/disk-cleanup/scan-only` | `/disk-cleanup/review` | `/disk-cleanup/deep` |
| Goose, Amp | minta dengan bahasa biasa | minta laporan saja | minta review file besar | minta deep scan |

¹ Butuh file perintah yang ditambahkan installer satu baris. Di dalamnya juga ada `/disk-cleanup` polos
yang menerima kata tambahan seperti skill biasa, dan perintah `help`. Tanpa file itu, minta saja
dengan bahasa sehari-hari; cara kerja skill-nya sama.

Plugin juga punya `/disk-cleanup:help`. Ukuran bisa ditulis di belakang perintah scan mana pun:
`/disk-cleanup 10gb`, `/disk-cleanup:scan 10gb`.

## Cara pasang lainnya

### skills CLI

Perintah di bagian [Claude Code](#claude-code) juga berlaku untuk agent lain. `-g` memasangnya untuk akun kamu. Tambahkan `-a claude-code` (atau `codex`, `cursor`, `gemini-cli`, ...)
untuk memilih agent, atau biarkan CLI yang bertanya. Yang terpasang skill-nya saja; file perintah
`/disk-cleanup` untuk Gemini CLI dan OpenCode hanya ikut lewat installer satu baris.

### Opsi installer satu baris

Installer mengunduh rilis v1.2.0, mencari agent AI yang ada di komputermu, lalu menyalin `SKILL.md`,
`scripts/`, dan `LICENSE` ke folder skills tiap agent. Khusus Gemini CLI dan OpenCode, installer juga
menambahkan beberapa file perintah kecil (`disk-cleanup.toml` dan folder `disk-cleanup/` berisi satu
file per mode di `~/.gemini/commands/`, serta padanannya berupa file `.md` di
`~/.config/opencode/commands/`). Installer tidak menjalankan pembersihan, tidak butuh hak
administrator, dan tidak menulis ke tempat lain.

Hanya untuk agent tertentu:

```bash
curl -fsSL https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.sh | bash -s -- --agent claude,cursor
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/awankkaley/disk-cleanup/v1.2.0/install.ps1))) -Agent claude,cursor
```

Nama agent: `claude`, `codex`, `cursor`, `gemini`, `copilot`, `opencode`, `amp`, `goose`, `agents`.

### Plugin Claude Code lewat terminal

Dua perintah `/plugin`-nya ada di bagian [Claude Code](#claude-code). Atau dari shell: `claude plugin marketplace add awankkaley/disk-cleanup`, lalu
`claude plugin install disk-cleanup@awankkaley-disk-cleanup`. Di Claude Code 2.1.275 ke atas cukup satu
langkah: `/plugin install disk-cleanup --marketplace awankkaley/disk-cleanup`.

Lewat plugin, tiap mode punya perintahnya sendiri (`/disk-cleanup:scan`, `:scan-only`, `:review`,
`:deep`, `:help`); lewat skill biasa perintahnya cuma satu:
`/disk-cleanup [scan-only|review|deep|help|10gb]`. Dua-duanya mengikuti instruksi yang sama dan
menjalankan skrip yang sama. Kalau kamu memasang keduanya, skill ini muncul dua kali di Claude Code,
jadi pilih salah satu saja.

### Salin manual

Unduh [rilis v1.2.0](https://github.com/awankkaley/disk-cleanup/releases/tag/v1.2.0), ekstrak, lalu
salin `SKILL.md`, `scripts/`, dan `LICENSE` ke folder bernama `disk-cleanup`:

| Agent | Folder |
| --- | --- |
| Claude Code | `~/.claude/skills/disk-cleanup/` |
| Aplikasi desktop ChatGPT (Codex), Codex CLI | `~/.agents/skills/disk-cleanup/` |
| Cursor | `~/.cursor/skills/disk-cleanup/` |
| Gemini CLI | `~/.gemini/skills/disk-cleanup/` |
| GitHub Copilot CLI | `~/.copilot/skills/disk-cleanup/` |
| OpenCode | `~/.config/opencode/skills/disk-cleanup/` |
| Amp, Goose, dan agent lain yang membaca folder bersama | `~/.agents/skills/disk-cleanup/` |

Di Windows, `~` adalah folder pengguna kamu, misalnya `C:\Users\<kamu>`.

Opsional, supaya perintah `/disk-cleanup` tersedia di Gemini CLI atau OpenCode: salin juga
`commands/gemini/disk-cleanup.toml` dan folder `commands/gemini/disk-cleanup/` ke
`~/.gemini/commands/`, atau `commands/opencode/disk-cleanup.md` dan folder
`commands/opencode/disk-cleanup/` ke `~/.config/opencode/commands/`.

## Kategori

Tingkat risiko: **aman** berarti aplikasinya akan membuat ulang sendiri; **perlu dibangun ulang**
berarti kamu harus menjalankan sebuah perintah untuk mengembalikannya; **permanen** berarti hilang
selamanya.

| ID kategori | Isinya | Platform | Risiko |
| --- | --- | --- | --- |
| `app-caches` | Cache aplikasi | macOS, Windows | aman |
| `temp-files` | File sementara yang lebih tua dari 7 hari | macOS, Windows | aman |
| `logs` | File log dan laporan crash yang lebih tua dari 7 hari | macOS | aman |
| `ios-updates` | Installer update iPhone, iPad, dan iPod yang pernah diunduh | macOS | aman |
| `crash-dumps` | Crash dump aplikasi | Windows | aman |
| `thumbnail-cache` | Cache thumbnail dan ikon Explorer | Windows | aman |
| `store-app-caches` | Cache aplikasi Microsoft Store (hanya file sementara dan cache internet) | Windows | aman |
| `trash` | Tempat Sampah / Recycle Bin (hanya kalau kamu minta secara tegas) | macOS, Windows | permanen |
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

Tiap kategori juga punya `rebuild_cost` (1 tidak terasa, 2 diunduh atau dibangun ulang saat dipakai
lagi, 3 unduh atau bangun ulangnya lama), yang menentukan urutan usulan dari `scan --target-gb`.

`app-caches` mencakup folder cache sistem ditambah tabel tetap berisi empat aplikasi yang dikenal
(Slack, Discord, Microsoft Teams classic, VS Code), dan untuk aplikasi-aplikasi itu hanya folder
bernama `Cache`, `Code Cache`, `GPUCache`, atau `CachedData`. Aplikasi yang menyimpan unduhan di
folder bernama cache (misalnya musik offline Spotify) sengaja tidak dimasukkan ke tabel. Aplikasi
yang sedang berjalan dilewati. Di Windows, `store-app-caches` hanya mencakup folder
`TempState` dan `INetCache` milik tiap aplikasi Store; `LocalCache` tidak disentuh. `ios-updates` tidak
pernah menyentuh cadangan perangkat.

Untuk `pnpm-store`, hasil scan tidak menampilkan ukuran: pnpm hanya membuang paket yang sudah tidak
dipakai proyek mana pun, jadi berapa ruang yang lega baru ketahuan setelah dibersihkan. Alat developer
yang cache-nya dipindah ke lokasi tidak standar akan tampil sebagai tidak tersedia dan dilewati.

Sebuah folder `node_modules` dianggap menganggur hanya jika proyeknya punya `package.json` dan lockfile
dan tidak ada apa pun di proyek itu yang diubah selama minimal 30 hari. Batas waktunya kamu yang
menentukan.

## Pemakaian manual lewat CLI

Skripnya bisa kamu jalankan sendiri tanpa AI. Keluarannya berupa JSON.

macOS:

```bash
bash scripts/cleanup.sh scan
bash scripts/cleanup.sh scan --target-gb 10
bash scripts/cleanup.sh clean --token <token> --categories npm-cache,browser-chrome
bash scripts/cleanup.sh review
bash scripts/cleanup.sh review-apply --token <token review>
```

Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 scan
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 clean --token <token> --categories npm-cache,browser-chrome
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 review
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\cleanup.ps1 review-apply --token <token review>
```

| Perintah | Opsi |
| --- | --- |
| `scan` | `--deep` ikut mencari `node_modules` yang menganggur (lambat). `--target-gb N` (1 sampai 10000) menambahkan `suggestion`: kategori aman, dari yang paling murah dibangun ulang, yang cukup untuk mencapai N GB. `--min-age-days N` batas umur file sementara dan log, bawaan 7. `--projects-dir PATH` lokasi yang ditelusuri deep scan, bawaannya folder home. |
| `clean` | `--token ID` dari hasil scan (wajib). `--categories id1,id2` (wajib). `--empty-trash` diperlukan untuk `trash`. `--min-idle-days N` untuk `node-modules-stale`, bawaan sekaligus minimum 30. `--log` menulis daftar path yang dihapus ke file lokal. |
| `review` | `--min-size-mb N` ukuran terkecil yang dianggap file besar, bawaan 100, minimum 10. `--downloads-age-days N` umur item di Downloads, bawaan 90, minimum 7. Menulis halaman review lalu membukanya; yang dicetak hanya jumlah dan token review. |
| `review-apply` | `--token ID` dari hasil review (wajib). Membaca `disk-cleanup-selection.json` dari folder Downloads atau, kalau tidak ada, dari Desktop (file valid yang paling baru yang dipakai), hanya menerimanya kalau memuat kode rahasia yang ditulis halaman review, lalu memindahkan file yang dipilih ke Tempat Sampah / Recycle Bin. |
| `--help`, `--version` | |

Token scan berlaku 15 menit dan untuk satu kali `clean`. Token review terpisah, berlaku 60 menit dan
untuk satu kali `review-apply`. Review menampilkan paling banyak 500 item, dari yang terbesar. Setiap
perintah, termasuk `--help` dan `--version`, lebih dulu menghapus halaman dan daftar milik review
yang umurnya sudah lebih dari 60 menit.

## Opsional: Full Disk Access di macOS

macOS melindungi beberapa folder, termasuk cache Safari. Tanpa izin tambahan, kategori Safari akan
berstatus "tidak ada izin" dan dilewati. Kategori lain tetap berjalan normal.

Kalau kamu ingin cache Safari ikut dibersihkan, buka System Settings > Privacy & Security > Full Disk
Access, lalu aktifkan aplikasi tempat agent AI kamu berjalan. Izin ini memberi aplikasi tersebut, dan
semua yang berjalan di dalamnya, akses ke jauh lebih banyak bagian disk kamu. Jadi lakukan hanya kalau
kamu merasa nyaman dengan itu. Skill ini tidak pernah memintanya dan tidak pernah mengubahnya.

## Berkontribusi

Issue dan pull request dipersilakan. Aturan yang paling penting:

- Keluaran skrip tidak boleh memuat path, nama file, nama pengguna, atau string runtime lainnya. Label
  dan pesan adalah konstanta tetap.
- Setiap penghapusan permanen harus lewat satu rutin hapus yang berpengaman. File pribadi hanya boleh
  dipindahkan ke Tempat Sampah, lewat satu rutin khusus untuk itu.
- `scripts/cleanup.sh` harus jalan di bash 3.2 bawaan macOS; `scripts/cleanup.ps1` harus jalan di
  Windows PowerShell 5.1. Tanpa dependensi tambahan.

**Menambah aplikasi ke `app-caches`.** Di kedua skrip ada tabel data berisi aplikasi yang dikenal.
Tambahkan satu baris berisi nama proses aplikasi dan folder cache-nya. Hanya subfolder `Cache`,
`Code Cache`, `GPUCache`, dan `CachedData` yang diperbolehkan. Tambahkan tes di `tests/` yang
membuktikan cache-nya terhapus dan file non-cache di sebelahnya tetap ada.

**Menambah kategori.** Tambahkan ke daftar kategori di kedua skrip kalau konsepnya ada di kedua
platform, dengan id yang stabil, teks label dan impact yang tetap, tingkat risiko, dan rebuild cost.
Utamakan perintah pembersihan resmi dari alatnya. Tambahkan tes untuk: pelaporan ukuran, pembersihan,
status dilewati, dan pemeriksaan privasi. Setelah itu tambahkan baris ke tabel di `README.md` dan
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

## Sumber tabel aplikasi

Diperiksa pada November 2026 dari dokumentasi resmi masing-masing:

- Tab Code di aplikasi desktop Claude berjalan lokal dan memuat skill: <https://code.claude.com/docs/en/desktop>, <https://code.claude.com/docs/en/desktop-quickstart>
- Mengunggah skill dalam bentuk ZIP, dan skill di chat berjalan di sandbox: <https://claude.com/docs/skills/how-to>, <https://claude.com/docs/skills/overview>
- Lingkungan terisolasi Cowork: <https://support.claude.com/en/articles/13345190-get-started-with-claude-cowork>
- Skill dan izin di aplikasi desktop ChatGPT dan Codex: <https://learn.chatgpt.com/docs/build-skills>, <https://learn.chatgpt.com/docs/permission-modes>
- Tugas cloud ChatGPT tidak punya akses ke file lokal: <https://help.openai.com/en/articles/20001548-agent-security-and-local-work-sync-in-chatgpt>
- Skill dan terminal di Cursor: <https://cursor.com/docs/context/skills>, <https://cursor.com/docs/agent/terminal>
- Skill di Gemini CLI: <https://geminicli.com/docs/cli/skills/>
- Skill di GitHub Copilot: <https://docs.github.com/en/copilot/concepts/agents/about-agent-skills>

## Lisensi

[MIT](LICENSE) © 2026 awankkaley
