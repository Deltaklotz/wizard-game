class_name ChainFx
extends Node3D
## Visual of a spectral chain (local and remote): interlocking ghost links (one procedural
## link mesh, instanced with a MultiMesh – shaders/vfx/chain_link.gdshader) laid along a world
## polyline from the caster's hand to the head/anchor, a glowing head with a mote trail, and
## the endings: burst() flings every link apart (they tumble a metre or two and fade), and
## dissolve() lets the chain fade away quietly after a pull finished.
##
## Links are laid out from the far end backwards, so a growing chain feeds out of the book and
## a pulling chain reels in at the hand.

const LINK_SHADER := preload("res://shaders/vfx/chain_link.gdshader")
## Outer length/width of a link, tube radius, and spacing of links along the chain.
const LINK_LENGTH := 0.34
const LINK_WIDTH := 0.19
const LINK_TUBE := 0.03
const PITCH := 0.23
const MAX_LINKS := 340
const BURST_TIME := 0.9
const DISSOLVE_TIME := 0.35

static var _link_mesh: ArrayMesh

var _first_person := false
var _color := Color.WHITE
var _accent := Color.WHITE
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _head: Node3D
var _head_light: OmniLight3D
var _trail: GPUParticles3D
var _points := PackedVector3Array()
var _count := 0
var _xforms: Array[Transform3D] = []
var _fades := PackedFloat32Array()
## Burst: per link velocity and spin; time since the ending began (-1 = alive).
var _vel: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _end_t := -1.0
var _bursting := false


static func create(parent: Node, color: Color, accent: Color, first_person: bool) -> ChainFx:
	var fx := ChainFx.new()
	fx._first_person = first_person
	fx._color = color
	fx._accent = accent
	parent.add_child(fx)
	return fx


## Draws a short chain and bursts it, so the shaders/particles compile during loading.
static func prewarm(vp: Node) -> void:
	var fx := create(vp, Color(0.7, 1, 0.3), Color(1, 0.9, 0.4), false)
	var pts := PackedVector3Array()
	for i in 12:
		pts.append(Vector3(sin(i * 0.4) * 0.5, 1.0, -float(i) * 0.6))
	fx.set_points(pts)
	vp.get_tree().create_timer(0.2).timeout.connect(fx.burst)


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	if _link_mesh == null:
		_link_mesh = _build_link_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = LINK_SHADER
	mat.set_shader_parameter("color", _color)
	mat.set_shader_parameter("accent", _accent)
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = _link_mesh
	_mm.instance_count = MAX_LINKS
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	_mmi.material_override = mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mmi)

	_head = Node3D.new()
	add_child(_head)
	_trail = SpellFx.particles(_head, 40, 0.45, false, false, Vector2(0.09, 0.09), _color, _accent)
	var pm := _trail.process_material as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	_trail.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_head_light = OmniLight3D.new()
	_head_light.light_volumetric_fog_energy = 0.0
	_head_light.light_color = _color
	_head_light.omni_range = 4.0
	_head_light.light_energy = 0.0
	_head.add_child(_head_light)


## The chain's polyline in world space, from the hand to the head/anchor.
func set_points(points: PackedVector3Array) -> void:
	if _end_t >= 0.0:
		return
	_points = points
	_layout()


## The glowing head (and its trail/light) – shown while the chain is flying.
func set_head_visible(on: bool) -> void:
	if _trail:
		_trail.emitting = on
		_head_light.visible = on


func is_ending() -> bool:
	return _end_t >= 0.0


## The chain snaps: every link flies off in its own direction, tumbling, and fades.
func burst() -> void:
	if _end_t >= 0.0:
		return
	_end_t = 0.0
	_bursting = true
	set_head_visible(false)
	_vel.resize(_count)
	_spin.resize(_count)
	for i in _count:
		var x := _xforms[i]
		var along := -x.basis.z.normalized()
		var r := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
		if r.length_squared() < 0.01:
			r = Vector3.UP
		_vel[i] = r.normalized() * randf_range(1.4, 4.2) + along * randf_range(-1.2, 1.2) + Vector3.UP * randf_range(0.3, 1.4)
		_spin[i] = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * randf_range(6.0, 16.0)
	# Bright sparks at a few points along the chain.
	if _count > 0:
		var bursts := clampi(_count / 25, 1, 10)
		for b in bursts:
			var at := _xforms[int((b + 0.5) * _count / bursts)].origin
			var p := SpellFx.particles(self, 18, 0.55, true, true, Vector2(0.025, 0.22), _color, _accent)
			p.global_position = at
			var pm := p.process_material as ParticleProcessMaterial
			pm.spread = 180.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 6.0
			pm.damping_min = 6.0
			pm.damping_max = 10.0
	get_tree().create_timer(BURST_TIME + 0.1).timeout.connect(queue_free)


## The pull is over: the chain fades out where it is.
func dissolve() -> void:
	if _end_t >= 0.0:
		return
	_end_t = 0.0
	set_head_visible(false)
	get_tree().create_timer(DISSOLVE_TIME + 0.6).timeout.connect(queue_free)


