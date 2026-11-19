"""
Modul inti untuk komunikasi printer Epson (USB, Network SNMP, dan Simulasi).
"""

from __future__ import annotations

import os
import json
import time
import socket
import struct
import re
from typing import Dict, Any, List, Optional, Tuple

import epson_usb
from epson_usb.printer import EpsonUsbPrinter
from epson_usb.backends import find_devices, open_mock
from epson_usb.backends.mock import MockConfig, MockTransport

from models import MODELS, detect_model, decode_counter_value


# ==============================================================================
# Helper SNMP Sederhana untuk Printer Network (L3150, L3250, dll via Wi-Fi/LAN)
# ==============================================================================
OID_PREFIX = "1.3.6.1.4.1.1248.1.2.2.44.1.1.2.1"
MODEL_NAME_OID = "1.3.6.1.4.1.1248.1.1.3.1.3.8.0"


def _ber_len(n: int) -> bytes:
    if n < 0x80:
        return bytes([n])
    out = b""
    while n:
        out = bytes([n & 0xFF]) + out
        n >>= 8
    return bytes([0x80 | len(out)]) + out


def _tlv(tag: int, value: bytes) -> bytes:
    return bytes([tag]) + _ber_len(len(value)) + value


def _ber_int(n: int) -> bytes:
    out, v = b"", n
    while True:
        out = bytes([v & 0xFF]) + out
        v >>= 8
        if (v == 0 and not (out[0] & 0x80)) or (v == -1 and (out[0] & 0x80)):
            break
    return _tlv(0x02, out)


def _ber_oid(oid_str: str) -> bytes:
    parts = [int(x) for x in oid_str.split(".")]
    body = bytes([40 * parts[0] + parts[1]])
    for p in parts[2:]:
        if p < 0x80:
            body += bytes([p])
            continue
        stack = [p & 0x7F]
        p >>= 7
        while p:
            stack.append((p & 0x7F) | 0x80)
            p >>= 7
        body += bytes(reversed(stack))
    return _tlv(0x06, body)


def _parse_tlv(data: bytes, i: int) -> Tuple[int, bytes, int]:
    tag, length = data[i], data[i + 1]
    i += 2
    if length & 0x80:
        num = length & 0x7F
        length = int.from_bytes(data[i : i + num], "big")
        i += num
    return tag, data[i : i + length], i + length


class SimpleSnmpClient:
    def __init__(self, host: str, community: str = "public", port: int = 161, timeout: float = 3.0):
        self.host = host
        self.port = port
        self.timeout = timeout
        self.community = community.encode("latin-1")
        self._rid = 0x4552

    def get(self, oid_str: str) -> bytes:
        self._rid = (self._rid + 1) & 0x7FFFFFFF
        varbind = _tlv(0x30, _ber_oid(oid_str) + _tlv(0x05, b""))
        pdu = _tlv(0xA0, _ber_int(self._rid) + _ber_int(0) + _ber_int(0) + _tlv(0x30, varbind))
        msg = _tlv(0x30, _ber_int(0) + _tlv(0x04, self.community) + pdu)
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(self.timeout)
        try:
            sock.sendto(msg, (self.host, self.port))
            data, _ = sock.recvfrom(4096)
        finally:
            sock.close()

        # Ekstrak value
        _, msg_bytes, _ = _parse_tlv(data, 0)
        i = 0
        _, _, i = _parse_tlv(msg_bytes, i)
        _, _, i = _parse_tlv(msg_bytes, i)
        _, pdu_bytes, _ = _parse_tlv(msg_bytes, i)
        j = 0
        _, _, j = _parse_tlv(pdu_bytes, j)
        _, es, j = _parse_tlv(pdu_bytes, j)
        _, _, j = _parse_tlv(pdu_bytes, j)
        _, vbs, _ = _parse_tlv(pdu_bytes, j)
        _, vb, _ = _parse_tlv(vbs, 0)
        k = 0
        _, _, k = _parse_tlv(vb, k)
        _, val, _ = _parse_tlv(vb, k)
        if int.from_bytes(es, "big"):
            raise IOError("SNMP error-status %d" % int.from_bytes(es, "big"))
        return val


