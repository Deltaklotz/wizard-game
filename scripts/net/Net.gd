extends Node
## Multiplayer client (autoload "Net"): WebSocket connection to the server program in
## server/. Joins with a nickname and colour, receives the world seed and the shared
## terrain snapshot (or is asked to generate and upload it), then exchanges player states,
## spell casts and world events. Without a connection the game simply runs offline.

signal status_changed(text: String)
## The world can be built: world_blob holds the terrain, or must_generate is set.
signal world_ready
signal world_progress(fraction: float)
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal player_joined(info: Dictionary)
signal player_left(id: int)
## id -> [x, y, z, yaw, pitch]
signal player_states(states: Dictionary)
signal spell_cast(id: int, spell_path: String, origin: Vector3, direction: Vector3)
signal event_received(id: int, event: Dictionary)
## Items lying in the world (server-owned): spawned / taken (by = taker's id).
signal item_added(id: int, item_path: String, pos: Vector3, by: int)
signal item_removed(id: int, by: int)
## A place was discovered (by = the discoverer's id); it shows on everyone's map.
signal site_discovered(site: String, by: int)

const PROTOCOL := 1
## Bump when terrain generation changes, so a server never mixes worlds from two versions.
const WORLD_VERSION := 2
const DEFAULT_PORT := 8910
const SEND_RATE := 20.0
const CHUNK := 256 * 1024
const MAX_BUFFERED := 1 << 20
const CONNECT_TIMEOUT := 8.0

enum State { OFFLINE, CONNECTING, JOINING, LOADING, IN_GAME }

var state := State.OFFLINE
var my_id := -1
var my_name := ""
var my_color := Color.WHITE
var seed := 0
var must_generate := false
var world_blob := PackedByteArray()
## id -> {"id", "name", "color": Color, "s": last state array}
var players := {}
## Reason for the last disconnect, shown on the title screen.
var last_error := ""
## Items lying in the world: id -> {"item": path, "p": Vector3}.
var items := {}
## Sites discovered in this world (site -> true), kept by the server.
var discovered := {}

var _ws: WebSocketPeer
var _timer := 0.0
var _outbox: Array = []
var _download := PackedByteArray()
var _download_size := 0
## Server clock minus local clock (see world_time()).
var _clock_offset := 0.0
var _clock_synced := false
## Server process started from the title screen's Host page (-1 = none) and its log file.
var hosted_pid := -1
const HOSTED_LOG := "user://hosted_server.log"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Hosting from the menu: starts the server (server/ project) as a background process of this
## same Godot executable, headless, with `args` (e.g. --port 8910 --new-world). It also gets
## --quit-when-empty, so it shuts itself down if this game crashes. Returns false on failure.
func start_hosted_server(args: PackedStringArray) -> bool:
	stop_hosted_server()
	var all := PackedStringArray(["--headless", "--log-file", ProjectSettings.globalize_path(HOSTED_LOG),
		"--path", ProjectSettings.globalize_path("res://server"), "--"])
	all.append_array(args)
	all.append("--quit-when-empty")
	hosted_pid = OS.create_process(OS.get_executable_path(), all, false)
	return hosted_pid > 0


func is_hosted_server_running() -> bool:
	return hosted_pid > 0 and OS.is_process_running(hosted_pid)


## Stops the menu-hosted server (if any). Everyone on it is disconnected.
func stop_hosted_server() -> void:
	if hosted_pid > 0 and OS.is_process_running(hosted_pid):
		OS.kill(hosted_pid)
	hosted_pid = -1


## Last lines of the hosted server's log (to explain why it failed to start).
func hosted_server_log(lines := 4) -> String:
	var f := FileAccess.open(HOSTED_LOG, FileAccess.READ)
	if f == null:
		return ""
	var all := f.get_as_text().strip_edges().split("\n")
	return "\n".join(all.slice(maxi(0, all.size() - lines)))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		stop_hosted_server()


## Shared world clock in seconds: the server's uptime online (estimated from its "clock"
## messages), the local uptime offline. Moving scenery (bobbing islands, orbiting rocks) is a
## pure function of it, so it is in the same place on every client. Also the global shader
## uniform `world_time`.
func world_time() -> float:
	return Time.get_ticks_usec() / 1000000.0 + _clock_offset


## A server timestamp arrived. Messages only arrive late, never early, so the largest
## (server - local) sample is the best estimate; it decays slowly so clock drift can't stick.
func _sync_clock(server_time: float) -> void:
	var sample := server_time - Time.get_ticks_usec() / 1000000.0
	if not _clock_synced or sample > _clock_offset:
		_clock_offset = sample
		_clock_synced = true


