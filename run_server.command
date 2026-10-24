#!/bin/bash
# Starts the Wizard Game multiplayer server (WebSocket, default port 8910).
# Extra options: --port 8910   --seed 1234   --new-world
cd "$(dirname "$0")"
/Applications/Godot.app/Contents/MacOS/Godot --headless --path server -- "$@"
read -n 1 -s -r -p "Press any key to continue..."