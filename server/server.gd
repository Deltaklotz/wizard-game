extends Node
## Wizard Game server: a small WebSocket relay for local multiplayer.
##
## - Hands out the world seed. GPU terrain erosion is not bit-exact between runs or GPUs,
##   so the first player to join generates the terrain and uploads it; the server keeps
##   that snapshot (also on disk) and streams it to everyone else. Everything built on
##   top of it (lake, trees, islands, start site) is seeded and therefore identical.
## - Relays player states (batched at TICK_RATE), spell casts and generic world events.
##   Room for server-side entities (enemies) later: see _tick().
## - Loads the balance config (config/balance.cfg next to the server folder, or --balance <file>)
##   and sends it to every player in "welcome", so all play by the server's numbers.
## - Owns items lying in the world: "drop" spawns one (broadcast "item"), "pickup" hands it to the
##   first player who asks (broadcast "item_gone" with the taker), so an item is never duplicated.
##
## Run (from the game folder):
##   Godot_v4.7.2-stable_win64_console.exe --headless --path server -- [--port 8910] [--seed 1234] [--new-world] [--reset-discovered] [--quit-when-empty] [--balance file]
## Without --seed the last world is reused; --new-world rolls a new random seed.
## Discovered places (hidden sites) are remembered per seed; --reset-discovered forgets them.
## --quit-when-empty (used when a player hosts from the game's menu): the server shuts itself down when
## nobody has been connected for a while, so it never lingers in the background.
##
## Protocol: JSON text messages {"t": type, ...}; the world snapshot travels as binary
## chunks between "world_begin" and "world_end".

const PROTOCOL := 1
const DEFAULT_PORT := 8910
const TICK_RATE := 20.0
const CHUNK := 256 * 1024
const MAX_BUFFERED := 1 << 20
const MAX_WORLD_BYTES := 64 << 20
const MAX_NAME := 16
const HELLO_TIMEOUT := 10.0
const CONFIG := "user://server.cfg"
const WORLD_DIR := "user://worlds"
## Balance config shared with the game project (server/ sits inside the game folder).
const BALANCE_FILE := "../config/balance.cfg"
const MAX_ITEMS := 500


class Client:
	var id: int
	var ws: WebSocketPeer
	var since := 0.0
	var joined := false
	var name := ""
	var color := ""
	var state: Array = []
	var state_dirty := false
	var has_world := false
	var outbox: Array = []  # [is_text: bool, payload]
	var upload := PackedByteArray()
	var upload_size := -1


var _tcp := TCPServer.new()
var _clients := {}  # id -> Client
var _next_id := 1
var _seed := 0
var _world_version := -1
var _world := PackedByteArray()
var _generator := -1
var _tick_acc := 0.0
## Shared world clock: seconds since the server started (sent in welcome and every second as
## "clock"); moving scenery (bobbing islands, orbiting rocks) is a function of it, so every
## client shows it in the same place without per-object messages.
var _clock_start := Time.get_ticks_usec()
var _clock_ticks := 0
var _balance := {}
## Items lying in the world: id -> {"item": resource path, "p": [x, y, z]}.
var _items := {}
## Sites discovered in this world (saved per seed in server.cfg).
var _discovered: Array = []
## --quit-when-empty: seconds without any player, and whether anyone has joined yet.
var _quit_when_empty := false
var _empty_time := 0.0
var _had_players := false
const EMPTY_QUIT_AFTER := 20.0
const NOBODY_QUIT_AFTER := 300.0
var _next_item := 1


