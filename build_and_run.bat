@echo off
call cmd /c flutter build apk --split-per-abi --obfuscate --split-debug-info=.\build\debug-info
call cmd /c adb install .\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
call cmd /c adb shell am start -n 'pl.serpentdash.shinden_mobile/.MainActivity'