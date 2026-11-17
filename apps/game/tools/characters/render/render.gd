extends SceneTree
## Renderiza un personaje 3D riggeado (GLB de Meshy) a cuadros de sprite
## isométricos. Lo usa ../build.sh; se puede llamar a mano:
##
##   godot --path tools/characters/render -s res://render.gd -- \
##       --glb=personaje.glb --out=frames --prefix=walk --frames=8 --k=3 \
##       [--donor=animacion.glb] [--bike=bici.glb] [--times=0,0.1,…] \
##       [--toon --bright=0.34 --head=1.25] [--rows=0,2] [--from=0 --to=1]
##
## Cámara ortográfica a 30° (proyección 2:1 del mapa). 8 direcciones en el
## suelo cada 45° (fila 0 = este/derecha, 2 = sur/hacia la cámara…). Cada
## cuadro: 32x48 lógicos a escala K (64x48 con --bike), pies en (16, 40). El
## modelo se normaliza a 1 unidad de alto con los pies en el origen.
##
## --donor: la animación sale de otro GLB con el mismo esqueleto de Meshy y se
## transfiere hueso a hueso (así cada animación se compra una sola vez).
## --bike: pose de pedaleo hecha aquí con IK (Meshy no tiene animación de bici).
## --toon: sombreado pintado (toon.gdshader); --head agranda la cabeza (chibi).

var K := 4
var FRAME := Vector2i(32, 48)
var FEET := Vector2i(16, 40)
const SUPERSAMPLE := 2
## Píxeles lógicos por unidad del mundo (el personaje mide ~38 px de alto en pantalla).
const PPU := 39.0
const PITCH := 30.0

var args := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	K = int(args.get("k", "4"))
	if args.has("bike"):
		# La bici no cabe en 32 px: cuadro doble de ancho, pies al centro.
		FRAME = Vector2i(64, 48)
		FEET = Vector2i(32, 40)
	_run.call_deferred()


