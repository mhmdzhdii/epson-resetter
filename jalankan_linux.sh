#!/usr/bin/env bash
# ==============================================================================
# Epson Waste Ink Pad Resetter - Interactive Linux Launcher
# ==============================================================================

set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Periksa hak akses root untuk komunikasi langsung hardware USB
if [ "$EUID" -ne 0 ]; then
    echo "=================================================================="
    echo "  EPSON WASTE INK PAD RESETTER (LINUX EDITION)"
    echo "=================================================================="
    echo "ℹ️  Komunikasi port fisik USB printer di Linux membutuhkan akses root/sudo."
    echo "Meminta izin sudo..."
    exec sudo -E "$0" "$@"
fi

show_menu() {
    clear
    echo "=================================================================="
    echo "     EPSON WASTE INK PAD RESETTER - LINUX INTERACTIVE MENU"
    echo "           Mendukung 1,270+ Model Epson (L120, L3110, dll)"
    echo "=================================================================="
    echo " 1. 🔍 Pindai Printer Terhubung (Scan USB)"
    echo " 2. 📊 Periksa Counter Bantalan Tinta (Check Counter)"
    echo " 3. ⚡ Reset Counter Bantalan Tinta ke 0% (Reset)"
    echo " 4. 💾 Backup Sel Memori EEPROM (Backup Data)"
    echo " 5. 🚿 Jalankan Head Cleaning (Pembersihan Nozzle)"
    echo " 6. 📄 Cetak Pola Uji Nozzle (Nozzle Check Pattern)"
    echo " 7. 🖥️  Buka Antarmuka Grafis Desktop (GUI Tkinter)"
    echo " 8. 🧪 Mode Uji Coba / Demo (Simulasi Tanpa Printer Fisik)"
    echo " 9. 🚪 Keluar"
    echo "=================================================================="
    echo -n "Pilih menu [1-9]: "
}

ask_model() {
    echo ""
    echo -n "Ketikkan model printer Anda (contoh: L120, L3110, L3210): "
    read -r MODEL_INPUT
    MODEL_INPUT=$(echo "$MODEL_INPUT" | tr '[:lower:]' '[:upper:]' | tr -d ' ')
    if [ -z "$MODEL_INPUT" ]; then
        MODEL_INPUT="L120"
        echo "Default menggunakan: L120"
    fi
}

while true; do
    show_menu
    read -r CHOICE
    case "$CHOICE" in
        1)
            echo ""
            python3 cli.py scan
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        2)
            ask_model
            echo ""
            python3 cli.py check --model "$MODEL_INPUT"
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        3)
            ask_model
            echo ""
            python3 cli.py reset --model "$MODEL_INPUT"
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        4)
            ask_model
            echo ""
            python3 cli.py backup --model "$MODEL_INPUT"
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        5)
            ask_model
            echo ""
            python3 cli.py clean --model "$MODEL_INPUT"
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        6)
            ask_model
            echo ""
            python3 cli.py nozzle --model "$MODEL_INPUT"
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        7)
            echo ""
            echo "Membuka antarmuka grafis (GUI)..."
            python3 Epson_Resetter.py gui || python3 gui_tk.py || echo "⚠️  Gagal membuka GUI. Pastikan sesi X11/Wayland aktif."
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        8)
            echo ""
            echo "Menjalankan simulasi demo untuk model L120..."
            python3 cli.py check --mock --model L120
            echo ""
            echo "Simulasi reset demo..."
            python3 cli.py reset --mock --model L120 --force
            echo ""
            read -rp "Tekan Enter untuk kembali ke menu..."
            ;;
        9)
            echo "Terima kasih telah menggunakan Epson Resetter."
            exit 0
            ;;
        *)
            echo "Pilihan tidak valid."
            sleep 1
            ;;
    esac
done
