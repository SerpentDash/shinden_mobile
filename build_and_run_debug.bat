@echo off
setlocal enabledelayedexpansion

set "FLUTTER=D:\Software\flutter\bin\flutter.bat"
if not exist "%FLUTTER%" set "FLUTTER=flutter"

call "%FLUTTER%" build apk --debug --split-per-abi
if errorlevel 1 goto :error

set "apk_found="
for /f "delims=" %%a in ('dir /b /s ".\build\app\outputs\flutter-apk\*arm64-v8a*debug*.apk" 2^>nul') do (
    call adb install -r "%%a"
    if errorlevel 1 goto :error
    set "apk_found=1"
)

if not defined apk_found goto :error

call adb shell am start -n "pl.serpentdash.shinden_mobile.debug/pl.serpentdash.shinden_mobile.MainActivity"
if "%~1" == "-show" start explorer ".\build\app\outputs\flutter-apk\"
goto :eof

:error
exit /b 1