func _run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(args.glb, state) != OK:
		push_error("no se pudo leer " + args.glb)
		quit(1)
		return
	var model: Node3D = doc.generate_scene(state)

	var size := FRAME * K * SUPERSAMPLE
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	root.add_child(vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = float(args.get("ambient", "0.55"))
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	vp.add_child(world_env)

	# Luz principal desde arriba a la izquierda y algo de frente (como el mapa).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = float(args.get("sun", "1.1"))
	sun.shadow_enabled = true
	sun.shadow_blur = 2.0
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.25
	vp.add_child(fill)

	if args.has("toon"):
		_toonify(model)
		env.ambient_light_energy = 0.0
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		sun.light_energy = 1.0
		sun.shadow_enabled = false
		fill.visible = false

	var pivot := Node3D.new()
	vp.add_child(pivot)
	pivot.add_child(model)
	_normalize(model)
	if args.has("bike"):
		_target_skel = _find_skeleton(model)
		_pivot = pivot
		_setup_bike(pivot)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(FRAME.y) / PPU
	cam.rotation_degrees = Vector3(-PITCH, 0, 0)
	# El origen (los pies) debe caer en FEET: el centro de la vista queda por encima.
	var up := cam.basis.y
	var forward := -cam.basis.z
	var center_offset_px := float(FRAME.y) / 2.0 - FEET.y  # negativo: centro arriba de los pies
	var target := up * (-center_offset_px / PPU)
	cam.position = target - forward * 10.0
	cam.near = 0.1
	cam.far = 30.0
	vp.add_child(cam)
	cam.current = true

	var player := _find_player(model)
	var anim_name := ""
	if player:
		var names := player.get_animation_list()
		print("animaciones: ", names)
		for n in names:
			print("  ", n, " = ", player.get_animation(n).length, " s")
		anim_name = args.get("anim", names[0] if not names.is_empty() else "")
		if not anim_name.is_empty():
			player.play(anim_name)
			player.pause()

	# --donor=otro.glb: la animación sale de otro personaje (mismo esqueleto de
	# Meshy) y se transfiere hueso a hueso (ver _retarget).
	var skeleton := _find_skeleton(model)
	_target_skel = skeleton
	if args.has("donor"):
		if player:
			player.get_parent().remove_child(player)
			player.free()
		var ddoc := GLTFDocument.new()
		var dstate := GLTFState.new()
		ddoc.append_from_file(args.donor, dstate)
		_donor = ddoc.generate_scene(dstate)
		root.add_child(_donor)
		_donor.visible = false
		_donor_skel = _find_skeleton(_donor)
		player = _find_player(_donor)
		var dn := player.get_animation_list()
		anim_name = args.get("anim", dn[0])
		print("donante: ", anim_name, " = ", player.get_animation(anim_name).length, " s")
		player.play(anim_name)
		player.pause()
		_target_skel = skeleton
		_map_bones()

	# --times=0,0.1,0.2,0.1 (fracciones de la animación) fija cada cuadro; si no,
	# --frames cuadros repartidos entre --from y --to.
	var times: Array = []
	if args.has("times"):
		times = Array(args.times.split(",")).map(func(s: String) -> float: return float(s))
	var frames := times.size() if not times.is_empty() else int(args.get("frames", "8"))
	var from := float(args.get("from", "0"))
	var to := float(args.get("to", "1"))
	var length := player.get_animation(anim_name).length if player and anim_name != "" else 0.0
	var out: String = args.get("out", "frames")
	DirAccess.make_dir_recursive_absolute(out)
	var prefix: String = args.get("prefix", "anim")
	var rows: Array = range(8) if not args.has("rows") else Array(args.rows.split(",")).map(func(s: String) -> int: return int(s))

	var sample_times: Array[float] = []
	for i in frames:
		# Ciclos (loop): reparte los cuadros sin repetir el último = primero.
		sample_times.append((float(times[i]) if not times.is_empty() else lerpf(from, to, float(i) / frames)) * length)
	for row: int in rows:
		var theta := deg_to_rad(row * 45.0)
		pivot.rotation.y = PI / 2.0 - theta
		pivot.position = Vector3.ZERO
		# Centra la animación: la cadera, en promedio, sobre el punto de los pies
		# (algunas animaciones corren el cuerpo; así no "flota" fuera de su sombra).
		if _bike_node:
			pass
		elif player and skeleton and length > 0.0:
			# Y: el pie más bajo de la animación, a la altura del pie en reposo
			# (algunas animaciones hunden o levantan todo el cuerpo).
			var feet := _foot_bones(skeleton)
			var rest_low := INF
			for b in feet:
				rest_low = minf(rest_low, (skeleton.global_transform * skeleton.get_bone_global_rest(b).origin).y)
			var sum := Vector3.ZERO
			var anim_low := INF
			for t in sample_times:
				_seek(player, t)
				var hips := skeleton.global_transform * skeleton.get_bone_global_pose(0).origin
				sum += Vector3(hips.x, 0.0, hips.z)
				for b in feet:
					anim_low = minf(anim_low, (skeleton.global_transform * skeleton.get_bone_global_pose(b).origin).y)
			pivot.position = -sum / sample_times.size()
			if not feet.is_empty():
				pivot.position.y = rest_low - anim_low
		for i in frames:
			if _bike_node:
				_bike_pose(float(i) / frames)
			elif player and length > 0.0:
				_seek(player, sample_times[i])
			await process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.resize(FRAME.x * K, FRAME.y * K, Image.INTERPOLATE_LANCZOS)
			img.save_png("%s/%s_%d_%02d.png" % [out, prefix, row, i])
	print("listo: ", out)
	quit()


var _donor: Node3D
var _donor_skel: Skeleton3D
var _target_skel: Skeleton3D
var _bone_map := {}  # hueso destino -> hueso donante
var _hip_ratio := 1.0


var _bike_node: Node3D
var _pivot: Node3D
var _bike_geo := {}


## Bici: un modelo aparte, escalado a las piernas del personaje. Las medidas
## (sillín, eje de pedales, puños) son fracciones de su caja, tomadas del
## dibujo de perfil con que se hizo (ancho x alto, desde el suelo).
func _setup_bike(pivot: Node3D) -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(args.bike, st)
	var bike: Node3D = doc.generate_scene(st)
	if args.has("toon"):
		_toonify(bike)
	var holder := Node3D.new()
	holder.add_child(bike)
	bike.rotation.y = PI / 2.0  # el frente del modelo (−X) mira a +Z, como el personaje
	var box := _aabb(holder, Transform3D.IDENTITY)
	pivot.add_child(holder)
	_bike_node = holder
	var sk := _target_skel
	var to_world := sk.global_transform
	var hip := to_world * sk.get_bone_global_rest(0).origin
	var up_leg := to_world * sk.get_bone_global_rest(sk.find_bone("LeftUpLeg")).origin
	var foot := to_world * sk.get_bone_global_rest(sk.find_bone("LeftFoot")).origin
	var leg_len := up_leg.distance_to(foot)
	var h := leg_len * float(args.get("bike_scale", "1.3"))
	var s := h / box.size.y
	holder.scale = Vector3.ONE * s
	var c := box.get_center()
	holder.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	var w := box.size.z * s
	var z := func(f: float) -> float: return (f - 0.5) * w
	_bike_geo = {
		"h": h, "hip": hip, "foot_h": foot.y, "leg": leg_len,
		"seat": Vector3(0, 0.80 * h, z.call(0.31)),
		"crank": Vector3(0, 0.26 * h, z.call(0.44)),
		"r": 0.15 * h,
		"grip": Vector3(0, 0.93 * h, z.call(0.55)),
		"grip_x": absf(box.size.x * s) * 0.42,
		"hip_x": absf(up_leg.x - hip.x),
	}
	print("bici: alto ", h, " largo ", w, " pierna ", leg_len)


## Pose de pedaleo en la fase [0, 1): cadera en el sillín, torso inclinado,
## pies siguiendo los pedales y manos en los puños (IK de dos huesos).
func _bike_pose(phase: float) -> void:
	var sk := _target_skel
	sk.reset_bone_poses()
	_apply_head(sk)
	var g := _bike_geo
	# Las medidas de la bici están en el espacio del pivote (que gira por fila).
	var inv := (_pivot.global_transform.affine_inverse() * sk.global_transform).affine_inverse()
	# Cadera sobre el sillín (en el espacio del esqueleto).
	var hip_world: Vector3 = g.seat + Vector3(0, 0.03 * g.h, -0.03 * g.h)
	var hips := 0
	sk.set_bone_pose_position(hips, inv * hip_world)
	# Torso adelante, cabeza mirando al frente.
	for b in ["Spine02", "Spine01", "Spine"]:
		_rotate_global(sk, sk.find_bone(b), Quaternion(Vector3.RIGHT, deg_to_rad(9)))
	_rotate_global(sk, sk.find_bone("neck"), Quaternion(Vector3.RIGHT, deg_to_rad(-14)))
	sk.force_update_all_bone_transforms()
	# Piernas: el tobillo va sobre el pedal, la rodilla hacia adelante.
	var ang := phase * TAU
	for side in [["Left", 1.0, 0.0], ["Right", -1.0, PI]]:
		var a: float = ang + side[2]
		var pedal: Vector3 = g.crank + Vector3(side[1] * g.hip_x, -cos(a) * g.r, sin(a) * g.r)
		var ankle := pedal + Vector3(0, g.foot_h * 0.9, -0.01)
		var up := sk.find_bone(side[0] + "UpLeg")
		var knee := sk.find_bone(side[0] + "Leg")
		var foot := sk.find_bone(side[0] + "Foot")
		_two_bone(sk, up, knee, foot, inv * ankle, inv * (ankle + Vector3(0, 0.3, 1.0)))
		_keep_global_rest(sk, foot)
	# Brazos: la muñeca en el puño, el codo hacia afuera y abajo.
	for side in [["Left", 1.0], ["Right", -1.0]]:
		var grip: Vector3 = g.grip + Vector3(side[1] * g.grip_x, 0, 0)
		var arm := sk.find_bone(side[0] + "Arm")
		var fore := sk.find_bone(side[0] + "ForeArm")
		var hand := sk.find_bone(side[0] + "Hand")
		_two_bone(sk, arm, fore, hand, inv * grip, inv * (grip + Vector3(side[1] * 1.0, -1.0, -0.6)))
	sk.force_update_all_bone_transforms()


func _rotate_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	if bone < 0:
		return
	sk.force_update_all_bone_transforms()
	var gb := sk.get_bone_global_pose(bone).basis.orthonormalized()
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis()
	var new_g := Basis(q) * gb
	sk.set_bone_pose_rotation(bone, (pb.inverse() * new_g).get_rotation_quaternion())


## Gira `bone` (en el espacio del esqueleto) para que su hijo pase de `from` a `to`.
func _aim(sk: Skeleton3D, bone: int, from: Vector3, to: Vector3) -> void:
	if from.length() < 1e-6 or to.length() < 1e-6:
		return
	_rotate_global(sk, bone, Quaternion(from.normalized(), to.normalized()))


func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, target: Vector3, pole: Vector3) -> void:
	sk.force_update_all_bone_transforms()
	var pa := sk.get_bone_global_pose(a).origin
	var pb := sk.get_bone_global_pose(b).origin
	var pc := sk.get_bone_global_pose(c).origin
	var l1 := pa.distance_to(pb)
	var l2 := pb.distance_to(pc)
	var to_t := target - pa
	var d := clampf(to_t.length(), absf(l1 - l2) + 1e-4, l1 + l2 - 1e-4)
	var dir := to_t.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var hgt := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var n := (pole - pa) - dir * (pole - pa).dot(dir)
	n = n.normalized() if n.length() > 1e-6 else Vector3.UP
	var want_b := pa + dir * x + n * hgt
	_aim(sk, a, pb - pa, want_b - pa)
	sk.force_update_all_bone_transforms()
	pb = sk.get_bone_global_pose(b).origin
	pc = sk.get_bone_global_pose(c).origin
	_aim(sk, b, pc - pb, (pa + dir * d) - pb)


