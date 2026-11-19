"""
Modul database printer Epson lengkap (1,270+ model) dengan metadata ramah pengguna.
Mendukung Epson L120, L3110, L3210, seluruh seri L, ET, XP, WF, dan lainnya.
"""

from __future__ import annotations

import re
from typing import Dict, Any, List, Optional, Tuple

# Coba impor database lengkap 1,271 model jika ada
try:
    from models_db import MODELS as ALL_MODELS_DB
except ImportError:
    ALL_MODELS_DB = {}

# Daftar model populer yang sering digunakan (termasuk L120, L3110, L3210)
POPULAR_MODELS = [
    "L120",
    "L3110",
    "L3210",
    "L1110",
    "L1210",
    "L210",
    "L220",
    "L300",
    "L310",
    "L350",
    "L355",
    "L360",
    "L365",
    "L380",
    "L385",
    "L455",
    "L485",
    "L550",
    "L565",
    "L655",
    "L800",
    "L805",
    "L850",
    "L1300",
    "L1800",
    "L3100",
    "L3150",
    "L3160",
    "L3200",
    "L3250",
    "L3260",
    "L4150",
    "L4160",
    "L5190",
    "L5290",
    "L6160",
    "L6170",
    "L6190",
    "ET-2710",
    "ET-2720",
    "ET-2810",
    "ET-2820",
    "XP-200",
    "XP-2100",
    "WF-2830",
]

# Metadata nama tampilan dan label counter untuk model-model utama
CURATED_PROFILES: Dict[str, Dict[str, Any]] = {
    "L120": {
        "display_name": "Epson L120",
        "family": "L-Series Legacy",
        "read_key": [146, 3],
        "write_key": b"Rudbecia",
        "reset": {24: 0, 25: 0, 28: 0, 29: 0, 46: 94, 30: 0},
        "counters": [
            {
                "id": "main",
                "name": "Bantalan Tinta Utama (Main Waste Pad)",
                "cells": [24, 25],
                "divisor": 62.0,
                "max_pts": 6200,
            },
            {
                "id": "platen",
                "name": "Bantalan Pembuangan Platen (Platen Pad)",
                "cells": [30],
                "divisor": 10.0,
                "max_pts": 1000,
            },
        ],
    },
    "L3110": {
        "display_name": "Epson L3110 Series (L3100 / L3110 / L3150)",
        "family": "EcoTank L3100 Series",
        "read_key": [151, 7],
        "write_key": b"Maribaya",
        "reset": {
            28: 0, 47: 0, 48: 0, 49: 0, 50: 0, 51: 0, 52: 0, 53: 0, 54: 94, 55: 94
        },
        "counters": [
            {
                "id": "main",
                "name": "Bantalan Tinta Utama (Main Waste Pad)",
                "cells": [48, 49],
                "divisor": 63.46,
                "max_pts": 6346,
            },
            {
                "id": "platen",
                "name": "Bantalan Cetak Tanpa Tepi (Borderless Pad)",
                "cells": [50, 51],
                "divisor": 34.16,
                "max_pts": 3416,
            },
        ],
    },
    "L3210": {
        "display_name": "Epson L3210 Series (L3200 / L3210 / L3250 / L1210)",
        "family": "EcoTank L3200 Series",
        "read_key": [74, 54],
        "write_key": b"Maribaya",
        "reset": {
            28: 0, 47: 0, 48: 0, 49: 0, 50: 0, 51: 0, 52: 0, 53: 0, 54: 94, 55: 94,
            252: 0, 253: 0, 254: 0, 255: 94
        },
        "counters": [
            {
                "id": "main",
                "name": "Bantalan Tinta Utama (Main Waste Pad)",
                "cells": [48, 49],
                "divisor": 63.46,
                "max_pts": 6346,
            },
            {
                "id": "platen",
                "name": "Bantalan Cetak Tanpa Tepi (Borderless Pad)",
                "cells": [50, 51],
                "divisor": 34.16,
                "max_pts": 3416,
            },
            {
                "id": "sub",
                "name": "Bantalan Tinta Tambahan (Sub Counter)",
                "cells": [252, 253],
                "divisor": None,
                "max_pts": None,
            },
        ],
    },
}


