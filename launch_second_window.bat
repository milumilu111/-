@echo off
setlocal
rem Launch a SECOND game window, for testing LAN multiplayer on one PC.
rem Edit only the GODOT path below if your Godot lives somewhere else.

set "GODOT=E:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
set "PROJ=%~dp0"
set "PROJ=%PROJ:~0,-1%"

if not exist "%GODOT%" (
  echo [ERROR] Godot not found: %GODOT%
  echo Edit GODOT in this file.
  pause
  exit /b 1
)

start "" "%GODOT%" --path "%PROJ%"
exit /b 0
