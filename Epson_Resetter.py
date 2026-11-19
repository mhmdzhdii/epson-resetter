#!/usr/bin/env python3
"""
Epson Waste Ink Pad Resetter (Windows & Linux Universal Launcher)
"""

import os
import sys

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] != "gui":
        import cli
        sys.exit(cli.main() or 0)
    else:
        # Di Windows atau mode desktop standalone, buka Tkinter GUI
        import gui_tk
        gui_tk.run_tk_gui()