# ==============================================================================
# Device Scanner
# ==============================================================================
def scan_printers(include_mock: bool = False) -> List[Dict[str, Any]]:
    """Memindai printer Epson USB yang tersambung ke komputer (Linux & Windows)."""
    devices = []
    import sys

    # 1. Pindai via epson_usb find_devices (Bekerja di Linux dan Windows USBPRINT)
    try:
        found = find_devices(vendor_id=0x04B8)
        for dev in found:
            prod_name = dev.product or "Epson USB Printer"
            det_model = detect_model(prod_name) or detect_model(dev.path)
            devices.append({
                "type": "usb",
                "backend": dev.backend,
                "path": dev.path,
                "name": prod_name,
                "serial": dev.serial,
                "detected_model": det_model,
                "display": f"{prod_name} [{dev.path}]",
            })
    except Exception:
        pass

    # 2. Di Windows: Pindai printer antrean Windows Spooler jika belum terdeteksi
    if sys.platform == "win32":
        try:
            import ctypes
            from ctypes import wintypes

            class PRINTER_INFO_2W(ctypes.Structure):
                _fields_ = [
                    ("pServerName", wintypes.LPWSTR),
                    ("pPrinterName", wintypes.LPWSTR),
                    ("pShareName", wintypes.LPWSTR),
                    ("pPortName", wintypes.LPWSTR),
                    ("pDriverName", wintypes.LPWSTR),
                    ("pComment", wintypes.LPWSTR),
                    ("pLocation", wintypes.LPWSTR),
                    ("pDevMode", ctypes.c_void_p),
                    ("pSepFile", wintypes.LPWSTR),
                    ("pPrintProcessor", wintypes.LPWSTR),
                    ("pDatatype", wintypes.LPWSTR),
                    ("pParameters", wintypes.LPWSTR),
                    ("pSecurityDescriptor", ctypes.c_void_p),
                    ("Attributes", wintypes.DWORD),
                    ("Priority", wintypes.DWORD),
                    ("DefaultPriority", wintypes.DWORD),
                    ("StartTime", wintypes.DWORD),
                    ("UntilTime", wintypes.DWORD),
                    ("Status", wintypes.DWORD),
                    ("cJobs", wintypes.DWORD),
                    ("AveragePPM", wintypes.DWORD),
                ]

            spool = ctypes.WinDLL("winspool.drv")
            needed = wintypes.DWORD()
            returned = wintypes.DWORD()
            flags = 0x00000002 | 0x00000004  # LOCAL | CONNECTIONS
            spool.EnumPrintersW(flags, None, 2, None, 0, ctypes.byref(needed), ctypes.byref(returned))
            if needed.value > 0:
                buf = ctypes.create_string_buffer(needed.value)
                if spool.EnumPrintersW(flags, None, 2, buf, needed.value, ctypes.byref(needed), ctypes.byref(returned)):
                    arr = ctypes.cast(buf, ctypes.POINTER(PRINTER_INFO_2W))
                    for i in range(returned.value):
                        pname = str(arr[i].pPrinterName)
                        if "EPSON" in pname.upper():
                            if not any(d["name"] == pname for d in devices):
                                det = detect_model(pname)
                                devices.append({
                                    "type": "winspool",
                                    "backend": "winspool",
                                    "path": pname,
                                    "name": pname,
                                    "serial": None,
                                    "detected_model": det,
                                    "display": f"{pname} (Windows Spooler)",
                                })
        except Exception:
            pass

    # 3. Di Linux: Pindai /dev/usb/lp*
    if sys.platform.startswith("linux"):
        for i in range(4):
            lp_path = f"/dev/usb/lp{i}"
            if os.path.exists(lp_path):
                if not any(d["path"] == lp_path for d in devices):
                    devices.append({
                        "type": "usb",
                        "backend": "raw",
                        "path": lp_path,
                        "name": f"USB Printer ({lp_path})",
                        "serial": None,
                        "detected_model": None,
                        "display": f"Epson RAW ({lp_path})",
                    })

    # 4. Opsi simulasi / demo jika diminta
    if include_mock:
        devices.append({
            "type": "mock",
            "backend": "mock",
            "path": "mock",
            "name": "Epson L3110 Series (Simulasi Demo)",
            "serial": "SIMULASI-9999",
            "detected_model": "L3110",
            "display": "Simulasi Printer (Mode Demo)",
        })

    return devices


