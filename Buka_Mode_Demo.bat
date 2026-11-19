@echo off
title Epson Waste Ink Resetter - Mode Simulasi Demo
cd /d "%~dp0"
echo ======================================================================
echo   EPSON WASTE INK PAD RESETTER (Mode Demo / Simulasi Windows)
echo   100%% Berjalan dengan Komponen Bawaan Windows (PowerShell)
echo ======================================================================
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& '%~dp0EpsonResetter.ps1' -Action gui -Mock"
if %errorlevel% neq 0 (
    pause
)