def get_model_spec(model_key: str) -> Optional[Dict[str, Any]]:
    """
    Mengambil konfigurasi lengkap (read_key, write_key, reset, counters)
    baik dari model terkurasi maupun dari database 1,270+ model.
    """
    model_key = model_key.strip()
    
    # 1. Cek profil terkurasi
    if model_key in CURATED_PROFILES:
        return CURATED_PROFILES[model_key]

    # 2. Cek database lengkap
    if model_key in ALL_MODELS_DB:
        raw = ALL_MODELS_DB[model_key]
        
        # Susun daftar counter yang ramah pengguna
        counters = []
        raw_counters = raw.get("counters", [])
        for idx, item in enumerate(raw_counters):
            c_name = item[0]
            cells = item[1]
            divisor = item[2] if len(item) > 2 else None

            # Buat nama deskriptif
            if idx == 0 or "main" in c_name.lower():
                display_label = "Bantalan Tinta Utama (Main Pad)"
                if not divisor and len(cells) >= 2:
                    divisor = 63.0
            elif idx == 1 or "platen" in c_name.lower() or "borderless" in c_name.lower():
                display_label = "Bantalan Cetak Tanpa Tepi (Borderless / Platen)"
                if not divisor and len(cells) >= 2:
                    divisor = 34.0
            else:
                display_label = f"Bantalan Tinta Tambahan #{idx+1} ({c_name})"

            counters.append({
                "id": f"waste{idx}",
                "name": display_label,
                "cells": cells,
                "divisor": divisor,
                "max_pts": int(divisor * 100) if divisor else (1000 if len(cells) == 1 else 6300),
            })

        return {
            "display_name": f"Epson {model_key}",
            "family": "Epson Series",
            "read_key": raw["read_key"],
            "write_key": raw["write_key"],
            "reset": raw["reset"],
            "counters": counters,
        }

    return None


def get_all_model_keys() -> List[str]:
    """Mengembalikan seluruh daftar model yang tersedia (diurutkan alfabet)."""
    keys = set(CURATED_PROFILES.keys())
    keys.update(ALL_MODELS_DB.keys())
    return sorted(list(keys), key=lambda x: (x not in POPULAR_MODELS, x))


def search_models(query: str, limit: int = 50) -> List[str]:
    """Mencari model berdasarkan kata kunci pencarian."""
    if not query:
        return POPULAR_MODELS[:limit]
    q = query.upper().replace(" ", "").replace("-", "").replace("EPSON", "")
    results = []
    
    # Prioritaskan popular models
    for m in POPULAR_MODELS:
        norm_m = m.upper().replace("-", "")
        if q in norm_m:
            results.append(m)

    # Tambahkan dari all models
    all_keys = get_all_model_keys()
    for m in all_keys:
        if m not in results:
            norm_m = m.upper().replace("-", "")
            if q in norm_m:
                results.append(m)
                if len(results) >= limit:
                    break
    return results


def detect_model(device_name: str) -> Optional[str]:
    """Mendeteksi kunci model dari string perangkat USB atau hostname."""
    if not device_name:
        return None
    s = device_name.upper().replace("-", "")
    
    # 1. Cek model populer
    for pm in POPULAR_MODELS:
        norm_pm = pm.upper().replace("-", "")
        if norm_pm in s:
            return pm

    # 2. Cek database lengkap
    for k in ALL_MODELS_DB.keys():
        norm_k = k.upper().replace("-", "")
        if len(norm_k) >= 3 and norm_k in s:
            return k

    return None


def decode_counter_value(cell_values: Dict[int, int], counter_def: Dict[str, Any]) -> Dict[str, Any]:
    """Menghitung poin mentah dan persentase kepenuhan counter dari byte EEPROM."""
    cells = list(counter_def["cells"])
    # Normalisasi jika ada format lama yang mencantumkan sel 47 di posisi ke-3
    if len(cells) == 3 and cells[2] == 47 and cells[0] in (48, 50):
        cells = [cells[0], cells[1]]

    raw = 0
    for i, c in enumerate(cells):
        val = cell_values.get(c, 0)
        if val is None:
            val = 0
        raw += (int(val) << (8 * i))
    
    divisor = counter_def.get("divisor")
    max_pts = counter_def.get("max_pts")
    
    if divisor:
        pct = round(raw / float(divisor), 1)
    elif max_pts:
        pct = round((raw / float(max_pts)) * 100.0, 1)
    else:
        pct = 0.0
        
    pct = max(0.0, pct)
    limit = max_pts or (int(divisor * 100) if divisor else 6346)
    
    return {
        "id": counter_def["id"],
        "name": counter_def["name"],
        "raw": raw,
        "max": limit,
        "percent": pct,
        "is_full": pct >= 100.0 or raw >= limit,
        "is_warning": pct >= 80.0,
    }


# Backwards compatibility dictionary
MODELS = {k: get_model_spec(k) for k in get_all_model_keys()}
