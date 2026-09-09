# ZXV OFFICIAL PROTECT

> Pterodactyl protection toolkit — ZXV OFFICIAL / XyrooXellz

## Access

**Access Key:** `ZxvHost`

Installer akan meminta Access Key sebelum membuka menu protection.

## Files

- `install.sh` — installer utama
- `protect1.sh` — Level 1
- `protect2.sh` — Level 2
- `protect3.sh` — Level 3
- `uninstallprotect.sh` — restore/uninstall
- `README.md` — dokumentasi

## Protection Levels

### LEVEL 1 — BASIC SHIELD

Proteksi dasar untuk membatasi akses server dan endpoint tertentu.

Cocok untuk pemasangan ringan.

### LEVEL 2 — HARD SHIELD

Menambahkan proteksi pada controller dan service admin/server yang tersedia dari source protection.

Lebih ketat daripada Level 1.

### LEVEL 3 — FULL SHIELD

Memasang seluruh protection set yang tersedia di paket ini.

Termasuk halaman khusus:

`/view/1`

yang diarahkan ke:

`ADMIN UTAMA`
`KHUSUS ADMIN UTAMA`

## Install

Upload file ke VPS, lalu:

```bash
chmod +x install.sh protect1.sh protect2.sh protect3.sh uninstallprotect.sh
```

Jalankan menu:

```bash
./install.sh
```

Atau langsung:

```bash
./protect1.sh
./protect2.sh
./protect3.sh
```

## Uninstall

```bash
./uninstallprotect.sh
```

Installer membuat backup sebelum mengganti file. Uninstaller menggunakan backup terakhir yang tersimpan untuk mengembalikan file.

## Panel Location

Default:

```text
/var/www/pterodactyl
```

Jika panel berada di lokasi lain:

```bash
PANEL_DIR=/path/ke/pterodactyl ./protect1.sh
```

## Important

Jalankan sebagai `root`.

Protection ini membatasi akses melalui aplikasi/Pterodactyl. Ini bukan jaminan terhadap user yang sudah memiliki akses `root` ke VPS, karena root tetap dapat membaca dan mengubah file sistem.

## Branding

```text
ZXV OFFICIAL
XyrooXellz
```

No Base64 payload. Source installer menggunakan heredoc agar file protection tetap dapat dibaca dan diaudit.