func is_online() -> bool:
	return state != State.OFFLINE


static func parse_address(text: String) -> Array:
	var host := text.strip_edges()
	var port := DEFAULT_PORT
	for prefix in ["ws://", "wss://"]:
		host = host.trim_prefix(prefix)
	host = host.trim_suffix("/")
	if host.count(":") == 1:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	return [host if not host.is_empty() else "127.0.0.1", port if port > 0 else DEFAULT_PORT]


func connect_to_host(address: String, nickname: String, color: Color) -> void:
	leave()
	var hp := parse_address(address)
	my_name = nickname
	my_color = color
	last_error = ""
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 2 * MAX_BUFFERED
	if "heartbeat_interval" in _ws:
		_ws.set("heartbeat_interval", 5.0)
	var err := _ws.connect_to_url("ws://%s:%d" % hp)
	if err != OK:
		_fail("Invalid address.")
		return
	state = State.CONNECTING
	_timer = 0.0
	status_changed.emit("Connecting to %s:%d…" % hp)


## Closes the connection (no signal). Safe to call when offline.
func leave() -> void:
	if _ws:
		_ws.close()
	_ws = null
	state = State.OFFLINE
	my_id = -1
	must_generate = false
	world_blob = PackedByteArray()
	players.clear()
	items.clear()
	discovered.clear()
	_outbox.clear()
	# Back to the game's own balance numbers.
	Balance.reset_to_local()
	_download = PackedByteArray()
	_clock_offset = 0.0
	_clock_synced = false


## Called by the world once it is built and the player spawned.
func enter_game() -> void:
	if state == State.LOADING:
		state = State.IN_GAME


# --- Sending --------------------------------------------------------------------------

## Movement flags sent with the state (for other players' animations).
const FLAG_ON_FLOOR := 1
const FLAG_SWIMMING := 2
const FLAG_DASHING := 4
const FLAG_AIMING := 8
const FLAG_DEAD := 16
const FLAG_BURNING := 32

func send_state(pos: Vector3, yaw: float, pitch: float, flags: int = FLAG_ON_FLOOR) -> void:
	if state == State.IN_GAME:
		_send({"t": "state", "s": [pos.x, pos.y, pos.z, wrapf(yaw, -PI, PI), pitch, flags]})


func send_cast(spell_path: String, origin: Vector3, direction: Vector3) -> void:
	if state == State.IN_GAME:
		_send({"t": "cast", "spell": spell_path, "o": _vec(origin), "d": _vec(direction)})


## Generic world/map event relayed to every other player, e.g. {"kind": "map_ping", ...}.
func send_event(event: Dictionary) -> void:
	if state == State.IN_GAME:
		var msg := event.duplicate()
		msg["t"] = "event"
		_send(msg)


## Asks the server to put an item into the world (it answers with "item" to everyone).
func send_drop(item_path: String, pos: Vector3) -> void:
	if state == State.IN_GAME or state == State.LOADING:
		_send({"t": "drop", "item": item_path, "p": _vec(pos)})


## Reports a discovered site (the server tells everyone once, and remembers it).
func send_discover(site: String) -> void:
	if state == State.IN_GAME:
		_send({"t": "discover", "site": site})


## Asks to take an item; the first asker gets it ("item_gone" with their id).
func send_pickup(id: int) -> void:
	if state == State.IN_GAME:
		_send({"t": "pickup", "id": id})


func upload_world(blob: PackedByteArray) -> void:
	if not is_online():
		return
	world_blob = blob
	_send({"t": "world_begin", "size": blob.size()})
	var pos := 0
	while pos < blob.size():
		_outbox.append([false, blob.slice(pos, mini(pos + CHUNK, blob.size()))])
		pos += CHUNK
	_send({"t": "world_end"})


func _send(msg: Dictionary) -> void:
	_outbox.append([true, JSON.stringify(msg)])


static func _vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


static func _to_vec(a: Variant) -> Vector3:
	if a is Array and a.size() == 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


