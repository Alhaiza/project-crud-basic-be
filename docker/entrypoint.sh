#!/bin/sh
# ==============================================================================
# SKRIP INISIALISASI BOOTING CONTAINER BACKEND (ENTRYPOINT.SH)
# ==============================================================================
# INI APA: Skrip shell (POSIX sh) yang pertama kali dieksekusi saat kontainer backend dinyalakan.
# KENAPA: Saat kontainer dijalankan bersamaan, ada jeda waktu (latency) di mana kontainer MySQL
#         sudah 'Up' namun mesin database belum selesai membuka port penerimaan koneksi.
# UNTUK APA & BAGAIMANA:
#   1. Menahan proses backend sampai database MySQL benar-benar siap menerima koneksi (TCP Ping).
#   2. Menjamin keberadaan Application Key (APP_KEY) untuk enkripsi sesi dan token Sanctum.
#   3. Membersihkan residu cache dari sistem operasi host Windows.
#   4. Mengaktifkan konfigurasi produksi (config/route cache).
#   5. Menjalankan migrasi skema tabel otomatis (php artisan migrate --force).
#   6. Mengalihkan proses (exec) ke daemon utama PHP-FPM di latar depan (foreground).
# ==============================================================================

# INI APA: Flag fail-fast shell script.
# KENAPA: Jika ada salah satu perintah di bawah yang gagal (exit code != 0), skrip langsung berhenti
#         seketika agar kita tidak menjalankan kontainer dalam kondisi setengah rusak / korup.
set -e

# ------------------------------------------------------------------------------
# 1. MENUNGGU KESIAPAN JARINGAN BASIS DATA MYSQL
# ------------------------------------------------------------------------------
# INI APA: Loop pengecekan koneksi TCP socket menggunakan netcat ('nc').
# KENAPA: Mencegah error 'PDOException: Connection Refused' saat Laravel mencoba query sebelum MySQL siap.
# BAGAIMANA: Mengirim probe setiap 2 detik ke host '$DB_HOST' (service database) pada port '$DB_PORT' (3306).
echo "==> [Backend] Menunggu database MySQL siap di $DB_HOST:$DB_PORT..."
until nc -z -v -w30 "$DB_HOST" "$DB_PORT"; do
  echo "==> [Backend] MySQL belum siap di $DB_HOST:$DB_PORT, menunggu 2 detik..."
  sleep 2
done
echo "==> [Backend] Koneksi basis data MySQL terhubung!"

# ------------------------------------------------------------------------------
# 2. VALIDASI & PEMBUATAN OTOMATIS APP_KEY LARAVEL
# ------------------------------------------------------------------------------
# INI APA: Pemeriksaan variabel lingkungan APP_KEY.
# KENAPA: Laravel mewajibkan enkripsi AES-256-CBC untuk token cookie dan session. Tanpa key ini,
#         setiap permintaan login user akan gagal dengan HTTP 500 error.
# BAGAIMANA: Jika variabel APP_KEY kosong di file .env, buatkan key acak baru secara otomatis.
if [ -z "$APP_KEY" ]; then
  echo "==> [Backend] APP_KEY belum ada, melakukan generate otomatis..."
  php artisan key:generate --force
fi

# ------------------------------------------------------------------------------
# 3. PEMBERSIHAN CACHE RESIDU DARI HOST OS WINDOWS
# ------------------------------------------------------------------------------
# INI APA: Penghapusan file cache PHP serial di folder 'bootstrap/cache'.
# KENAPA: Sering kali developer menjalankan 'composer install' atau 'php artisan' di Windows host,
#         meninggalkan file cache dengan path direktori Windows (D:\...) atau package dev (Laravel Pail).
# BAGAIMANA: Menghapus cache lama dan mendaftarkan ulang provider paket produksi Linux.
rm -f /var/www/html/bootstrap/cache/*.php
php artisan package:discover --ansi || true

# ------------------------------------------------------------------------------
# 4. CACHE KONFIGURASI & RUTE PRODUKSI
# ------------------------------------------------------------------------------
# INI APA: Kompilasi semua file config/*.php dan routes/api.php menjadi 1 file biner datar.
# KENAPA: Meningkatkan kecepatan eksekusi Laravel secara drastis hingga 4x lipat di server produksi.
echo "==> [Backend] Mengoptimalkan konfigurasi dan rute cache..."
php artisan config:cache || true
php artisan route:cache || true

# ------------------------------------------------------------------------------
# 5. MIGRASI STRUKTUR TABEL BASIS DATA
# ------------------------------------------------------------------------------
# INI APA: Eksekusi otomatis seluruh file migration Laravel ke basis data MySQL.
# KENAPA: Menjamin bahwa tabel 'users', 'products', 'personal_access_tokens' langsung tercipta
#         tanpa perlu developer login manual ke kontainer atau membuka phpMyAdmin.
# BAGAIMANA: Parameter '--force' wajib ditambahkan saat 'APP_ENV=production'.
echo "==> [Backend] Menjalankan migrasi database otomatis..."
php artisan migrate --force

# ------------------------------------------------------------------------------
# 6. PENYERAHAN KONTROL KE PROSES UTAMA (PHP-FPM)
# ------------------------------------------------------------------------------
# INI APA: Perintah penggantian proses (process replacement) dengan parameter CMD Dockerfile.
# KENAPA: Agar PHP-FPM berjalan sebagai PID 1 di kontainer Linux, sehingga sinyal OS seperti
#         SIGTERM dan SIGINT saat 'docker stop' dapat diterima dan ditutup secara bersih (graceful shutdown).
echo "==> [Backend] Inisialisasi selesai. Menjalankan PHP-FPM..."
exec "$@"