func _ready() -> void:
	Engine.max_fps = 60
	var args := _parse_args()
	var port := int(args.get("port", DEFAULT_PORT))
	_quit_when_empty = args.has("quit-when-empty")
	var cfg := ConfigFile.new()
	cfg.load(CONFIG)
	if args.has("seed"):
		_seed = int(args["seed"])
	elif args.has("new-world") or not cfg.has_section_key("world", "seed"):
		_seed = randi_range(1, 999999)
	else:
		_seed = cfg.get_value("world", "seed")
	cfg.set_value("world", "seed", _seed)
	cfg.save(CONFIG)
	_discovered = cfg.get_value("discovered", str(_seed), [])
	if args.has("reset-discovered"):
		_discovered = []
		cfg.set_value("discovered", str(_seed), [])
		cfg.save(CONFIG)
	DirAccess.make_dir_recursive_absolute(WORLD_DIR)
	var balance_path := str(args["balance"]) if args.has("balance") \
		else ProjectSettings.globalize_path("res://").path_join(BALANCE_FILE).simplify_path()
	_balance = _read_balance(balance_path)

	if _tcp.listen(port) != OK:
		printerr("Could not listen on port %d (already in use?)" % port)
		get_tree().quit(1)
		return
	print("")
	print("=== Wizard Game server ===")
	print("World seed : %d" % _seed)
	print("Port       : %d" % port)
	print("Discovered : %s" % (", ".join(PackedStringArray(_discovered)) if not _discovered.is_empty() else "nothing yet (--reset-discovered clears it)"))
	print("Players can connect to:")
	for ip in _lan_addresses():
		print("    %s   (or %s:%d)" % [ip, ip, port])
	print("World cache: %s" % ProjectSettings.globalize_path(WORLD_DIR))
	print("Balance    : %s (%s)" % [balance_path, "%d sections" % _balance.size() if not _balance.is_empty() else "NOT FOUND - players use their own"])
	print("Waiting for wizards... (Ctrl+C to stop)")


