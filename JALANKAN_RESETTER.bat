@echo off
title Epson Waste Ink Pad Resetter (Windows Native)
cd /d "%~dp0"

:: 1. Periksa Hak Akses Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Meminta izin Administrator untuk membuka akses port USB printer...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: 2. Jalankan Resetter dengan Hak Akses Hardware Penuh
echo ======================================================================
echo   EPSON WASTE INK PAD RESETTER (Windows Edition)
echo   Hak Akses: ADMINISTRATOR (Akses Port USB Hardware Aktif)
echo   100%% Fitur Bawaan Windows (PowerShell ^& .NET WinForms)
echo   Mendukung 1,270+ Model Epson (L120, L3110, L3210, L360, L805, dll.)
echo ======================================================================
echo Membuka antarmuka grafis...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0EpsonResetter.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Ada kendala saat menjalankan PowerShell.
    pause
)
