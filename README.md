# MonitorBar

Monitor sistem macOS yang hidup **hanya di menu bar**. Nggak ada window
utama, nggak ada dashboard, nggak ada riwayat — klik ikon di menu bar,
popover berisi 6 kartu ini yang muncul:

| Kartu | Isi |
|---|---|
| **Memory** | % terpakai + GB terpakai/total, donut breakdown (App / Wired / Compressed / Cached), badge disk terpakai + swap |
| **Processor Load** | % CPU total + bar per-core (ungu = user, biru = system) |
| **Network Activity** | Koneksi (Wi-Fi/Ethernet), ↓/↑ per detik, IP publik + IP lokal |
| **Processor Temperature** | Suhu CPU (°C) + termometer + badge Low/Moderate/High |
| **Processes** | 2 aplikasi terberat: %CPU, %RAM, ukuran RAM — proses helper digabung ke app induknya |
| **Device** | Versi macOS + uptime |

Satu-satunya jendela lain adalah **Settings** (dari tombol gear di
popover, atau ⌘,): launch at login, interval refresh (1/2/5 detik),
metrik yang ditampilkan di menu bar, kartu yang ditampilkan, dan
toggle IP publik. Quit dari footer popover atau ⌘Q.

App terpisah dari Ultimate Mac Monitor — project ini memang sengaja
kecil: tanpa incidents, tanpa history, tanpa notifikasi, tanpa updater.

## Build & jalankan (di Mac)

Butuh Xcode (Swift 5.9+), macOS 14+.

```bash
swift test                  # unit test MonitorKit
./scripts/build-app.sh      # menghasilkan dist/MonitorBar.app
open dist/MonitorBar.app
```

Catatan first run: angka berbasis delta (CPU, network, proses) butuh
dua kali sampling, jadi di detik-detik pertama kartu menampilkan `—`.
Itu disengaja — app ini nggak pernah mengarang angka.

## Sumber data

- CPU per-core: `host_processor_info` · CPU total & proses:
  `proc_pid_rusage` (delta waktu user+system, gaya Activity Monitor)
- Memory: `host_statistics64` · Swap: `vm.swapusage` · Disk: atribut
  filesystem volume `/`
- Network: `getifaddrs` pada interface utama (`en0` → Wi-Fi)
- Suhu: AppleSMC kunci `Tp01` (fallback `Tp05`) — terverifikasi di
  MacBook Air M2; kalau sensor nggak terbaca, kartu menampilkan `—`
- IP publik: `api.ipify.org`, maksimal 1×/menit, hanya saat toggle-nya
  menyala. Itu satu-satunya panggilan jaringan app ini. Matiin
  toggle-nya = app sepenuhnya offline.
- Device: `ProcessInfo` (versi OS + `systemUptime`)

## Dua keputusan interpretasi dari screenshot referensi

- Badge `↓ 75%` di kartu Memory ditafsirkan sebagai **disk terpakai**
  (badge kedua `⇄` jelas swap). Kalau maksudnya lain, tinggal ganti
  satu baris di `MemoryCard`.
- Kolom tengah Processes ditafsirkan sebagai **%RAM** (kolom pertama
  %CPU, ketiga ukuran RAM). %GPU per-proses nggak punya API publik
  yang praktis di macOS.
