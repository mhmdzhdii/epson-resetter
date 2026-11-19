#!/usr/bin/env python3
"""
Antarmuka Baris Perintah (CLI) untuk Epson Resetter (L120, L3110, L3210).
"""

from __future__ import annotations

import argparse
import sys
import os

# Tambahkan direktori modul ke path jika dijalankan langsung
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from models import MODELS, detect_model
import core


def print_banner():
    print("=" * 64)
    print(" EPSON WASTE INK PAD RESETTER (L120 • L3110 • L3210)")
    print(" Alat Pengatur Ulang Bantalan Pembuangan Tinta Epson untuk Linux")
    print("=" * 64)


def cmd_scan(args):
    print("🔍 Memindai printer Epson yang tersambung via USB...")
    devices = core.scan_printers(include_mock=args.mock)
    if not devices:
        print("❌ Tidak ditemukan printer Epson USB yang aktif.")
        print("   Tips:")
        print("   1. Pastikan kabel USB printer tersambung dengan baik.")
        print("   2. Pastikan printer dalam keadaan HIDUP (Power ON).")
        print("   3. Jalankan 'lsusb' untuk memeriksa vendor ID 04b8.")
        return 1

    print(f"✅ Ditemukan {len(devices)} perangkat:")
    for idx, d in enumerate(devices, 1):
        det = f" [Terdeteksi: {d['detected_model']}]" if d["detected_model"] else ""
        print(f"   {idx}. {d['name']} (Path: {d['path']}, Backend: {d['backend']}){det}")
    return 0


def cmd_check(args):
    print_banner()
    model = args.model
    dev_path = args.device
    host = args.host
    is_mock = args.mock

    mode = "mock" if is_mock else ("network" if host else "usb")

    if not model and not host and not is_mock:
        # Coba auto-detect dari scan
        devs = core.scan_printers(include_mock=False)
        if devs and devs[0].get("detected_model"):
            model = devs[0]["detected_model"]
            dev_path = dev_path or devs[0]["path"]
            print(f"ℹ️  Model terdeteksi otomatis: {model} pada {dev_path}")

    if not model:
        print("❌ Model printer harus ditentukan dengan --model [L120|L3110|L3210]")
        print(f"   Pilihan model: {', '.join(MODELS.keys())}")
        return 1

    model = model.upper()
    if model not in MODELS:
        print(f"❌ Model '{model}' tidak dikenal. Pilihan: {list(MODELS.keys())}")
        return 1

    print(f"📡 Menghubungi printer {MODELS[model]['display_name']} ({mode.upper()})...")
    mgr = core.PrinterManager(mode=mode, device_path=dev_path, host=host, is_mock=is_mock)

    try:
        st = mgr.read_status(model)
    except Exception as exc:
        print(f"❌ Gagal membaca printer: {exc}")
        return 1

    print("\n📊 STATUS BANTALAN PEMBUANGAN TINTA:")
    print("-" * 64)
    print(f" Model        : {st['display_name']}")
    print(f" Nomor Seri   : {st['serial_number']}")
    print("-" * 64)

    for c in st["counters"]:
        bar_len = 24
        pct = c["percent"]
        filled = int((pct / 100.0) * bar_len)
        filled = min(bar_len, max(0, filled))
        bar = "█" * filled + "░" * (bar_len - filled)
        
        status_txt = "AMAN"
        if c["is_full"]:
            status_txt = "⚠️ PENUH (SERVICE REQUIRED)"
        elif c["is_warning"]:
            status_txt = "HAMPIR PENUH"

        max_str = f" / {c['max']}" if c.get("max") else ""
        print(f" {c['name']}")
        print(f"   [{bar}] {pct:5.1f}% ({c['raw']}{max_str} poin) -> {status_txt}")
        print()

    print("-" * 64)
    if st["is_full"]:
        print("⚠️  PERINGATAN: Bantalan tinta sudah penuh atau hampir penuh.")
        print("   Jalankan 'epson-resetter reset --model " + model + "' untuk mereset.")
    else:
        print("✅ Status printer normal.")
    return 0


def cmd_backup(args):
    model = args.model
    if not model:
        print("❌ Tentukan model printer dengan --model [L120|L3110|L3210]")
        return 1
    model = model.upper()
    mode = "mock" if args.mock else ("network" if args.host else "usb")
    mgr = core.PrinterManager(mode=mode, device_path=args.device, host=args.host, is_mock=args.mock)

    try:
        path, data = mgr.backup_eeprom(model, output_path=args.output)
        print(f"✅ Backup EEPROM berhasil disimpan ke: {path}")
        return 0
    except Exception as exc:
        print(f"❌ Gagal membuat backup: {exc}")
        return 1