## El pie queda con su orientación de reposo (plano sobre el pedal).
func _keep_global_rest(sk: Skeleton3D, bone: int) -> void:
	sk.force_update_all_bone_transforms()
	var parent := sk.get_bone_parent(bone)
	var pb := sk.get_bone_global_pose(parent).basis.orthonormalized()
	var want := sk.get_bone_global_rest(bone).basis.orthonormalized()
	sk.set_bone_pose_rotation(bone, (pb.inverse() * want).get_rotation_quaternion())


func _toonify(node: Node) -> void:
	var shader: Shader = load("res://toon.gdshader")
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.get_active_material(i) as BaseMaterial3D
			var mat := ShaderMaterial.new()
			mat.shader = shader
			if src:
				mat.set_shader_parameter("albedo_tex", src.albedo_texture)
				mat.set_shader_parameter("albedo_color", src.albedo_color)
			mat.set_shader_parameter("brightness", float(args.get("bright", "0.32")))
			mi.set_surface_override_material(i, mat)


## Cabeza más grande (estilo chibi del juego): escala el hueso de la cabeza.
func _apply_head(sk: Skeleton3D) -> void:
	var h := float(args.get("head", "1.0"))
	var b := sk.find_bone("Head")
	if b >= 0 and h != 1.0:
		sk.set_bone_pose_scale(b, Vector3.ONE * h)


