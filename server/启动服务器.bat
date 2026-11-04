@echo off
chcp 65001 >nul
cd /d "%~dp0"
echo ============================================
echo   异形入侵 - 联机中转服务器
echo ============================================
echo.
echo 本机地址（把下面这些填给对方）：
powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*'} | ForEach-Object { '   {0}  ({1})' -f $_.IPAddress, $_.InterfaceAlias }"
echo.
echo 对方在游戏里填：  ws://这里选一个IP:7788
echo 这个窗口关掉 = 服务器停止。
echo.
node relay.mjs %1
pause
