@echo off
rem Updates Wizard Game from GitHub and starts it. Also works on its own in an empty folder:
rem it then downloads the game and Godot first. Everything happens in update.ps1.
rem (One line on purpose: this file may be replaced by the update while it runs.)
cd /d "%~dp0" & (if not exist update.ps1 powershell -NoProfile -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest https://raw.githubusercontent.com/Deltaklotz/wizard-game/main/update.ps1 -OutFile update.ps1") & powershell -NoProfile -ExecutionPolicy Bypass -File update.ps1 %* & (if errorlevel 1 pause) & exit /b
