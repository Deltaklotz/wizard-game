#!/bin/bash
# Wizard Game updater + launcher for macOS and Linux (the Windows twin is update.ps1).
#   1. Brings the game up to date with the GitHub repository:
#        - in a git checkout (developers): git pull
#        - otherwise (players): downloads the latest commit as a zip if it changed since last time
#   2. Downloads Godot if it isn't next to the game yet (Godot.app on macOS, the binary on Linux).
#   3. Imports changed assets, then starts the game (or, with --server, the multiplayer server).
# Works from an empty folder too: put play.command (macOS) or this script alone in a folder and run it.
#
#   ./update.sh [--server] [--no-update] [server arguments...]

set -u
REPO="Deltaklotz/wizard-game"
BRANCH="main"
GODOT_VERSION="4.7.2-stable"
ROOT="$(cd "$(dirname "$0")" && pwd)"
UA="wizard-game-updater"

SERVER=0
NO_UPDATE=0
REST=()
for a in "$@"; do
	case "$a" in
		--server) SERVER=1 ;;
		--no-update) NO_UPDATE=1 ;;
		*) REST+=("$a") ;;
	esac
done

say() { echo "  $1"; }

if [ "$(uname)" = "Darwin" ]; then
	GODOT="$ROOT/Godot.app/Contents/MacOS/Godot"
	GODOT_ZIP="Godot_v${GODOT_VERSION}_macos.universal.zip"
else
	GODOT="$ROOT/Godot_v${GODOT_VERSION}_linux.x86_64"
	GODOT_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
fi

# Returns 0 if the game changed.
update_from_zip() {
	local sha current tmp src item
	sha=$(curl -fsSL -H "User-Agent: $UA" "https://api.github.com/repos/$REPO/commits/$BRANCH" \
		| grep -m1 '"sha"' | sed -E 's/.*"sha": *"([0-9a-f]+)".*/\1/')
	if [ -z "$sha" ]; then
		say "Could not reach GitHub - starting the version you have."
		return 1
	fi
	current=$(cat "$ROOT/.version" 2>/dev/null | tr -d '[:space:]')
	if [ "$sha" = "$current" ]; then
		say "Up to date (${sha:0:7})."
		return 1
	fi
	say "Downloading update ${sha:0:7}..."
	tmp=$(mktemp -d)
	if ! curl -fsSL -H "User-Agent: $UA" "https://codeload.github.com/$REPO/zip/$sha" -o "$tmp/game.zip"; then
		say "Download failed - starting the version you have."
		rm -rf "$tmp"
		return 1
	fi
	unzip -q "$tmp/game.zip" -d "$tmp/x"
	src=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -1)
	# Folders are mirrored (files removed from the game disappear too); loose files are copied.
	for item in "$src"/* "$src"/.[!.]*; do
		[ -e "$item" ] || continue
		if [ -d "$item" ]; then
			if command -v rsync >/dev/null 2>&1; then
				rsync -a --delete --exclude ".godot" "$item/" "$ROOT/$(basename "$item")/"
			else
				rm -rf "$ROOT/$(basename "$item")"
				cp -R "$item" "$ROOT/"
			fi
		else
			cp -f "$item" "$ROOT/"
		fi
	done
	chmod +x "$ROOT"/*.sh "$ROOT"/*.command 2>/dev/null
	rm -rf "$tmp"
	echo "$sha" > "$ROOT/.version"
	say "Updated."
	return 0
}

update_game() {
	if [ -d "$ROOT/.git" ] && command -v git >/dev/null 2>&1; then
		say "Pulling the latest version (git)..."
		local before after
		before=$(git -C "$ROOT" rev-parse HEAD)
		git -C "$ROOT" pull --ff-only || say "git pull failed (local changes?) - starting the version you have."
		after=$(git -C "$ROOT" rev-parse HEAD)
		[ "$before" != "$after" ]
		return
	fi
	update_from_zip
}

get_godot() {
	[ -x "$GODOT" ] && return
	say "Downloading Godot $GODOT_VERSION (only once)..."
	local tmp
	tmp=$(mktemp -d)
	curl -fL -H "User-Agent: $UA" \
		"https://github.com/godotengine/godot-builds/releases/download/$GODOT_VERSION/$GODOT_ZIP" -o "$tmp/godot.zip" \
		|| { echo "Could not download Godot."; exit 1; }
	unzip -q -o "$tmp/godot.zip" -d "$ROOT"
	rm -rf "$tmp"
	chmod +x "$GODOT"
	# Downloaded apps may be quarantined by macOS; this one comes straight from godotengine's releases.
	[ "$(uname)" = "Darwin" ] && xattr -dr com.apple.quarantine "$ROOT/Godot.app" 2>/dev/null
	return 0
}

echo ""
echo "=== Wizard Game ==="
CHANGED=no
if [ "$NO_UPDATE" = 0 ]; then
	update_game && CHANGED=yes
fi
get_godot
if [ ! -f "$ROOT/project.godot" ]; then
	echo "The game files are missing and could not be downloaded."
	exit 1
fi
# Import new or changed assets (always on the first start; a few minutes then).
if [ "$CHANGED" = yes ] || [ ! -d "$ROOT/.godot/imported" ]; then
	say "Importing assets (this takes a while after big updates)..."
	"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1
fi
if [ "$SERVER" = 1 ]; then
	say "Starting the server..."
	exec "$GODOT" --headless --path "$ROOT/server" -- "${REST[@]}"
fi
say "Starting the game..."
"$GODOT" --path "$ROOT" >/dev/null 2>&1 &
