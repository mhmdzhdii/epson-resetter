@echo off
title Epson Waste Ink Pad Resetter (Windows Edition)
cd /d "%~dp0"

:: 1. Periksa Hak Akses Administrator
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Meminta izin Administrator untuk membuka akses port USB printer...
    powershell -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ======================================================================
echo   EPSON WASTE INK PAD RESETTER (Windows Edition)
echo   Hak Akses: ADMINISTRATOR (Port USB Hardware Siap)
echo   100%% Fitur Bawaan Windows (PowerShell ^& .NET WinForms)
echo   Mendukung 1,270+ Model Epson (L120, L3110, L3210, L360, L805, dll.)
echo ======================================================================
echo.
echo Membuka antarmuka grafis...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0EpsonResetter.ps1"
if %errorlevel% equ 0 goto end

:: Fallback jika ada Python
where python >nul 2>&1
if %errorlevel% equ 0 (
    python Epson_Resetter.py
    goto end
)

where py >nul 2>&1
if %errorlevel% equ 0 (
    py Epson_Resetter.py
    goto end
)

echo.
echo Jika aplikasi belum terbuka, silakan klik kanan file ini dan pilih 'Run as administrator'.
pause

:end
