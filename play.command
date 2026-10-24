#!/bin/bash
# macOS: double-click to update Wizard Game from GitHub and start it (Linux: run ./update.sh).
# Also works on its own in an empty folder: it then downloads the game and Godot first.
# If macOS says it can't be opened, run once in Terminal:  chmod +x play.command
cd "$(dirname "$0")"
if [ ! -f update.sh ]; then
	curl -fsSL https://raw.githubusercontent.com/Deltaklotz/wizard-game/main/update.sh -o update.sh || exit 1
fi
bash update.sh "$@"
