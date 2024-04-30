@echo off
call cmd /c flutter build apk --split-per-abi --obfuscate --split-debug-info=.\build\debug-info || exit /b
for /f "delims=" %%a in ('dir /b /s .\build\app\outputs\apk\release\*arm64-v8a*.apk 2^>nul') do call cmd /c adb install "%%a" || exit /b
call cmd /c adb shell am start -n 'pl.serpentdash.shinden_mobile/.MainActivity'
if "%~1" == "-show" start explorer.exe .\build\app\outputs\apk\release\