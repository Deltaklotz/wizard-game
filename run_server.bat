@echo off
rem Starts the Wizard Game multiplayer server (WebSocket, default port 8910).
rem Extra options: --port 8910   --seed 1234   --new-world   --balance path\to\balance.cfg
rem seeds: 6767 4242(defaut) 6769
rem Balance numbers come from config\balance.cfg (restart the server after editing it).
cd /d "%~dp0"
Godot_v4.7.2-stable_win64_console.exe --headless --path server -- %* --seed 88 --reset-discovered
pause