def cmd_reset(args):
    print_banner()
    model = args.model
    if not model:
        # Coba auto-detect
        devs = core.scan_printers(include_mock=args.mock)
        if devs and devs[0].get("detected_model"):
            model = devs[0]["detected_model"]
            print(f"ℹ️  Model terdeteksi otomatis: {model}")

    if not model:
        print("❌ Model printer harus ditentukan dengan --model [L120|L3110|L3210]")
        return 1
    model = model.upper()
    if model not in MODELS:
        print(f"❌ Model '{model}' tidak dikenal. Pilihan: {list(MODELS.keys())}")
        return 1

    print(f"\n⚠️  PERINGATAN KESELAMATAN SEBELUM RESET:")
    print("   1. Reset perangkat lunak ini HANYA menghapus hitungan digital di memori.")
    print("   2. Tinta buangan fisik di dalam busa (waste pad) TIDAK otomatis hilang.")
    print("   3. Pastikan busa pembuangan di bagian belakang printer sudah dicuci/dikeringkan,")
    print("      atau pasang tabung pembuangan luar agar tinta tidak tumpah merusak meja/mesin.")
    print("-" * 64)

    if not args.force:
        confirm = input(f"Ketik 'YA' untuk mereset counter printer {model}: ")
        if confirm.strip().upper() != "YA":
            print("❌ Proses reset dibatalkan.")
            return 1

    mode = "mock" if args.mock else ("network" if args.host else "usb")
    mgr = core.PrinterManager(mode=mode, device_path=args.device, host=args.host, is_mock=args.mock)

    print(f"\n⏳ Memulai proses reset {model}...")
    try:
        res = mgr.reset_counters(model)
        print(f"💾 Backup otomatis tersimpan di: {res['backup_path']}")
        print(f"✅ {res['message']}")
        print("\n📊 Nilai counter setelah reset:")
        for c in res["counters_after"]:
            print(f"   - {c['name']}: {c['raw']} poin ({c['percent']}%)")
        print("\n🎉 RESET BERHASIL! Silakan matikan printer Anda sekarang, tunggu 5 detik, lalu nyalakan kembali.")
        return 0
    except Exception as exc:
        print(f"\n❌ Gagal mereset printer: {exc}")
        return 1


def cmd_clean(args):
    model = args.model
    if not model:
        devs = core.scan_printers(include_mock=args.mock)
        if devs and devs[0].get("detected_model"):
            model = devs[0]["detected_model"]
            print(f"ℹ️  Model terdeteksi otomatis: {model}")
    if not model:
        print("❌ Model printer harus ditentukan dengan --model [MODEL]")
        return 1
    model = model.upper()
    mode = "mock" if args.mock else ("network" if args.host else "usb")
    mgr = core.PrinterManager(mode=mode, device_path=args.device, host=args.host, is_mock=args.mock)
    print(f"🚿 Mengirim perintah Head Cleaning ke printer {model}...")
    try:
        mgr.clean_head(model)
        print("✅ Perintah Head Cleaning berhasil dikirim!")
        print("ℹ️  Printer sedang memompa tinta untuk membersihkan nozzle. Tunggu hingga motor berhenti.")
        return 0
    except Exception as exc:
        print(f"❌ Gagal mengirim perintah Head Cleaning: {exc}")
        return 1


def cmd_nozzle(args):
    model = args.model
    if not model:
        devs = core.scan_printers(include_mock=args.mock)
        if devs and devs[0].get("detected_model"):
            model = devs[0]["detected_model"]
            print(f"ℹ️  Model terdeteksi otomatis: {model}")
    if not model:
        print("❌ Model printer harus ditentukan dengan --model [MODEL]")
        return 1
    model = model.upper()
    mode = "mock" if args.mock else ("network" if args.host else "usb")
    mgr = core.PrinterManager(mode=mode, device_path=args.device, host=args.host, is_mock=args.mock)
    print(f"📄 Mengirim perintah Cetak Nozzle Check ke printer {model}...")
    try:
        mgr.nozzle_check(model)
        print("✅ Perintah Cetak Nozzle Check berhasil dikirim!")
        print("ℹ️  Pastikan kertas sudah dimasukkan. Printer sedang mencetak pola uji.")
        return 0
    except Exception as exc:
        print(f"❌ Gagal mengirim perintah Nozzle Check: {exc}")
        return 1