# ==============================================================================
# Sesi Printer Utama
# ==============================================================================
class PrinterManager:
    """Mengelola sesi komunikasi, baca EEPROM, backup, dan reset counter."""

    def __init__(
        self,
        mode: str = "usb",
        device_path: Optional[str] = None,
        host: Optional[str] = None,
        is_mock: bool = False,
    ):
        self.mode = mode  # 'usb', 'network', atau 'mock'
        self.device_path = device_path
        self.host = host
        self.is_mock = is_mock
        self._mock_transport: Optional[MockTransport] = None
        self._mock_eeprom: Dict[int, int] = {}

    def _get_profile(self, model_key: str) -> Dict[str, Any]:
        from models import get_model_spec
        spec = get_model_spec(model_key)
        if not spec:
            raise ValueError(f"Model {model_key} tidak ditemukan di database.")
        return spec

    def _open_printer(self, profile: Dict[str, Any]) -> EpsonUsbPrinter:
        read_key = profile["read_key"]
        write_key = profile["write_key"]

        if self.is_mock or self.mode == "mock":
            if not self._mock_transport:
                # Siapkan EEPROM simulasi penuh awal (misal ~98% penuh pada L3110)
                if not self._mock_eeprom:
                    self._mock_eeprom = {
                        48: 0x80,
                        49: 0x18,
                        47: 0x00,  # ~6272 poin
                        50: 0x20,
                        51: 0x0A,  # ~2600 poin
                        24: 0x34,
                        25: 0x12,  # L120 ~4660 poin
                        30: 0x05,
                        252: 0x10,
                        253: 0x00,
                    }
                cfg = MockConfig(
                    model_name=f"{profile['display_name']} (Simulasi)",
                    serial="SIMULASI-123456",
                    device_id=f"MFG:EPSON;CMD:ESCPL2,BDC,D4;MDL:{profile['display_name']};CLS:PRINTER;DES:{profile['display_name']};".encode("ascii"),
                    read_key=tuple(read_key),
                    write_key=write_key,
                    eeprom=self._mock_eeprom,
                )
                self._mock_transport = MockTransport(cfg)
            return EpsonUsbPrinter(
                transport=self._mock_transport,
                read_key=read_key,
                write_key=write_key,
                auto_open=True,
            )

        # Mode USB Real
        if self.device_path:
            return EpsonUsbPrinter(
                device=self.device_path,
                read_key=read_key,
                write_key=write_key,
                auto_open=True,
            )
        else:
            return EpsonUsbPrinter(
                read_key=read_key,
                write_key=write_key,
                auto_open=True,
            )

    def read_status(self, model_key: str) -> Dict[str, Any]:
        """Membaca informasi printer dan tingkat kepenuhan bantalan tinta."""
        profile = self._get_profile(model_key)
        
        # 1. Mode Network SNMP
        if self.mode == "network" and self.host:
            return self._read_status_snmp(profile)

        # 2. Mode USB / Mock
        printer = self._open_printer(profile)
        with printer:
            # Ambil identifikasi perangkat
            dev_id_dict = {}
            try:
                dev_id_dict = printer.get_device_identification()
            except Exception:
                pass

            # Ambil status dan nomor seri
            serial_no = "N/A"
            try:
                st = printer.get_printer_status()
                serial_no = st.get("serial_number_info") or "N/A"
            except Exception:
                pass

            # Tentukan semua alamat cell yang perlu dibaca
            needed_addrs = set()
            for c in profile["counters"]:
                needed_addrs.update(c["cells"])
            for a in profile["reset"].keys():
                needed_addrs.add(a)

            # Baca cell EEPROM
            cells_data = {}
            for addr in sorted(needed_addrs):
                try:
                    cells_data[addr] = printer.read_cell(addr)
                except Exception as e:
                    cells_data[addr] = 0

            # Hitung counter
            counter_results = []
            for c in profile["counters"]:
                c_val = decode_counter_value(cells_data, c)
                counter_results.append(c_val)

            return {
                "success": True,
                "model_key": model_key,
                "display_name": profile["display_name"],
                "serial_number": serial_no,
                "device_id": dev_id_dict,
                "counters": counter_results,
                "cells": cells_data,
                "is_full": any(c["is_full"] for c in counter_results),
                "is_warning": any(c["is_warning"] for c in counter_results),
            }

    def _read_status_snmp(self, profile: Dict[str, Any]) -> Dict[str, Any]:
        """Membaca counter via SNMP untuk printer yang tersambung ke jaringan IP."""
        client = SimpleSnmpClient(self.host)
        read_key = profile["read_key"]
        
        # Baca Model
        try:
            detected_name = client.get(MODEL_NAME_OID).decode("latin-1", "replace").strip()
        except Exception:
            detected_name = profile["display_name"]

        # Kumpulkan sel yang diperlukan
        needed_addrs = set()
        for c in profile["counters"]:
            needed_addrs.update(c["cells"])
        for a in profile["reset"].keys():
            needed_addrs.add(a)

        cells_data = {}
        for addr in sorted(needed_addrs):
            # Frame || + read_payload
            payload = [read_key[0], read_key[1], 65, 190, 160, addr % 256, addr // 256]
            frame = b"||" + struct.pack("<H", len(payload)) + bytes(payload)
            oid = OID_PREFIX + "." + ".".join(str(b) for b in frame)
            resp = client.get(oid).decode("latin-1", "replace")
            m = re.search(r"EE:([0-9A-Fa-f]{6})", resp)
            if m:
                cells_data[addr] = int(m.group(1)[4:], 16)
            else:
                cells_data[addr] = 0

        counter_results = []
        for c in profile["counters"]:
            counter_results.append(decode_counter_value(cells_data, c))

        return {
            "success": True,
            "model_key": profile["display_name"],
            "display_name": detected_name,
            "serial_number": f"IP: {self.host}",
            "device_id": {"Model": [detected_name]},
            "counters": counter_results,
            "cells": cells_data,
            "is_full": any(c["is_full"] for c in counter_results),
            "is_warning": any(c["is_warning"] for c in counter_results),
        }

    def backup_eeprom(self, model_key: str, output_path: Optional[str] = None) -> Tuple[str, Dict[str, Any]]:
        """Membaca dan menyimpan backup data EEPROM ke file JSON sebelum direset."""
        status = self.read_status(model_key)
        profile = self._get_profile(model_key)
        
        if not output_path:
            backup_dir = os.path.expanduser("~/.local/share/epson-resetter/backups")
            os.makedirs(backup_dir, exist_ok=True)
            timestamp = time.strftime("%Y%m%d_%H%M%S")
            output_path = os.path.join(backup_dir, f"backup_{model_key}_{timestamp}.json")

        backup_content = {
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
            "model_key": model_key,
            "model_name": profile["display_name"],
            "serial_number": status.get("serial_number"),
            "counters": status.get("counters"),
            "cells": {str(k): v for k, v in status.get("cells", {}).items()},
        }

        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(backup_content, f, indent=2)

        return output_path, backup_content

    def reset_counters(self, model_key: str) -> Dict[str, Any]:
        """
        Mengeksekusi proses reset waste ink pad counter:
        1. Buat backup otomatis
        2. Tulis byte reset ke EEPROM
        3. Verifikasi pembacaan kembali
        4. Jalankan perintah service restart / refresh
        """
        profile = self._get_profile(model_key)
        
        # 1. Backup otomatis
        backup_path, _ = self.backup_eeprom(model_key)

        # 2. Tulis nilai reset
        reset_map = profile["reset"]
        cells_to_write = list(reset_map.items())

        if self.mode == "network" and self.host:
            self._reset_snmp(profile)
        else:
            printer = self._open_printer(profile)
            with printer:
                # Tulis seluruh cell reset
                printer.write_cells(cells_to_write)
                
                # Verifikasi penulisan
                mismatches = []
                for addr, expected_val in reset_map.items():
                    actual = printer.read_cell(addr)
                    if actual != expected_val:
                        mismatches.append(f"Cell {addr}: dapat {actual}, seharusnya {expected_val}")

                if mismatches:
                    raise IOError(f"Verifikasi reset gagal pada sebagian alamat:\n" + "\n".join(mismatches))

                # Update state pada mock jika mode mock
                if self.is_mock or self.mode == "mock":
                    for addr, val in reset_map.items():
                        self._mock_eeprom[addr] = val

                # Jalankan service rw jika didukung
                try:
                    printer.service_rw()
                except Exception:
                    pass

        # 3. Baca status akhir
        new_status = self.read_status(model_key)

        return {
            "success": True,
            "backup_path": backup_path,
            "counters_after": new_status.get("counters", []),
            "message": "Bantalan tinta berhasil direset ke 0%. Silakan matikan printer, tunggu 5 detik, lalu hidupkan kembali.",
        }

    def _reset_snmp(self, profile: Dict[str, Any]):
        """Reset via SNMP untuk network printer."""
        client = SimpleSnmpClient(self.host)
        read_key = profile["read_key"]
        write_key = profile["write_key"]
        reset_map = profile["reset"]

        # Caesar shift (+1) pada write_key
        caesar_key = [0 if b == 0 else (b + 1) for b in write_key]

        for addr, val in reset_map.items():
            payload = ([read_key[0], read_key[1], 66, 189, 33, addr % 256, addr // 256, val] + caesar_key)
            frame = b"||" + struct.pack("<H", len(payload)) + bytes(payload)
            oid = OID_PREFIX + "." + ".".join(str(b) for b in frame)
            resp = client.get(oid).decode("latin-1", "replace")
            if ":OK;" not in resp:
                raise IOError(f"Penulisan ke alamat {addr}={val} gagal diverifikasi via SNMP. Raw: {resp}")

    def clean_head(self, model_key: str) -> bool:
        """Kirim perintah Remote1 CH (Head Cleaning) ke printer."""
        if self.is_mock or self.mode == "mock":
            return True
        profile = self._get_profile(model_key)
        printer = self._open_printer(profile)
        with printer:
            try:
                printer.command(b"CH", b"\x00\x00")
            except Exception:
                pass
        return True

    def nozzle_check(self, model_key: str) -> bool:
        """Kirim perintah Remote1 NC (Nozzle Check) ke printer."""
        if self.is_mock or self.mode == "mock":
            return True
        profile = self._get_profile(model_key)
        printer = self._open_printer(profile)
        with printer:
            try:
                printer.command(b"NC", b"\x00\x00")
            except Exception:
                pass
        return True
