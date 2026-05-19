@echo off
:: Utilitzem l'ordre per a UTF-8 al principi de tot
chcp 65001 >nul

:: Titon sense caracters especials per evitar errors de lectura del fitxer
title Llantzador ExportaChrome v1.1

setlocal enabledelayedexpansion

:: Anem a la carpeta on es troba el fitxer
cd /d "%~dp0"

set "scriptName=ExportaChrome.ps1"

:: Verificacio (sense accents en el codi intern)
if not exist "%scriptName%" (
    echo [ERROR] No s'ha trobat el fitxer: %scriptName%
    echo Assegura't que el .bat i el .ps1 estiguin a la mateixa carpeta.
    echo.
    pause
    exit
)

echo ==========================================
echo       Iniciant ExportaChrome v1.1
echo ==========================================
echo.
echo S'esta obrint l'interficie...
echo Si us plau, no tanquis aquesta finestra.
echo.

:: Execucio de PowerShell (Aquesta part es la mes important)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0%scriptName%"

if %errorlevel% neq 0 (
    echo.
    echo [ERROR] L'aplicacio s'ha tancat amb errors.
    pause
)
