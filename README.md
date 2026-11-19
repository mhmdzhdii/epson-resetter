# Epson Waste Ink Pad Resetter (Windows & Linux) 🖨️⚡

[![Platform: Windows & Linux](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-blue.svg)](https://github.com)
[![Models Supported](https://img.shields.io/badge/Supported%20Models-1%2C270%2B-brightgreen.svg)](https://github.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![No Malware / No Activation](https://img.shields.io/badge/Free%20%26%20Clean-100%25%20Open%20Source-success.svg)](https://github.com)

A free, 100% open-source waste ink pad resetter tool for **Epson printers** (supporting **1,270+ models**, including **L120, L3110, L3210, L360, L805, EcoTank series, XP, and WF**).

---

## 🌟 Key Features

* **100% Native on Windows**: Built using PowerShell and .NET Windows Forms. Runs immediately without installing Python, Java, or third-party drivers.
* **Native Linux Support**: Full Linux compatibility with an interactive terminal menu (`./jalankan_linux.sh`), direct CLI commands, and Tkinter GUI.
* **1,270+ Epson Models**: Comprehensive database of memory profiles, read/write keys, and EEPROM addresses.
* **Auto-Backup**: Automatically creates a timestamped JSON snapshot of your counter cells in `Backups/` before writing to EEPROM.
* **Auto-Verify**: Re-reads physical EEPROM chips after writing to verify that counters have dropped to **0 points (0.0%)**.
* **Port Status Indicator**: Detects active USB connections and marks printer queues as `[Online / Terhubung]` vs `[Offline]`.
* **Hardware Diagnostics**: Displays USB interface pipes, spooler document health, firmware version, and chip specs in a formatted window with clipboard copy.
* **Ink Maintenance Tools**:
  * 🚿 **Head Cleaning**: Sends Remote1 `CH` command to engage the pump motor and unclog nozzles.
  * 📄 **Nozzle Check Pattern**: Sends Remote1 `NC` command to print a test grid pattern.
* **Standalone EXE & Icon**: Includes `Launcher.cs` and `Compile_Exe.bat` to compile `EpsonResetter.exe` with a custom icon and silent execution.

---

## 🚀 Cara Penggunaan (Windows)

1. Sambungkan printer Epson Anda dengan **kabel USB** dan nyalakan printer.
2. Buka folder aplikasi dan pilih salah satu cara:
   * **Paling Direkomendasikan**: Klik 2x `JALANKAN_RESETTER.bat`.
   * **Opsi File EXE**: Klik 2x `Compile_Exe.bat` untuk membuat `EpsonResetter.exe` ber-ikon kustom, lalu klik 2x `EpsonResetter.exe`.
3. Pada antarmuka aplikasi:
   * Pilih nama printer Anda di dropdown **Printer Windows**.
   * Di kolom **Cari Model**, ketikkan model printer Anda (misal: `L120`, `L3110`, `L3210`).
   * Klik tombol **`🔍 1. Baca Counter`** untuk melihat persentase bantalan tinta saat ini.
   * Klik tombol **`⚡ 3. Reset Counter (0%)`**. Sistem akan otomatis mencadangkan data dan mereset chip.
4. **Langkah Wajib**: Setelah muncul notifikasi berhasil, **matikan printer dengan tombol Power fisik**, tunggu 5 detik, lalu hidupkan kembali!

---

## 🐧 Cara Penggunaan (Linux)

Pastikan Python 3 terpasang. Di Linux, akses langsung ke port hardware USB membutuhkan izin `sudo`.

### Opsi A: Menu Interaktif
```bash
./jalankan_linux.sh
```
Pilih opsi dari menu interaktif (Scan, Check, Reset, Head Cleaning, Nozzle Check, atau GUI).

### Opsi B: Perintah CLI Langsung
```bash
# 1. Pindai printer terhubung
sudo python3 cli.py scan

# 2. Periksa persentase counter
sudo python3 cli.py check --model L120

# 3. Reset counter ke 0% (dengan auto-backup & auto-verify)
sudo python3 cli.py reset --model L120

# 4. Alat perawatan
sudo python3 cli.py clean --model L120   # Head Cleaning
sudo python3 cli.py nozzle --model L120  # Nozzle Check
```

### Opsi C: Antarmuka Grafis (GUI Desktop)
```bash
sudo -E python3 Epson_Resetter.py
```

---

## ⚠️ Peringatan Keselamatan Fisik

> [!WARNING]
> Reset perangkat lunak ini **HANYA** menghapus batas hitungan digital di memori chip EEPROM printer.
> Tinta buangan fisik di dalam busa (*waste ink pad*) di bagian belakang printer **TIDAK** otomatis hilang.
>
> Pastikan Anda:
> 1. Mencuci busa pembuangan di bagian belakang printer sampai bersih lalu dikeringkan, ATAU
> 2. Mengganti busa bantalan dengan yang baru, ATAU
> 3. Memasang selang/tabung pembuangan luar (*waste ink tank*).
> 
> Jika busa tidak dibersihkan, cairan tinta pekat berlebih lama-kelamaan dapat meluber dan merusak meja atau korslet pada komponen sirkuit printer.

---

## 📁 Struktur Direktori

```text
├── app.ico                 # Ikon aplikasi multi-resolusi
├── Backups/                # Folder penyimpanan otomatis backup EEPROM (.json)
├── Buka_Aplikasi.bat       # Launcher alternatif Windows
├── Buka_Mode_Demo.bat      # Launcher mode simulasi tanpa printer fisik
├── cli.py                  # Antarmuka CLI lintas platform
├── Compile_Exe.bat         # Batch compiler ke native EpsonResetter.exe (menggunakan CSC .NET)
├── core.py                 # Core driver komunikasi RAW USB & SNMP
├── EpsonResetter.ps1       # Aplikasi utama Windows GUI (.NET WinForms & Win32 API)
├── Epson_Resetter.py       # Universal Python launcher
├── epson_usb/              # Pustaka transport RAW USB (libusb, pyusb, usblp, usbprint)
├── gui_tk.py               # Antarmuka grafis Tkinter untuk Linux & fallback
├── JALANKAN_RESETTER.bat   # Script peluncur utama Windows (Auto Administrator)
├── JALANKAN_RESETTER.vbs   # Peluncur Windows mode senyap tanpa console
├── jalankan_linux.sh       # Script peluncur interaktif Linux
├── Launcher.cs             # Kode sumber C# untuk EpsonResetter.exe
├── models.json             # Database 1,270+ profil memori printer Epson
├── models.py               # Loader database model & pencarian
├── models_db.py            # Serialized specs fallback
├── PANDUAN_WINDOWS.txt     # Panduan teks lengkap pengguna Windows
└── README.md               # Dokumentasi proyek
```

---

## 📜 Lisensi
Dilisensikan di bawah lisensi [MIT](LICENSE). Bebas digunakan, dipelajari, dan dimodifikasi untuk keperluan pemeliharaan printer mandiri.