def main():
    parser = argparse.ArgumentParser(
        description="Epson Waste Ink Pad Resetter untuk Linux (L120, L3110, L3210)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    subparsers = parser.add_subparsers(dest="command")

    # Command: gui
    p_gui = subparsers.add_parser("gui", help="Buka antarmuka grafis desktop (GUI)")
    p_gui.add_argument("--tk", action="store_true", help="Gunakan antarmuka Tkinter (mode Windows/ringan)")

    # Command: scan
    p_scan = subparsers.add_parser("scan", help="Pindai printer Epson USB yang tersambung")
    p_scan.add_argument("--mock", action="store_true", help="Sertakan opsi simulasi/demo")

    # Command: check
    p_check = subparsers.add_parser("check", help="Periksa status kepenuhan bantalan tinta")
    p_check.add_argument("-m", "--model", choices=list(MODELS.keys()), help="Model printer")
    p_check.add_argument("-d", "--device", help="Path perangkat USB (misal /dev/usb/lp0)")
    p_check.add_argument("--host", help="IP address printer (untuk network/Wi-Fi)")
    p_check.add_argument("--mock", action="store_true", help="Gunakan mode simulasi/demo")

    # Command: backup
    p_backup = subparsers.add_parser("backup", help="Simpan backup EEPROM counter ke file JSON")
    p_backup.add_argument("-m", "--model", choices=list(MODELS.keys()), required=True, help="Model printer")
    p_backup.add_argument("-d", "--device", help="Path perangkat USB")
    p_backup.add_argument("--host", help="IP address printer")
    p_backup.add_argument("-o", "--output", help="Path file output backup (.json)")
    p_backup.add_argument("--mock", action="store_true", help="Gunakan mode simulasi")

    # Command: reset
    p_reset = subparsers.add_parser("reset", help="Reset waste ink pad counter ke 0%%")
    p_reset.add_argument("-m", "--model", choices=list(MODELS.keys()), help="Model printer")
    p_reset.add_argument("-d", "--device", help="Path perangkat USB")
    p_reset.add_argument("--host", help="IP address printer")
    p_reset.add_argument("--force", action="store_true", help="Jangan minta konfirmasi 'YA'")
    p_reset.add_argument("--mock", action="store_true", help="Gunakan mode simulasi")

    # Command: clean
    p_clean = subparsers.add_parser("clean", help="Jalankan siklus pembersihan head (Head Cleaning)")
    p_clean.add_argument("-m", "--model", choices=list(MODELS.keys()), help="Model printer")
    p_clean.add_argument("-d", "--device", help="Path perangkat USB")
    p_clean.add_argument("--host", help="IP address printer")
    p_clean.add_argument("--mock", action="store_true", help="Gunakan mode simulasi")

    # Command: nozzle
    p_nozzle = subparsers.add_parser("nozzle", help="Cetak pola uji nozzle check (Nozzle Check Pattern)")
    p_nozzle.add_argument("-m", "--model", choices=list(MODELS.keys()), help="Model printer")
    p_nozzle.add_argument("-d", "--device", help="Path perangkat USB")
    p_nozzle.add_argument("--host", help="IP address printer")
    p_nozzle.add_argument("--mock", action="store_true", help="Gunakan mode simulasi")

    args = parser.parse_args()

    if not args.command or args.command == "gui":
        force_tk = getattr(args, "tk", False) or sys.platform == "win32"
        if not force_tk:
            try:
                import gui
                return gui.run_gui() or 0
            except Exception as e:
                try:
                    import gui_tk
                    return gui_tk.run_tk_gui() or 0
                except Exception:
                    pass
        else:
            try:
                import gui_tk
                return gui_tk.run_tk_gui() or 0
            except Exception as e:
                print(f"Error membuka Tkinter GUI: {e}", file=sys.stderr)
                return 1

    if args.command == "scan":
        return cmd_scan(args)
    elif args.command == "check":
        return cmd_check(args)
    elif args.command == "backup":
        return cmd_backup(args)
    elif args.command == "reset":
        return cmd_reset(args)
    elif args.command == "clean":
        return cmd_clean(args)
    elif args.command == "nozzle":
        return cmd_nozzle(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