func _map_bones() -> void:
	for i in _target_skel.get_bone_count():
		var j := _donor_skel.find_bone(_target_skel.get_bone_name(i))
		if j >= 0:
			_bone_map[i] = j
	var th := _target_skel.get_bone_global_rest(0).origin.y
	var dh := _donor_skel.get_bone_global_rest(0).origin.y
	_hip_ratio = th / dh if dh > 0.0 else 1.0
	print("huesos mapeados: ", _bone_map.size(), "/", _target_skel.get_bone_count(), " cadera x", _hip_ratio)


func _seek(player: AnimationPlayer, t: float) -> void:
	player.seek(t, true)
	if _donor_skel:
		_retarget()
	if _target_skel:
		_apply_head(_target_skel)
		_target_skel.force_update_all_bone_transforms()


## Transfiere la pose del donante: cada hueso gira en el mundo lo mismo que gira
## el del donante respecto a su reposo (así no importa que los reposos difieran
## un poco). La cadera además se desplaza, escalada a la altura del destino.
func _retarget() -> void:
	_donor_skel.force_update_all_bone_transforms()
	var sk := _target_skel
	var globals := {}
	for i in sk.get_bone_count():
		var parent := sk.get_bone_parent(i)
		var rest_g := sk.get_bone_global_rest(i).basis.orthonormalized()
		var g := rest_g
		if _bone_map.has(i):
			var j: int = _bone_map[i]
			var d_rest := _donor_skel.get_bone_global_rest(j).basis.orthonormalized()
			var d_pose := _donor_skel.get_bone_global_pose(j).basis.orthonormalized()
			g = (d_pose * d_rest.inverse()) * rest_g
		elif parent >= 0:
			# Sin pareja: sigue a su padre como en reposo.
			var parent_rest: Basis = sk.get_bone_global_rest(parent).basis.orthonormalized()
			g = globals[parent] * parent_rest.inverse() * rest_g
		globals[i] = g
		var local: Basis = g if parent < 0 else (globals[parent] as Basis).inverse() * g
		sk.set_bone_pose_rotation(i, local.get_rotation_quaternion())
		if parent < 0 and _bone_map.has(i):
			var j: int = _bone_map[i]
			var moved := _donor_skel.get_bone_pose_position(j) - _donor_skel.get_bone_rest(j).origin
			sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin + moved * _hip_ratio)
	sk.force_update_all_bone_transforms()


