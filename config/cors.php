<?php

return [
    // 1. Path endpoint yang diproteksi dan diizinkan CORS (semua route berawalan api/)
    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    // 2. HTTP method yang diizinkan (GET, POST, PUT, DELETE, OPTIONS, dll.)
    'allowed_methods' => ['*'],

    // 3. Domain frontend Nuxt yang diizinkan mengakses API (mencegah error CORS)
    'allowed_origins' => ['http://localhost:3000', 'http://127.0.0.1:3000'],

    // 4. Pola regex untuk domain asal jika dinamis (kosong untuk kebutuhan lokal)
    'allowed_origins_patterns' => [],

    // 5. Header HTTP yang diizinkan dikirim oleh Nuxt (Content-Type, Authorization, dll.)
    'allowed_headers' => ['*'],

    // 6. Header response yang diizinkan dibaca oleh JavaScript di frontend
    'exposed_headers' => [],

    // 7. Lama waktu (detik) browser boleh menyimpan cache hasil preflight OPTIONS request
    'max_age' => 0,

    // 8. Diaktifkan agar browser diizinkan mengirim cookie atau kredensial autentikasi
    'supports_credentials' => true,
];
