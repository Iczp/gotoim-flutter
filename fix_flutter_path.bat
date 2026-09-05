@echo off
chcp 65001 >nul
echo ???? Flutter PATH ????...
powershell -NoProfile -ExecutionPolicy Bypass -File "F:\Dev\GotoIM\gotoim-flutter\fix_flutter_path.ps1"
pause