## Escala el modelo a 1 unidad de alto, centra x/z y apoya los pies en y = 0.
func _normalize(model: Node3D) -> void:
	var box := _aabb(model, Transform3D.IDENTITY)
	print("aabb original: ", box)
	var s := float(args.get("height", "1.0")) / box.size.y
	model.scale = Vector3.ONE * s
	var c := box.get_center()
	model.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)


func _aabb(node: Node, xform: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	var t := xform
	if node is Node3D:
		t = xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		var mi := node as MeshInstance3D
		# Con esqueleto, el mesh se dibuja en el espacio de los huesos: la escala
		# de los nodos padre (p. ej. Armature x0.01) no le aplica.
		var skinned := mi.skin != null or not mi.skeleton.is_empty() and mi.get_node_or_null(mi.skeleton) is Skeleton3D
		var b: AABB = (Transform3D.IDENTITY if skinned else t) * mi.mesh.get_aabb()
		result = b
		first = false
	for child in node.get_children():
		var cb := _aabb(child, t)
		if cb.size == Vector3.ZERO:
			continue
		result = cb if first else result.merge(cb)
		first = false
	return result


func _foot_bones(skeleton: Skeleton3D) -> Array[int]:
	var out: Array[int] = []
	for i in skeleton.get_bone_count():
		var n := skeleton.get_bone_name(i).to_lower()
		if n.contains("foot") or n.contains("toe"):
			out.append(i)
	return out


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var s := _find_skeleton(child)
		if s:
			return s
	return null


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var p := _find_player(child)
		if p:
			return p
	return null
