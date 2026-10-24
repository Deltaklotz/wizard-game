#!/bin/bash
# macOS: starts the Wizard Game multiplayer server headless (WebSocket, default port 8910), after
# updating the game like play.command does. Players can also host from the game's Host page instead.
# Extra options: --port 8910   --seed 1234   --new-world   --reset-discovered   --balance path/to/balance.cfg
cd "$(dirname "$0")"
bash update.sh --server "$@"
read -n 1 -s -r -p "Press any key to continue..."
