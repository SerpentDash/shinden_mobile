@echo off
setlocal enabledelayedexpansion

REM Build the APK
call flutter build apk --split-per-abi --obfuscate --split-debug-info=.\build\debug-info
if errorlevel 1 goto :error

REM Find and install the APK
for /f "delims=" %%a in ('dir /b /s ".\build\app\outputs\apk\release\*arm64-v8a*.apk" 2^>nul') do (
    call adb install "%%a"
    if errorlevel 1 goto :error
    set "apk_found=1"
)

if not defined apk_found (
    echo Error: ARM64 APK not found.
    goto :error
)

REM Launch the app
call adb shell am start -n "pl.serpentdash.shinden_mobile/.MainActivity"

REM Open explorer if -show parameter is provided
if "%~1" == "-show" start explorer ".\build\app\outputs\apk\release\"

goto :eof

:error
echo An error occurred.
exit /b 1