# ==============================================================================
# DOCKERFILE BACKEND LARAVEL 12 (MULTI-STAGE PRODUCTION BUILD)
# ==============================================================================
# INI APA: Cetak biru (blueprint) pembuatan container image Backend Laravel 12.
# KENAPA: Menggunakan teknik Multi-Stage Build untuk memisahkan tahap instalasi
#         dependensi Composer dengan tahap eksekusi runtime produksi.
# UNTUK APA & BAGAIMANA:
#   - Menghasilkan image kontainer PHP-FPM super ramping berbasis Alpine Linux (~80 MB).
#   - Menghindari keberadaan Git, Composer binary, dan compiler sampah di runtime akhir.
# ==============================================================================

# ------------------------------------------------------------------------------
# STAGE 1: BUILD DEPENDENCIES VIA COMPOSER
# ------------------------------------------------------------------------------
# INI APA: Tahap pertama sementara (temporary stage) yang menggunakan image resmi Composer.
# KENAPA: Composer membutuhkan PHP CLI dan memori besar untuk me-resolve dependensi paket.
# UNTUK APA & BAGAIMANA: Mengunduh pustaka vendor tanpa menyertakan devDependencies.
# ------------------------------------------------------------------------------
FROM composer:2 AS vendor

WORKDIR /app

# INI APA: Menyalin hanya file definisi paket dan lockfile.
# KENAPA: Memanfaatkan fitur Docker Layer Caching. Jika kode aplikasi berubah namun 'composer.json'
#         tidak berubah, tahap 'composer install' tidak akan diulang dari nol.
COPY composer.json composer.lock ./

# INI APA: Menjalankan instalasi paket produksi.
# KENAPA:
#   - '--no-dev': Membuang package testing/debug seperti Pest, PHPUnit, Faker, Laravel Pail.
#   - '--prefer-dist': Mengunduh arsip zip terkompresi langsung, bukan git clone.
#   - '--optimize-autoloader': Menghasilkan classmap teroptimasi untuk performa eksekusi kilat.
#   - '--no-scripts': Mencegah eksekusi script artisan otomatis saat image baru dirakit.
RUN composer install \
    --no-dev \
    --no-interaction \
    --prefer-dist \
    --optimize-autoloader \
    --no-scripts

# ------------------------------------------------------------------------------
# STAGE 2: PRODUCTION PHP-FPM RUNTIME (ALPINE LINUX)
# ------------------------------------------------------------------------------
# INI APA: Image final yang akan benar-benar dijalankan di dalam server / VPS.
# KENAPA: Menggunakan 'php:8.2-fpm-alpine' karena Alpine berukuran sangat kecil (<10 MB)
#         dan PHP-FPM adalah standar industri tercepat dalam melayani request via FastCGI.
# UNTUK APA & BAGAIMANA: Mengeksekusi framework Laravel dan berkomunikasi dengan database.
# ------------------------------------------------------------------------------
FROM php:8.2-fpm-alpine AS runner

WORKDIR /var/www/html

# INI APA: Instalasi library sistem operasi Alpine dan kompilasi ekstensi internal PHP.
# KENAPA: Alpine sangat minimalis sehingga belum memiliki driver MySQL atau modul manipulasi teks.
# UNTUK APA & BAGAIMANA:
#   - 'mysql-client' & 'pdo_mysql': Driver komunikasi ke server basis data MySQL.
#   - 'libzip-dev' & 'zip': Untuk penanganan arsip berkas di Laravel.
#   - 'mbstring' & 'bcmath': Pustaka matematika string presisi tinggi (dibutuhkan Laravel Core).
#   - 'opcache': Pustaka kompilasi bytecode PHP di memori agar eksekusi script 3-5x lebih cepat.
RUN apk add --no-cache \
    mysql-client \
    libpng-dev \
    libzip-dev \
    zip \
    unzip \
    curl \
    oniguruma-dev \
    libxml2-dev \
    && docker-php-ext-install \
    pdo_mysql \
    mbstring \
    bcmath \
    opcache

# INI APA: Konfigurasi tuning performa OPcache produksi.
# KENAPA: Mematikan validasi timestamp file ('validate_timestamps=0') agar PHP membaca
#         bytecode dari RAM tanpa bolak-balik membaca SSD/HDD server setiap kali ada request.
COPY docker/php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# INI APA: Menyalin direktori 'vendor' yang telah bersih dari Stage 1 (builder).
# KENAPA: Menghemat bandwidth dan mempercepat build tanpa perlu install Composer di Alpine runtime.
COPY --from=vendor /app/vendor ./vendor

# INI APA: Menyalin seluruh source code aplikasi Laravel dari host.
# BAGAIMANA: File-file sampah development diabaikan secara otomatis lewat file '.dockerignore'.
COPY . .

# INI APA: Standarisasi izin akses berkas (file permission) dan penemuan package.
# KENAPA: Web server (user 'www-data') wajib memiliki hak tulis (write access) ke folder
#         'storage' dan 'bootstrap/cache' untuk menyimpan sesi, log error, dan template blade yang di-render.
# UNTUK APA & BAGAIMANA:
#   - Membersihkan cache kadaluarsa dari host Windows.
#   - Menjalankan 'php artisan package:discover' khusus untuk package produksi.
#   - Memberikan kepemilikan direktori ke user 'www-data:www-data'.
#   - Memberi izin eksekusi (+x) pada skrip inisialisasi 'entrypoint.sh'.
RUN rm -f /var/www/html/bootstrap/cache/*.php \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache \
    && chmod +x /var/www/html/docker/entrypoint.sh

# INI APA: Dokumentasi port komunikasi internal.
# BAGAIMANA: Menandakan bahwa kontainer ini melayani protokol FastCGI di port 9000.
EXPOSE 9000

# INI APA: Skrip booting otomatis dan proses daemon utama.
# KENAPA: Kita perlu memastikan database MySQL telah siap dan migrasi tabel selesai sebelum PHP-FPM aktif.
# BAGAIMANA: 'entrypoint.sh' berjalan terlebih dahulu, lalu diakhiri dengan eksekusi daemon 'php-fpm'.
ENTRYPOINT ["/var/www/html/docker/entrypoint.sh"]
CMD ["php-fpm"]
