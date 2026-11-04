@echo off
chcp 65001 >nul
rem 双开：再开一个游戏窗口，用来在本机测试联机。
rem 需要改的地方只有下面两行：Godot 可执行文件路径、项目路径。

set "GODOT=E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJ=%~dp0"

if not exist "%GODOT%" (
  echo 找不到 Godot：%GODOT%
  echo 请把 bat 里的 GODOT 改成你自己的路径。
  pause
  exit /b 1
)

start "" "%GODOT%" --path "%PROJ%"
exit