func _parse_args() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if "=" in key:
				out[key.get_slice("=", 0)] = key.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[key] = args[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


## {section: {key: value}} from a balance ConfigFile (same format the game reads).
func _read_balance(path: String) -> Dictionary:
	var out := {}
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return out
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		out[section] = values
	return out


func _lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


# --- Main loop -------------------------------------------------------------------------

func _process(delta: float) -> void:
	while _tcp.is_connection_available():
		_accept(_tcp.take_connection())
	for id in _clients.keys():
		_poll(_clients[id], delta)
	if _quit_when_empty:
		if _joined_count() > 0:
			_had_players = true
			_empty_time = 0.0
		else:
			_empty_time += delta
			if _empty_time > (EMPTY_QUIT_AFTER if _had_players else NOBODY_QUIT_AFTER):
				print("Nobody is connected any more - shutting down.")
				get_tree().quit()
				return
	_tick_acc += delta
	if _tick_acc >= 1.0 / TICK_RATE:
		_tick_acc = fmod(_tick_acc, 1.0 / TICK_RATE)
		_tick()
	for c: Client in _clients.values():
		_flush(c)


func _accept(conn: StreamPeerTCP) -> void:
	var ws := WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	ws.outbound_buffer_size = 2 * MAX_BUFFERED
	if "heartbeat_interval" in ws:
		ws.set("heartbeat_interval", 5.0)
	if ws.accept_stream(conn) != OK:
		return
	var c := Client.new()
	c.id = _next_id
	_next_id += 1
	c.ws = ws
	_clients[c.id] = c


func _poll(c: Client, delta: float) -> void:
	c.ws.poll()
	match c.ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			while c.ws.get_available_packet_count() > 0:
				var pkt := c.ws.get_packet()
				if c.ws.was_string_packet():
					var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
					if msg is Dictionary and msg.has("t"):
						_handle(c, msg)
				else:
					_handle_binary(c, pkt)
				if not _clients.has(c.id):
					return
		WebSocketPeer.STATE_CLOSED:
			_remove(c)
			return
	if not c.joined:
		c.since += delta
		if c.since > HELLO_TIMEOUT:
			c.ws.close(1000, "No hello")
			_remove(c)


## Sends queued messages while the socket's outgoing buffer has room (world chunks are big).
func _flush(c: Client) -> void:
	if c.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	while not c.outbox.is_empty() and c.ws.get_current_outbound_buffered_amount() < MAX_BUFFERED:
		var item: Array = c.outbox.pop_front()
		if item[0]:
			c.ws.send_text(item[1])
		else:
			c.ws.send(item[1], WebSocketPeer.WRITE_MODE_BINARY)


func _send(c: Client, msg: Dictionary) -> void:
	c.outbox.append([true, JSON.stringify(msg)])


func _broadcast(msg: Dictionary, except_id := -1) -> void:
	var text := JSON.stringify(msg)
	for c: Client in _clients.values():
		if c.joined and c.id != except_id:
			c.outbox.append([true, text])


## Server heartbeat: batches player states. Future server-side simulation (enemies,
## timed world events) belongs here.
func _tick() -> void:
	var states: Array = []
	for c: Client in _clients.values():
		if c.joined and c.state_dirty:
			states.append([c.id] + c.state)
			c.state_dirty = false
	if not states.is_empty():
		_broadcast({"t": "states", "s": states})
	_clock_ticks += 1
	if _clock_ticks >= int(TICK_RATE):
		_clock_ticks = 0
		_broadcast({"t": "clock", "time": _now()})


func _now() -> float:
	return (Time.get_ticks_usec() - _clock_start) / 1000000.0


# --- Messages ---------------------------------------------------------------------------

func _handle(c: Client, msg: Dictionary) -> void:
	var t: String = str(msg["t"])
	if not c.joined:
		if t == "hello":
			_hello(c, msg)
		return
	match t:
		"state":
			var s: Variant = msg.get("s")
			# [x, y, z, yaw, pitch] + optional movement flags (see Net.send_state).
			if s is Array and (s.size() == 5 or s.size() == 6):
				var clean: Array = []
				for v in s:
					clean.append(snappedf(float(v), 0.001))
				c.state = clean
				c.state_dirty = true
		"cast", "event":
			# Relayed as-is, stamped with the sender.
			msg["id"] = c.id
			_broadcast(msg, c.id)
		"drop":
			var item := str(msg.get("item", ""))
			var p: Variant = msg.get("p")
			if item.begins_with("res://") and p is Array and p.size() == 3 and _items.size() < MAX_ITEMS:
				var id := _next_item
				_next_item += 1
				var pos := [snappedf(float(p[0]), 0.01), snappedf(float(p[1]), 0.01), snappedf(float(p[2]), 0.01)]
				_items[id] = {"item": item, "p": pos}
				_broadcast({"t": "item", "id": id, "item": item, "p": pos, "by": c.id})
		"discover":
			# First discovery of a site: remembered for this world and announced to everyone.
			var site := str(msg.get("site", "")).substr(0, 40)
			if not site.is_empty() and not _discovered.has(site):
				_discovered.append(site)
				var cfg := ConfigFile.new()
				cfg.load(CONFIG)
				cfg.set_value("discovered", str(_seed), _discovered)
				cfg.save(CONFIG)
				_broadcast({"t": "discovered", "site": site, "by": c.id})
				print("* %s discovered %s" % [c.name, site])
		"pickup":
			var id := int(msg.get("id", -1))
			if _items.has(id):
				_items.erase(id)
				_broadcast({"t": "item_gone", "id": id, "by": c.id})
		"world_begin":
			if c.id == _generator:
				c.upload_size = int(msg.get("size", 0))
				if c.upload_size <= 0 or c.upload_size > MAX_WORLD_BYTES:
					c.upload_size = -1
				c.upload = PackedByteArray()
		"world_end":
			if c.id == _generator and c.upload_size > 0 and c.upload.size() == c.upload_size:
				_world_uploaded(c)


func _handle_binary(c: Client, data: PackedByteArray) -> void:
	if c.id != _generator or c.upload_size <= 0:
		return
	c.upload.append_array(data)
	if c.upload.size() > c.upload_size:
		c.upload_size = -1
		c.upload = PackedByteArray()


func _hello(c: Client, msg: Dictionary) -> void:
	if int(msg.get("v", -1)) != PROTOCOL:
		_reject(c, "Version mismatch (server protocol %d)." % PROTOCOL)
		return
	var world_version := int(msg.get("world", 0))
	if world_version != _world_version:
		if _joined_count() > 0:
			_reject(c, "Your game version builds a different world than the other players'.")
			return
		_world_version = world_version
		_world = _load_world()
		_generator = -1

	var name := str(msg.get("name", "")).strip_edges().replace("\n", " ")
	name = name.substr(0, MAX_NAME) if not name.is_empty() else "Wizard"
	name = _unique_name(name)
	var color := str(msg.get("color", "ffffff"))
	if not color.is_valid_html_color():
		color = "ffffff"
	c.name = name
	c.color = Color.html(color).to_html(false)
	c.joined = true

	var mode := "ready"
	if _world.is_empty():
		if _generator == -1:
			_generator = c.id
			mode = "generate"
		else:
			mode = "wait"
	var others: Array = []
	for o: Client in _clients.values():
		if o.joined and o.id != c.id:
			others.append({"id": o.id, "name": o.name, "color": o.color, "s": o.state})
	var items: Array = []
	for id in _items:
		items.append({"id": id, "item": _items[id].item, "p": _items[id].p})
	_send(c, {"t": "welcome", "id": c.id, "seed": _seed, "name": c.name, "world": mode, "players": others,
		"balance": _balance, "items": items, "time": _now(), "discovered": _discovered})
	_broadcast({"t": "join", "id": c.id, "name": c.name, "color": c.color}, c.id)
	if mode == "ready":
		_stream_world(c)
	print("+ %s joined (#%d, %s) - %d online" % [c.name, c.id, mode, _joined_count()])


func _reject(c: Client, reason: String) -> void:
	c.ws.send_text(JSON.stringify({"t": "reject", "reason": reason}))
	c.ws.close(4000, "Rejected")
	print("- rejected a client: %s" % reason)
	# Keep polling briefly so the close handshake goes out; dropped by the hello timeout.
	c.since = HELLO_TIMEOUT - 2.0


func _remove(c: Client) -> void:
	if not _clients.has(c.id):
		return
	_clients.erase(c.id)
	if not c.joined:
		return
	_broadcast({"t": "leave", "id": c.id})
	print("- %s left - %d online" % [c.name, _joined_count()])
	if c.id == _generator:
		_generator = -1
		# Hand the job to someone still waiting for the world.
		for o: Client in _clients.values():
			if o.joined and not o.has_world:
				_generator = o.id
				_send(o, {"t": "world_generate"})
				print("  %s now generates the world" % o.name)
				break


func _joined_count() -> int:
	var n := 0
	for c: Client in _clients.values():
		if c.joined:
			n += 1
	return n


func _unique_name(name: String) -> String:
	var taken := {}
	for c: Client in _clients.values():
		if c.joined:
			taken[c.name] = true
	if not taken.has(name):
		return name
	var k := 2
	while taken.has("%s %d" % [name, k]):
		k += 1
	return "%s %d" % [name, k]


# --- World snapshot --------------------------------------------------------------------

func _world_path() -> String:
	return "%s/world_%d_v%d.bin" % [WORLD_DIR, _seed, _world_version]


func _load_world() -> PackedByteArray:
	if FileAccess.file_exists(_world_path()):
		var data := FileAccess.get_file_as_bytes(_world_path())
		print("Loaded cached world %s (%.1f MB)" % [_world_path().get_file(), data.size() / 1048576.0])
		return data
	return PackedByteArray()


func _world_uploaded(c: Client) -> void:
	# Header: "WZW1", version, seed (see WorldBlob.gd in the game).
	if c.upload.slice(0, 4).get_string_from_ascii() != "WZW1" or c.upload.decode_u32(8) != _seed:
		print("  ignored an invalid world upload from %s" % c.name)
		return
	_world = c.upload
	c.upload = PackedByteArray()
	c.upload_size = -1
	c.has_world = true
	_generator = -1
	var f := FileAccess.open(_world_path(), FileAccess.WRITE)
	if f:
		f.store_buffer(_world)
		f.close()
	print("  world received from %s (%.1f MB), saved" % [c.name, _world.size() / 1048576.0])
	for o: Client in _clients.values():
		if o.joined and not o.has_world:
			_stream_world(o)


func _stream_world(c: Client) -> void:
	c.has_world = true
	_send(c, {"t": "world_begin", "size": _world.size()})
	var pos := 0
	while pos < _world.size():
		c.outbox.append([false, _world.slice(pos, mini(pos + CHUNK, _world.size()))])
		pos += CHUNK
	_send(c, {"t": "world_end"})
