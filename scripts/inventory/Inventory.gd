class_name Inventory
extends Node
## The local player's items. Two containers:
##   HOTBAR – the grimoire's pages (10, number keys 1-0); only spell pages fit here.
##   BAG    – the satchel (BAG_SIZE slots); any item (later also non-spell items).
## Items are Resources (spells for now) identified over the network by their resource path.
##
## Dropping puts an item into the world in front of the player as a WorldItem; pressing the
## "interact" action (E) near one picks it up when there is room (spells go to a free page first,
## then the bag). get_pickup_target() is the item that E would take (for the on-screen prompt). Online the
## server owns world items (Net.send_drop / send_pickup, signals item_added / item_removed), so
## only one player can take an item; offline they are handled here directly.

signal changed
## Tried to pick something up with no room for it.
signal full

enum { HOTBAR, BAG }

const BAG_SIZE := 24
## Reach for picking up (metres from the player's body centre).
const PICKUP_RADIUS := 2.6
## Metres in front of the player a dropped item lands.
const DROP_DISTANCE := 2.2

var player: Node3D
var grimoire: Grimoire
var bag: Array[Resource] = []

## World items: id -> {"node": WorldItem, "item": path}.
var _world := {}
var _pending := {}
var _local_ids := -1


func setup(owner_player: Node3D) -> void:
	player = owner_player
	grimoire = owner_player.grimoire
	bag.resize(BAG_SIZE)


func _ready() -> void:
	Net.item_added.connect(_on_item_added)
	Net.item_removed.connect(_on_item_removed)
	# Items already lying around when joining.
	for id in Net.items:
		_spawn(id, Net.items[id].item, Net.items[id].p, false)


# --- Slots ------------------------------------------------------------------------------

func slot_count(container: int) -> int:
	return grimoire.page_count if container == HOTBAR else BAG_SIZE


func get_item(container: int, index: int) -> Resource:
	if container == HOTBAR:
		return grimoire.get_spell_on_page(index)
	return bag[index] if index >= 0 and index < bag.size() else null


## Whether `item` may sit in `container` (the hotbar takes spell pages only).
static func accepts(container: int, item: Resource) -> bool:
	return container != HOTBAR or item == null or item is Spell


## The open page's spell can't be taken away while it is being aimed or held (chain, ward).
func is_locked(container: int, index: int) -> bool:
	return container == HOTBAR and index == grimoire.current_page \
		and (grimoire.is_channeling() or grimoire.is_aiming())


func can_move(from_c: int, from_i: int, to_c: int, to_i: int) -> bool:
	if from_c == to_c and from_i == to_i:
		return false
	if is_locked(from_c, from_i) or is_locked(to_c, to_i):
		return false
	return accepts(to_c, get_item(from_c, from_i)) and accepts(from_c, get_item(to_c, to_i))


## Moves an item onto another slot, swapping with whatever is there.
func move(from_c: int, from_i: int, to_c: int, to_i: int) -> bool:
	if not can_move(from_c, from_i, to_c, to_i):
		return false
	var a := get_item(from_c, from_i)
	var b := get_item(to_c, to_i)
	_put(to_c, to_i, a)
	_put(from_c, from_i, b)
	changed.emit()
	return true


func _put(container: int, index: int, item: Resource) -> void:
	if container == HOTBAR:
		grimoire.set_spell(index, item as Spell)
	else:
		bag[index] = item


## Puts an item into the first fitting free slot (spells: pages first). False if full.
func add(item: Resource) -> bool:
	var slot := _free_slot(item)
	if slot.x < 0:
		return false
	_put(slot.x, slot.y, item)
	changed.emit()
	return true


func has_room_for(item: Resource) -> bool:
	return _free_slot(item).x >= 0


func _free_slot(item: Resource) -> Vector2i:
	if item is Spell:
		for i in grimoire.page_count:
			if grimoire.get_spell_on_page(i) == null:
				return Vector2i(HOTBAR, i)
	for i in BAG_SIZE:
		if bag[i] == null:
			return Vector2i(BAG, i)
	return Vector2i(-1, -1)


# --- Dropping and picking up ------------------------------------------------------------

