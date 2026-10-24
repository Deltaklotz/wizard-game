extends Node3D
## Builds the world at startup: terrain -> lake & start site -> vegetation & greebles ->
## floating islands, then drops the player at the start site near the middle of the map.
## Online, the seed comes from the server and the terrain is either downloaded (identical
## for everyone) or generated here and uploaded for the others (see Net, WorldBlob).

@export var terrain_settings: TerrainSettings
@export var player_path: NodePath
@export var build_vegetation := true
@export var build_islands := true
@export var build_lake := true

var terrain_data: TerrainData
var start_site: StartSite

var _loading: CanvasLayer


func _ready() -> void:
	var player := get_node_or_null(player_path) as Node3D
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	_show_loading("Shaping the land...")
	# Let the loading label render before the heavy lifting starts.
	await get_tree().process_frame
	await get_tree().process_frame

	if terrain_settings == null:
		terrain_settings = TerrainSettings.new()
	terrain_data = _obtain_terrain()
	if terrain_data == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_settings.seed
	# Lakes are carved into the heightmap before anything is built on it.
	var lake_shape: LakeShape = null
	if build_lake:
		lake_shape = LakeShape.find(terrain_data, rng)
		lake_shape.carve(terrain_data)
	start_site = StartSite.find(terrain_data, terrain_settings.seed)
	start_site.flatten(terrain_data)
	# Big forests, glades and trails (trails are painted into the control map). Own seed offset so
	# the other generators' seeds stay as they were.
	terrain_data.forests = ForestLayout.generate(terrain_data, terrain_settings.seed + 7919, start_site, lake_shape)
	SecretSite.carve(terrain_data)
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(terrain_data)
	add_child(start_site)
	start_site.build()

	if build_vegetation:
		_set_loading("Growing forests...")
		await get_tree().process_frame
		var veg := Vegetation.new()
		veg.name = "Vegetation"
		add_child(veg)
		veg.build(terrain_data, rng.randi())
		var grass := GrassField.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(terrain)
		# Own seed offset (not drawn from rng, so the lake/island seeds stay as they were).
		var shrooms := ShroomField.new()
		shrooms.name = "Shrooms"
		add_child(shrooms)
		shrooms.build(terrain_data, terrain_settings.seed + 4241, veg.tree_positions)
	if lake_shape:
		var lake := Lake.new()
		lake.name = "Lake"
		add_child(lake)
		lake.build(terrain_data, lake_shape, rng.randi())
	if build_islands:
		_set_loading("Raising the sky islands...")
		await get_tree().process_frame
		var islands := IslandField.new()
		islands.name = "SkyIslands"
		add_child(islands)
		islands.build(terrain_data, rng.randi())

	var map := get_node_or_null("../MapOverlay")
	if map:
		_set_loading("Drawing the map...")
		await get_tree().process_frame
		await map.build(self)

	if player:
		place_player(player)
		player.process_mode = Node.PROCESS_MODE_INHERIT
	var orb := get_node_or_null("../MagicOrb") as Node3D
	if orb:
		orb.global_position = start_site.orb_position()
	_loading.queue_free()
	Net.enter_game()


## Offline: generate from the settings. Online: use the server's seed and its shared
## Puts the player on their spot in the waystone circle, facing the pillar (spawn and respawn).
func place_player(p: Node3D) -> void:
	var spawn := start_site.spawn_point(maxi(Net.my_id - 1, 0))
	p.global_position = spawn + Vector3.UP * 1.0
	var to_center := start_site.orb_position() - spawn
	var yaw := atan2(-to_center.x, -to_center.z)
	if p.has_method("set_look"):
		p.set_look(yaw, 0.0)
	else:
		p.rotation.y = yaw


## terrain snapshot, or generate it and upload it when we are the first player.
func _obtain_terrain() -> TerrainData:
	if not Net.is_online():
		return TerrainGenerator.generate(terrain_settings)
	terrain_settings.seed = Net.seed
	if not Net.world_blob.is_empty():
		var data := WorldBlob.decode(Net.world_blob, Net.seed)
		if data == null:
			_set_loading("The world received from the server is damaged.")
			push_error("Could not decode the shared world.")
		return data
	var generated := TerrainGenerator.generate(terrain_settings)
	if generated:
		Net.upload_world(WorldBlob.encode(generated, Net.seed, Net.WORLD_VERSION))
	return generated


func _show_loading(text: String) -> void:
	_loading = CanvasLayer.new()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var label := Label.new()
	label.name = "Label"
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loading.add_child(label)
	add_child(_loading)


func _set_loading(text: String) -> void:
	(_loading.get_node("Label") as Label).text = text