# --- Polling ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _clock_synced:
		_clock_offset -= delta * 0.002
	RenderingServer.global_shader_parameter_set("world_time", world_time())
	if _ws == null:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_timer += delta
			if _timer > CONNECT_TIMEOUT:
				_fail("No server answered. Check the address and that the server is running.")
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				state = State.JOINING
				status_changed.emit("Joining…")
				_ws.send_text(JSON.stringify({"t": "hello", "v": PROTOCOL, "world": WORLD_VERSION,
					"name": my_name, "color": my_color.to_html(false)}))
			while _ws and _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet()
				if _ws.was_string_packet():
					var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
					if msg is Dictionary and msg.has("t"):
						_handle(msg)
				else:
					_download.append_array(pkt)
					if _download_size > 0:
						world_progress.emit(float(_download.size()) / _download_size)
			if _ws:
				_flush()
		WebSocketPeer.STATE_CLOSED:
			var reason := _ws.get_close_reason()
			if state == State.CONNECTING:
				_fail("Could not connect. Check the address and that the server is running.")
			elif state == State.JOINING or state == State.LOADING:
				_fail(last_error if not last_error.is_empty() else "The server closed the connection.")
			else:
				_lost("Lost connection to the server." + (" (%s)" % reason if not reason.is_empty() else ""))


func _flush() -> void:
	while not _outbox.is_empty() and _ws.get_current_outbound_buffered_amount() < MAX_BUFFERED:
		var item: Array = _outbox.pop_front()
		if item[0]:
			_ws.send_text(item[1])
		else:
			_ws.send(item[1], WebSocketPeer.WRITE_MODE_BINARY)


func _fail(reason: String) -> void:
	leave()
	last_error = reason
	connection_failed.emit(reason)


func _lost(reason: String) -> void:
	leave()
	last_error = reason
	disconnected.emit(reason)


func _handle(msg: Dictionary) -> void:
	match str(msg["t"]):
		"welcome":
			my_id = int(msg["id"])
			seed = int(msg["seed"])
			if msg.has("time"):
				_sync_clock(float(msg["time"]))
			my_name = str(msg.get("name", my_name))
			state = State.LOADING
			for p in msg.get("players", []):
				_add_player(p)
			var balance: Variant = msg.get("balance", {})
			if balance is Dictionary and not balance.is_empty():
				Balance.apply(balance)
			items.clear()
			for it in msg.get("items", []):
				if it is Dictionary:
					items[int(it.get("id", -1))] = {"item": str(it.get("item", "")), "p": _to_vec(it.get("p"))}
			discovered.clear()
			for site in msg.get("discovered", []):
				discovered[str(site)] = true
			match str(msg.get("world", "")):
				"generate":
					must_generate = true
					status_changed.emit("Joined. You shape the world for everyone…")
					world_ready.emit()
				"wait":
					status_changed.emit("Joined. Another wizard is still shaping the world…")
				_:
					status_changed.emit("Joined. Receiving the world…")
		"reject":
			last_error = str(msg.get("reason", "Rejected by the server."))
		"world_generate":
			if world_blob.is_empty():
				must_generate = true
				status_changed.emit("You shape the world for everyone…")
				world_ready.emit()
		"world_begin":
			_download = PackedByteArray()
			_download_size = int(msg.get("size", 0))
			status_changed.emit("Receiving the world…")
		"world_end":
			world_blob = _download
			_download = PackedByteArray()
			world_ready.emit()
		"join":
			var info := _add_player(msg)
			player_joined.emit(info)
		"leave":
			var id := int(msg["id"])
			players.erase(id)
			player_left.emit(id)
		"states":
			var out := {}
			for s in msg.get("s", []):
				if s is Array and (s.size() == 6 or s.size() == 7):
					var id := int(s[0])
					if id != my_id and players.has(id):
						out[id] = s.slice(1)
						players[id]["s"] = out[id]
			if not out.is_empty():
				player_states.emit(out)
		"clock":
			_sync_clock(float(msg.get("time", 0.0)))
		"cast":
			spell_cast.emit(int(msg.get("id", -1)), str(msg.get("spell", "")), _to_vec(msg.get("o")), _to_vec(msg.get("d")))
		"event":
			event_received.emit(int(msg.get("id", -1)), msg)
		"item":
			var iid := int(msg.get("id", -1))
			var pos := _to_vec(msg.get("p"))
			items[iid] = {"item": str(msg.get("item", "")), "p": pos}
			item_added.emit(iid, str(msg.get("item", "")), pos, int(msg.get("by", -1)))
		"discovered":
			var site := str(msg.get("site", ""))
			discovered[site] = true
			site_discovered.emit(site, int(msg.get("by", -1)))
		"item_gone":
			var iid := int(msg.get("id", -1))
			items.erase(iid)
			item_removed.emit(iid, int(msg.get("by", -1)))


func _add_player(p: Dictionary) -> Dictionary:
	var info := {"id": int(p["id"]), "name": str(p.get("name", "Wizard")),
		"color": Color.html(str(p.get("color", "ffffff"))), "s": p.get("s", [])}
	players[info.id] = info
	return info