## Throws the item in a slot into the world in front of the player.
func drop(container: int, index: int) -> bool:
	var item := get_item(container, index)
	if item == null or is_locked(container, index) or item.resource_path.is_empty():
		return false
	_put(container, index, null)
	changed.emit()
	var pos := _drop_point()
	if Net.is_online():
		Net.send_drop(item.resource_path, pos)
	else:
		_on_item_added(_local_ids, item.resource_path, pos, Net.my_id)
		_local_ids -= 1
	return true


## On the ground in front of the player (hovering), not inside a wall.
func _drop_point() -> Vector3:
	var cam: Camera3D = player.camera
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 0.001 else -player.global_basis.z
	var space := player.get_world_3d().direct_space_state
	var from: Vector3 = player.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * DROP_DISTANCE)
	q.exclude = [(player as CollisionObject3D).get_rid()]
	q.collision_mask = 1
	var r := space.intersect_ray(q)
	var at: Vector3 = (r.position - fwd * 0.4) if not r.is_empty() else from + fwd * DROP_DISTANCE
	var down := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 30.0)
	down.collision_mask = 1
	var g := space.intersect_ray(down)
	return (g.position if not g.is_empty() else at) + Vector3.UP * WorldItem.HOVER


func _on_item_added(id: int, path: String, pos: Vector3, by: int) -> void:
	_spawn(id, path, pos, true)


func _spawn(id: int, path: String, pos: Vector3, fresh: bool) -> void:
	if _world.has(id) or not ResourceLoader.exists(path):
		return
	var item := load(path) as Resource
	if item == null:
		return
	var node := WorldItem.create(get_tree().current_scene, item, pos, fresh)
	_world[id] = {"node": node, "item": path}


func _on_item_removed(id: int, by: int) -> void:
	var entry: Dictionary = _world.get(id, {})
	_world.erase(id)
	_pending.erase(id)
	if entry.is_empty():
		return
	var mine := by == Net.my_id
	if is_instance_valid(entry.node):
		(entry.node as WorldItem).collect(player if mine else _avatar(by))
	if mine:
		var item := load(entry.item) as Resource
		# Taken while the bag filled up meanwhile: back on the ground.
		if item and not add(item):
			if Net.is_online():
				Net.send_drop(entry.item, _drop_point())
			else:
				_on_item_added(_local_ids, entry.item, _drop_point(), Net.my_id)
				_local_ids -= 1


func _avatar(id: int) -> Node3D:
	var remotes := get_tree().current_scene.get_node_or_null("RemotePlayers")
	return remotes.avatar(id) if remotes and remotes.has_method("avatar") else null


func _physics_process(delta: float) -> void:
	for id in _pending.keys():
		_pending[id] -= delta
		if _pending[id] <= 0.0:
			_pending.erase(id)


## The world item the interact key would pick up: the nearest within reach, preferring the one
## the player looks at. {"id", "node"} or {}.
func get_pickup_target() -> Dictionary:
	if player == null or player.is_dead():
		return {}
	var cam: Camera3D = player.camera
	var eye := cam.global_position
	var view := -cam.global_basis.z
	var best := {}
	var best_score := INF
	for id in _world:
		if _pending.has(id):
			continue
		var node := _world[id].node as WorldItem
		if not is_instance_valid(node) or node.is_collected():
			continue
		var d := node.global_position.distance_to(player.global_position)
		if d > PICKUP_RADIUS:
			continue
		var to := (node.global_position - eye).normalized()
		var score := d + (1.0 - view.dot(to)) * 3.0
		if score < best_score:
			best_score = score
			best = {"id": id, "node": node}
	return best


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact") or event.is_echo() or player == null:
		return
	if player.is_input_blocked():
		return
	var target := get_pickup_target()
	if target.is_empty():
		return
	get_viewport().set_input_as_handled()
	var node := target.node as WorldItem
	if not has_room_for(node.item):
		full.emit()
		return
	if Net.is_online():
		Net.send_pickup(target.id)
		_pending[target.id] = 2.0
	else:
		_on_item_removed(target.id, Net.my_id)
