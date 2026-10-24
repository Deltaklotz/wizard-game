# Wizard Game updater + launcher (called by play.bat and run_server.bat).
#   1. Brings the game up to date with the GitHub repository:
#        - in a git checkout (developers): git pull
#        - otherwise (players): downloads the latest commit as a zip if it changed since last time
#   2. Downloads Godot if it isn't next to the game yet.
#   3. Imports changed assets, then starts the game (or, with -Server, the multiplayer server).
# Works from an empty folder too: put play.bat alone in a folder and run it.
#
#   powershell -ExecutionPolicy Bypass -File update.ps1 [-Server] [-NoUpdate] [-- server arguments]

param(
	[switch]$Server,
	[switch]$NoUpdate,
	[Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # Invoke-WebRequest is very slow with the progress bar

$Repo = "Deltaklotz/wizard-game"
$Branch = "main"
$GodotVersion = "4.7.2-stable"
$Root = $PSScriptRoot
$Godot = Join-Path $Root "Godot_v$GodotVersion`_win64.exe"
$GodotConsole = Join-Path $Root "Godot_v$GodotVersion`_win64_console.exe"
$Headers = @{ "User-Agent" = "wizard-game-updater" }

function Say($text) { Write-Host "  $text" }

function Update-FromZip {
	try {
		$sha = (Invoke-RestMethod "https://api.github.com/repos/$Repo/commits/$Branch" -Headers $Headers).sha
	} catch {
		Say "Could not reach GitHub - starting the version you have."
		return $false
	}
	$versionFile = Join-Path $Root ".version"
	$current = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { "" }
	if ($sha -eq $current) {
		Say "Up to date ($($sha.Substring(0, 7)))."
		return $false
	}
	Say "Downloading update $($sha.Substring(0, 7))..."
	$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "wizard-game-update"
	if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
	New-Item -ItemType Directory $tmp | Out-Null
	$zip = Join-Path $tmp "game.zip"
	Invoke-WebRequest "https://codeload.github.com/$Repo/zip/$sha" -OutFile $zip -Headers $Headers
	Expand-Archive $zip -DestinationPath $tmp -Force
	$src = Get-ChildItem $tmp -Directory | Select-Object -First 1
	# Folders are mirrored (files removed from the game disappear too); loose files are copied.
	foreach ($item in Get-ChildItem $src.FullName) {
		$dest = Join-Path $Root $item.Name
		if ($item.PSIsContainer) {
			robocopy $item.FullName $dest /MIR /NFL /NDL /NJH /NJS /NP /XD .godot | Out-Null
			if ($LASTEXITCODE -ge 8) { throw "Copying $($item.Name) failed (robocopy $LASTEXITCODE)." }
		} else {
			Copy-Item $item.FullName $dest -Force
		}
	}
	Remove-Item $tmp -Recurse -Force
	Set-Content $versionFile $sha
	Say "Updated."
	return $true
}

function Update-Game {
	$isGit = (Test-Path (Join-Path $Root ".git")) -and (Get-Command git -ErrorAction SilentlyContinue)
	if ($isGit) {
		Say "Pulling the latest version (git)..."
		$before = git -C $Root rev-parse HEAD
		git -C $Root pull --ff-only
		if ($LASTEXITCODE -ne 0) { Say "git pull failed (local changes?) - starting the version you have." }
		return ($before -ne (git -C $Root rev-parse HEAD))
	}
	return Update-FromZip
}

function Get-Godot {
	if ((Test-Path $Godot) -and (Test-Path $GodotConsole)) { return }
	Say "Downloading Godot $GodotVersion (about 90 MB, only once)..."
	$zip = Join-Path ([System.IO.Path]::GetTempPath()) "godot-$GodotVersion.zip"
	Invoke-WebRequest "https://github.com/godotengine/godot-builds/releases/download/$GodotVersion/Godot_v$GodotVersion`_win64.exe.zip" -OutFile $zip -Headers $Headers
	Expand-Archive $zip -DestinationPath $Root -Force
	Remove-Item $zip -Force
}

Write-Host ""
Write-Host "=== Wizard Game ==="
$changed = $false
if (-not $NoUpdate) { $changed = Update-Game }
Get-Godot
if (-not (Test-Path (Join-Path $Root "project.godot"))) {
	throw "The game files are missing and could not be downloaded."
}
# Import new or changed assets (always on the first start; a few minutes then).
if ($changed -or -not (Test-Path (Join-Path $Root ".godot\imported"))) {
	Say "Importing assets (this takes a while after big updates)..."
	& $GodotConsole --headless --path $Root --import 2>&1 | Out-Null
}
if ($Server) {
	Say "Starting the server..."
	& $GodotConsole --headless --path (Join-Path $Root "server") -- @Rest
} else {
	Say "Starting the game..."
	Start-Process $Godot -ArgumentList "--path", "`"$Root`"" -WorkingDirectory $Root
}
