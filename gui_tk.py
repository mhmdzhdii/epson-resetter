#!/usr/bin/env python3
"""
Antarmuka Grafis (GUI) berbasis Tkinter yang ringan dan kompatibel penuh dengan OS Windows, Linux, dan macOS.
Mendukung 1,270+ model printer Epson termasuk L120, L3110, L3210, L360, L805, L1800, dll.
"""

from __future__ import annotations

import os
import sys
import threading
import time
from typing import Dict, Any, List, Optional

# Tambahkan direktori modul
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tkinter as tk
from tkinter import ttk, messagebox, filedialog

import models
import core


class TkResetterApp:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.root.title("Epson Waste Ink Pad Resetter (Windows & Linux)")
        self.root.geometry("680x760")
        self.root.minsize(580, 680)

        # Style TTK
        self.style = ttk.Style()
        try:
            if "clam" in self.style.theme_names():
                self.style.theme_use("clam")
        except Exception:
            pass

        self.scanned_devices: List[Dict[str, Any]] = []
        self.current_model = "L3110"
        self.all_models = models.get_all_model_keys()

        self._configure_styles()
        self._build_ui()

        # Mulai pemindaian awal di background
        self.root.after(200, self.refresh_devices)

    def _configure_styles(self):
        self.style.configure("Header.TLabel", font=("Segoe UI", 16, "bold"), foreground="#1a5fb4")
        self.style.configure("SubHeader.TLabel", font=("Segoe UI", 10), foreground="#5e5c64")
        self.style.configure("Card.TLabelframe", padding=10)
        self.style.configure("Card.TLabelframe.Label", font=("Segoe UI", 10, "bold"), foreground="#241f31")
        self.style.configure("Accent.TButton", font=("Segoe UI", 10, "bold"), padding=6)
        self.style.configure("Reset.TButton", font=("Segoe UI", 10, "bold"), foreground="#c01c28", padding=6)
        self.style.configure("StatusGreen.TLabel", font=("Segoe UI", 10, "bold"), foreground="#26a269")
        self.style.configure("StatusRed.TLabel", font=("Segoe UI", 10, "bold"), foreground="#c01c28")
        self.style.configure("StatusYellow.TLabel", font=("Segoe UI", 10, "bold"), foreground="#e5a50a")

    def _build_ui(self):
        main_frame = ttk.Frame(self.root, padding=16)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # -------------------------------------------------------------
        # 1. Header Frame
        # -------------------------------------------------------------
        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=(0, 10))

        lbl_title = ttk.Label(header_frame, text="Epson Waste Ink Pad Resetter", style="Header.TLabel")
        lbl_title.pack(anchor=tk.W)

        lbl_sub = ttk.Label(
            header_frame,
            text="Kompatibel: Windows & Linux • Mendukung 1,270+ Model Epson (L120, L3110, L3210, dll.)",
            style="SubHeader.TLabel",
        )
        lbl_sub.pack(anchor=tk.W, pady=(2, 0))

        # -------------------------------------------------------------
        # 2. Peringatan Keselamatan Fisik
        # -------------------------------------------------------------
        warn_frame = tk.Frame(main_frame, bg="#fef6e0", bd=1, relief=tk.SOLID, padx=10, pady=8)
        warn_frame.pack(fill=tk.X, pady=(0, 12))

        lbl_warn = tk.Label(
            warn_frame,
            text="⚠️ PERINGATAN FISIK: Reset software HANYA menghapus batas counter digital di memori.\n"
                 "Pastikan busa pembuangan tinta fisik di belakang printer sudah dicuci/dikeringkan/diganti\n"
                 "atau buatkan botol pembuangan luar agar tinta buangan tidak tumpah merusak meja!",
            bg="#fef6e0",
            fg="#8f5b00",
            font=("Segoe UI", 9, "bold"),
            justify=tk.LEFT,
        )
        lbl_warn.pack(anchor=tk.W)

        # -------------------------------------------------------------
        # 3. Frame Pemilihan Model & Koneksi
        # -------------------------------------------------------------
        conn_frame = ttk.LabelFrame(main_frame, text=" 1. Koneksi & Model Printer ", style="Card.TLabelframe")
        conn_frame.pack(fill=tk.X, pady=(0, 10))

        # Radio Mode
        mode_box = ttk.Frame(conn_frame)
        mode_box.pack(fill=tk.X, pady=(0, 8))

        ttk.Label(mode_box, text="Mode:", font=("Segoe UI", 9, "bold")).pack(side=tk.LEFT, padx=(0, 8))
        self.var_mode = tk.StringVar(value="usb")
        r_usb = ttk.Radiobutton(mode_box, text="Kabel USB", variable=self.var_mode, value="usb", command=self._on_mode_change)
        r_usb.pack(side=tk.LEFT, padx=6)
        r_net = ttk.Radiobutton(mode_box, text="Jaringan (IP Wi-Fi)", variable=self.var_mode, value="network", command=self._on_mode_change)
        r_net.pack(side=tk.LEFT, padx=6)
        r_mock = ttk.Radiobutton(mode_box, text="Mode Demo (Simulasi)", variable=self.var_mode, value="mock", command=self._on_mode_change)
        r_mock.pack(side=tk.LEFT, padx=6)

        # Baris Perangkat USB
        self.dev_row = ttk.Frame(conn_frame)
        self.dev_row.pack(fill=tk.X, pady=3)

        ttk.Label(self.dev_row, text="Printer USB:", width=14).pack(side=tk.LEFT)
        self.cb_device = ttk.Combobox(self.dev_row, state="readonly", width=42)
        self.cb_device.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8))
        self.cb_device.bind("<<ComboboxSelected>>", self._on_device_selected)

        btn_scan = ttk.Button(self.dev_row, text="🔄 Pindai USB", command=self.refresh_devices)
        btn_scan.pack(side=tk.LEFT)

        # Baris IP Address (Network)
        self.ip_row = ttk.Frame(conn_frame)
        ttk.Label(self.ip_row, text="Alamat IP:", width=14).pack(side=tk.LEFT)
        self.ent_ip = ttk.Entry(self.ip_row, width=28)
        self.ent_ip.insert(0, "192.168.1.100")
        self.ent_ip.pack(side=tk.LEFT, padx=(0, 8))
        ttk.Label(self.ip_row, text="(Port SNMP 161)").pack(side=tk.LEFT)

        # Baris Pencarian & Pemilihan Model
        model_row = ttk.Frame(conn_frame)
        model_row.pack(fill=tk.X, pady=6)

        ttk.Label(model_row, text="Cari Model:", width=14).pack(side=tk.LEFT)
        self.ent_search = ttk.Entry(model_row, width=16)
        self.ent_search.pack(side=tk.LEFT, padx=(0, 8))
        self.ent_search.bind("<KeyRelease>", self._on_search_key)

        ttk.Label(model_row, text="Pilih Model:").pack(side=tk.LEFT, padx=(0, 6))
        self.cb_model = ttk.Combobox(model_row, state="readonly", width=26)
        self.cb_model.pack(side=tk.LEFT, fill=tk.X, expand=True)
        self.cb_model.bind("<<ComboboxSelected>>", self._on_model_selected)

        self._populate_models_list()

        # -------------------------------------------------------------
        # 4. Frame Status Bantalan Tinta
        # -------------------------------------------------------------
        status_frame = ttk.LabelFrame(main_frame, text=" 2. Status Bantalan Pembuangan Tinta ", style="Card.TLabelframe")
        status_frame.pack(fill=tk.X, pady=(0, 10))

        # Status Label
        st_row = ttk.Frame(status_frame)
        st_row.pack(fill=tk.X, pady=(0, 6))
        ttk.Label(st_row, text="Kondisi Mesin:", width=14).pack(side=tk.LEFT)
        self.lbl_status_badge = ttk.Label(st_row, text="Belum Dibaca (Klik 'Baca Counter')", style="SubHeader.TLabel")
        self.lbl_status_badge.pack(side=tk.LEFT)

        # Counter 1: Main Pad
        main_c_frame = ttk.Frame(status_frame)
        main_c_frame.pack(fill=tk.X, pady=4)
        self.lbl_main_name = ttk.Label(main_c_frame, text="Bantalan Tinta Utama (Main Pad):", font=("Segoe UI", 9, "bold"))
        self.lbl_main_name.pack(anchor=tk.W)

        m_bar_box = ttk.Frame(main_c_frame)
        m_bar_box.pack(fill=tk.X, pady=2)
        self.prog_main = ttk.Progressbar(m_bar_box, maximum=100.0, value=0.0)
        self.prog_main.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        self.lbl_main_val = ttk.Label(m_bar_box, text="0 poin (0.0%)", width=22, anchor=tk.E)
        self.lbl_main_val.pack(side=tk.RIGHT)

        # Counter 2: Platen Pad
        plat_c_frame = ttk.Frame(status_frame)
        plat_c_frame.pack(fill=tk.X, pady=4)
        self.lbl_plat_name = ttk.Label(plat_c_frame, text="Bantalan Cetak Tanpa Tepi (Borderless / Platen):", font=("Segoe UI", 9, "bold"))
        self.lbl_plat_name.pack(anchor=tk.W)

        p_bar_box = ttk.Frame(plat_c_frame)
        p_bar_box.pack(fill=tk.X, pady=2)
        self.prog_platen = ttk.Progressbar(p_bar_box, maximum=100.0, value=0.0)
        self.prog_platen.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 10))
        self.lbl_plat_val = ttk.Label(p_bar_box, text="0 poin (0.0%)", width=22, anchor=tk.E)
        self.lbl_plat_val.pack(side=tk.RIGHT)

        # -------------------------------------------------------------
        # 5. Frame Tombol Aksi
        # -------------------------------------------------------------
        act_frame = ttk.LabelFrame(main_frame, text=" 3. Tindakan Eksekusi ", style="Card.TLabelframe")
        act_frame.pack(fill=tk.X, pady=(0, 10))

        btn_box = ttk.Frame(act_frame)
        btn_box.pack(fill=tk.X, pady=4)

        self.btn_read = ttk.Button(btn_box, text="🔍 1. Baca Counter", style="Accent.TButton", command=self.read_counter)
        self.btn_read.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

        self.btn_backup = ttk.Button(btn_box, text="💾 2. Backup EEPROM", command=self.backup_eeprom)
        self.btn_backup.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

        self.btn_reset = ttk.Button(btn_box, text="⚡ 3. Reset Counter (0%)", style="Reset.TButton", command=self.confirm_reset)
        self.btn_reset.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=4)

        # -------------------------------------------------------------
        # 6. Log Console Frame
        # -------------------------------------------------------------
        log_frame = ttk.LabelFrame(main_frame, text=" Catatan Aktivitas ", style="Card.TLabelframe")
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.txt_log = tk.Text(log_frame, height=6, bg="#ffffff", fg="#241f31", font=("Consolas", 9), relief=tk.SOLID, bd=1)
        self.txt_log.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        scroll_log = ttk.Scrollbar(log_frame, orient=tk.VERTICAL, command=self.txt_log.yview)
        scroll_log.pack(side=tk.RIGHT, fill=tk.Y)
        self.txt_log.configure(yscrollcommand=scroll_log.set)

        self._log("Aplikasi Epson Resetter siap. Mendukung 1,270+ model Epson.")

    # -----------------------------------------------------------------
    # Helper & Event Handlers
    # -----------------------------------------------------------------
    def _log(self, text: str):
        t_str = time.strftime("[%H:%M:%S] ")
        self.txt_log.insert(tk.END, t_str + text + "\n")
        self.txt_log.see(tk.END)

    def _set_busy(self, busy: bool):
        state = tk.DISABLED if busy else tk.NORMAL
        self.btn_read.configure(state=state)
        self.btn_backup.configure(state=state)
        self.btn_reset.configure(state=state)

    def _populate_models_list(self, filtered: Optional[List[str]] = None):
        if filtered is not None:
            models_to_show = filtered
        else:
            # Tampilkan model populer di atas, diikuti yang lain
            popular = models.POPULAR_MODELS
            others = [m for m in self.all_models if m not in popular]
            models_to_show = popular + others

        self.cb_model["values"] = models_to_show
        if "L3110" in models_to_show:
            self.cb_model.set("L3110")
            self.current_model = "L3110"
        elif models_to_show:
            self.cb_model.set(models_to_show[0])
            self.current_model = models_to_show[0]

    def _on_search_key(self, event):
        query = self.ent_search.get().strip()
        matched = models.search_models(query, limit=100)
        self.cb_model["values"] = matched
        if matched:
            self.cb_model.set(matched[0])
            self.current_model = matched[0]

    def _on_model_selected(self, event):
        self.current_model = self.cb_model.get().strip()
        spec = models.get_model_spec(self.current_model)
        disp = spec["display_name"] if spec else self.current_model
        self._log(f"Model dipilih: {disp}")

    def _on_mode_change(self):
        mode = self.var_mode.get()
        if mode == "usb":
            self.dev_row.pack(fill=tk.X, pady=3)
            self.ip_row.pack_forget()
            self.refresh_devices()
        elif mode == "network":
            self.dev_row.pack_forget()
            self.ip_row.pack(fill=tk.X, pady=3)
        elif mode == "mock":
            self.dev_row.pack(fill=tk.X, pady=3)
            self.ip_row.pack_forget()
            self.refresh_devices()

    def _on_device_selected(self, event):
        idx = self.cb_device.current()
        if idx >= 0 and idx < len(self.scanned_devices):
            d = self.scanned_devices[idx]
            det = d.get("detected_model")
            if det and det in self.all_models:
                self.cb_model.set(det)
                self.current_model = det
                self._log(f"Perangkat terdeteksi otomatis: {det}")

    def refresh_devices(self):
        self._set_busy(True)
        self._log("Memindai perangkat printer Epson...")
        is_mock = (self.var_mode.get() == "mock")

        def _thread():
            devs = core.scan_printers(include_mock=is_mock)
            self.root.after(0, self._update_devices_list, devs)

        threading.Thread(target=_thread, daemon=True).start()

    def _update_devices_list(self, devs: List[Dict[str, Any]]):
        self.scanned_devices = devs
        if not devs:
            self.cb_device["values"] = ["Tidak ada printer USB ditemukan"]
            self.cb_device.set("Tidak ada printer USB ditemukan")
            self._log("⚠️ Tidak ada printer USB terdeteksi. Hubungkan printer atau coba Mode Demo.")
        else:
            vals = [d["display"] for d in devs]
            self.cb_device["values"] = vals
            self.cb_device.current(0)
            self._on_device_selected(None)
            self._log(f"✅ Ditemukan {len(devs)} printer.")
        self._set_busy(False)

    def _get_manager(self) -> core.PrinterManager:
        mode = self.var_mode.get()
        if mode == "mock":
            return core.PrinterManager(mode="mock", is_mock=True)
        elif mode == "network":
            ip = self.ent_ip.get().strip()
            return core.PrinterManager(mode="network", host=ip)
        else:
            dev_path = None
            idx = self.cb_device.current()
            if idx >= 0 and idx < len(self.scanned_devices):
                dev_path = self.scanned_devices[idx]["path"]
            return core.PrinterManager(mode="usb", device_path=dev_path)

    def read_counter(self):
        self._set_busy(True)
        self._log(f"Membaca data counter untuk model {self.current_model}...")

        def _thread():
            try:
                mgr = self._get_manager()
                st = mgr.read_status(self.current_model)
                self.root.after(0, self._update_status_display, st)
            except Exception as e:
                self.root.after(0, self._show_error, f"Gagal membaca printer:\n{e}")
            finally:
                self.root.after(0, lambda: self._set_busy(False))

        threading.Thread(target=_thread, daemon=True).start()

    def _update_status_display(self, st: Dict[str, Any]):
        if st["is_full"]:
            self.lbl_status_badge.configure(text="🚨 SERVICE REQUIRED (BANTALAN TINTA PENUH)", style="StatusRed.TLabel")
        elif st["is_warning"]:
            self.lbl_status_badge.configure(text="⚠️ WASPADA (Hampir Penuh > 80%)", style="StatusYellow.TLabel")
        else:
            self.lbl_status_badge.configure(text="✅ NORMAL / AMAN", style="StatusGreen.TLabel")

        for c in st["counters"]:
            pct = c["percent"]
            max_s = f" / {c['max']}" if c.get("max") else ""
            val_text = f"{c['raw']}{max_s} poin ({pct}%)"
            
            if c["id"] == "main" or "main" in c["name"].lower() or c["id"] == "waste0":
                self.lbl_main_name.configure(text=c["name"] + ":")
                self.lbl_main_val.configure(text=val_text)
                self.prog_main["value"] = pct
            else:
                self.lbl_plat_name.configure(text=c["name"] + ":")
                self.lbl_plat_val.configure(text=val_text)
                self.prog_platen["value"] = pct

        self._log("✅ Pembacaan counter berhasil.")

    def backup_eeprom(self):
        self._set_busy(True)
        self._log("Membuat file backup EEPROM...")

        def _thread():
            try:
                mgr = self._get_manager()
                path, data = mgr.backup_eeprom(self.current_model)
                self.root.after(0, messagebox.showinfo, "Backup Berhasil", f"Data EEPROM berhasil disimpan ke:\n{path}")
                self._log(f"💾 Backup disimpan: {path}")
            except Exception as e:
                self.root.after(0, self._show_error, f"Gagal membuat backup:\n{e}")
            finally:
                self.root.after(0, lambda: self._set_busy(False))

        threading.Thread(target=_thread, daemon=True).start()

    def confirm_reset(self):
        spec = models.get_model_spec(self.current_model)
        dname = spec["display_name"] if spec else self.current_model
        
        msg = (
            f"Anda akan mereset hitungan bantalan tinta untuk {dname}.\n\n"
            "⚠️ PERINGATAN FISIK:\n"
            "Reset ini hanya menghapus memori digital di mesin.\n"
            "Pastikan busa penyerap tinta fisik di bagian belakang/bawah printer "
            "sudah dibersihkan, diganti, atau dipasang tabung pembuangan luar!\n\n"
            "Lanjutkan reset counter ke 0%?"
        )
        if messagebox.askyesno("Konfirmasi Reset Waste Ink Pad", msg, icon=messagebox.WARNING):
            self.execute_reset()

    def execute_reset(self):
        self._set_busy(True)
        self._log(f"Memulai reset counter untuk {self.current_model}...")

        def _thread():
            try:
                mgr = self._get_manager()
                res = mgr.reset_counters(self.current_model)
                self.root.after(0, self._on_reset_done, res)
            except Exception as e:
                self.root.after(0, self._show_error, f"Gagal mereset printer:\n{e}")
            finally:
                self.root.after(0, lambda: self._set_busy(False))

        threading.Thread(target=_thread, daemon=True).start()

    def _on_reset_done(self, res: Dict[str, Any]):
        self._log(f"🎉 {res['message']}")
        self.prog_main["value"] = 0.0
        self.lbl_main_val.configure(text="0 poin (0.0%)")
        self.prog_platen["value"] = 0.0
        self.lbl_plat_val.configure(text="0 poin (0.0%)")
        self.lbl_status_badge.configure(text="✅ BERHASIL DIRESET (0%)", style="StatusGreen.TLabel")

        success_msg = (
            "Bantalan tinta berhasil direset ke 0%!\n\n"
            "LANGKAH PENTING SELANJUTNYA:\n"
            "1. Matikan printer menggunakan tombol Power.\n"
            "2. Tunggu 5 - 10 detik.\n"
            "3. Nyalakan kembali printer Anda.\n\n"
            f"File backup otomatis tersimpan di:\n{res['backup_path']}"
        )
        messagebox.showinfo("Reset Berhasil! 🎉", success_msg)

    def _show_error(self, message: str):
        self._log(f"❌ Error: {message}")
        messagebox.showerror("Terjadi Kesalahan", message)


def run_tk_gui():
    root = tk.Tk()
    app = TkResetterApp(root)
    root.mainloop()


if __name__ == "__main__":
    run_tk_gui()