func _process(delta: float) -> void:
	if _end_t < 0.0:
		if _trail and _trail.emitting and _count > 0:
			# The light stays off right in front of the book (it lit up the pages).
			var d := _head.global_position.distance_to(_points[0])
			_head_light.light_energy = 1.4 * clampf((d - 2.0) / 3.0, 0.0, 1.0) if _first_person else 1.4
		return
	_end_t += delta
	if _bursting:
		var u := _end_t / BURST_TIME
		var fade := 1.0 - smoothstep(0.3, 1.0, u)
		var damp := exp(-2.6 * delta)
		for i in _count:
			_vel[i] = _vel[i] * damp + Vector3.DOWN * 2.5 * delta
			var x := _xforms[i]
			x.origin += _vel[i] * delta
			var w := _spin[i]
			if w.length_squared() > 0.0001:
				x.basis = Basis(w.normalized(), w.length() * delta) * x.basis
			_spin[i] *= damp
			_xforms[i] = x
			var s := lerpf(1.0, 0.55, u)
			_mm.set_instance_transform(i, Transform3D(x.basis.orthonormalized().scaled(Vector3.ONE * s), x.origin))
			# Links that were faded out near the hand stay hidden.
			var f := (fade * 1.6 if u < 0.08 else fade) * _fades[i]
			_mm.set_instance_custom_data(i, Color(f, float(i % 17) / 17.0, 0.0, 0.0))
	else:
		var alpha := 1.0 - clampf(_end_t / DISSOLVE_TIME, 0.0, 1.0)
		for i in _count:
			_mm.set_instance_custom_data(i, Color(_fades[i] * alpha, fmod(float(i) * 0.618, 1.0), 0.0, 0.0))


func _layout() -> void:
	var n := _points.size()
	if n < 2:
		_count = 0
		_mm.visible_instance_count = 0
		return
	var cum := PackedFloat32Array()
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + _points[i - 1].distance_to(_points[i])
	var total := cum[n - 1]
	_head.global_position = _points[n - 1]
	_count = mini(int(total / PITCH) + 1, MAX_LINKS)
	_xforms.resize(_count)
	_fades.resize(_count)
	var lo := _points[0]
	var hi := _points[0]
	var seg := n - 1
	for k in _count:
		# Arc length of this link, measured back from the far end.
		var s := total - float(k) * PITCH
		while seg > 1 and cum[seg - 1] > s:
			seg -= 1
		var a := _points[seg - 1]
		var b := _points[seg]
		var len_ab := maxf(cum[seg] - cum[seg - 1], 0.0001)
		var pos := a.lerp(b, clampf((s - cum[seg - 1]) / len_ab, 0.0, 1.0))
		var t := (b - a) / len_ab
		var ref := Vector3.UP if absf(t.y) < 0.95 else Vector3.RIGHT
		var x := ref.cross(t).normalized()
		var y := t.cross(x)
		var basis := Basis(x, y, t)
		# Neighbouring links stand at right angles; a little stable jitter per link.
		var roll := (PI * 0.5 if k % 2 == 1 else 0.0) + sin(float(k) * 12.9898) * 0.18
		basis = basis * Basis(Vector3.BACK, roll)
		var xf := Transform3D(basis, pos)
		_xforms[k] = xf
		_mm.set_instance_transform(k, xf)
		# Fade in away from the hand (in first person the first links would cover the book).
		var fade := smoothstep(0.8, 2.8, s) if _first_person else smoothstep(0.0, 0.25, s)
		_fades[k] = fade
		_mm.set_instance_custom_data(k, Color(fade, fmod(float(k) * 0.618, 1.0), 0.0, 0.0))
		lo = lo.min(pos)
		hi = hi.max(pos)
	_mm.visible_instance_count = _count
	_mmi.custom_aabb = AABB(lo - Vector3.ONE, hi - lo + Vector3.ONE * 2.0)


## One link: a stadium-shaped centre line in the XZ plane swept with a circular tube.
## Long axis = local Z (along the chain).
static func _build_link_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := LINK_WIDTH * 0.5 - LINK_TUBE
	var half := LINK_LENGTH * 0.5 - LINK_TUBE - a
	const ARC := 10
	const TUBE := 6
	# Centre line: two semicircles joined by straight sides.
	var centers: Array[Vector3] = []
	var outs: Array[Vector3] = []
	for side in 2:
		var cz := half if side == 0 else -half
		for i in ARC + 1:
			var ang := PI * float(i) / ARC + (0.0 if side == 0 else PI)
			var o := Vector3(cos(ang), 0.0, sin(ang))
			centers.append(Vector3(0, 0, cz) + o * a)
			outs.append(o)
	var m := centers.size()
	for i in m:
		for j in TUBE + 1:
			var phi := TAU * float(j) / TUBE
			var nrm := outs[i] * cos(phi) + Vector3.UP * sin(phi)
			st.set_normal(nrm)
			st.set_uv(Vector2(float(i) / m, float(j) / TUBE))
			st.add_vertex(centers[i] + nrm * LINK_TUBE)
	for i in m:
		var i2 := (i + 1) % m
		for j in TUBE:
			var v00 := i * (TUBE + 1) + j
			var v01 := i * (TUBE + 1) + j + 1
			var v10 := i2 * (TUBE + 1) + j
			var v11 := i2 * (TUBE + 1) + j + 1
			st.add_index(v00)
			st.add_index(v10)
			st.add_index(v11)
			st.add_index(v00)
			st.add_index(v11)
			st.add_index(v01)
	return st.commit()
