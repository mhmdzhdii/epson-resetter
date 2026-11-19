@echo off
title Kompilasi Epson Resetter ke File EXE Native Windows
cd /d "%~dp0"
echo ======================================================================
echo   KOMPILASI EXE NATIVE WINDOWS (Menggunakan CSC Bawaan .NET Framework)
echo ======================================================================
echo.

set CSC=""
if exist "%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" (
    set CSC="%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
) else if exist "%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe" (
    set CSC="%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
)

if %CSC%=="" (
    echo [ERROR] Compiler csc.exe tidak ditemukan di direktori .NET Framework Windows.
    echo Anda tetap bisa langsung menjalankan 'JALANKAN_RESETTER.bat' tanpa kompilasi.
    pause
    exit /b 1
)

echo Menggunakan compiler C# bawaan Windows: %CSC%
echo Mengompilasi EpsonResetter.exe dengan ikon aplikasi kustom...

set ICON_FLAG=
if exist "app.ico" (
    set ICON_FLAG=/win32icon:"app.ico"
)

%CSC% /target:winexe /optimize+ %ICON_FLAG% /out:"EpsonResetter.exe" "Launcher.cs"
if %errorlevel% equ 0 (
    echo.
    echo ======================================================================
    echo   BERHASIL! File 'EpsonResetter.exe' telah dibuat!
    echo   - Sudah terpasang ikon aplikasi (app.ico)
    echo   - Otomatis meminta hak akses Administrator (UAC)
    echo   - Tidak memunculkan jendela console hitam (Silent Background)
    echo   Anda sekarang bisa langsung klik ganda 'EpsonResetter.exe'.
    echo ======================================================================
) else (
    echo.
    echo Kompilasi gagal. Gunakan file 'JALANKAN_RESETTER.bat' untuk menjalankan aplikasi.
)
echo.
pause
