extends SceneTree
## Genera el arte inicial EDITABLE del juego en assets/art/ (un PNG por tile,
## variante y personaje). Es un punto de partida: edítalos o reemplázalos con
## tu propio arte (Aseprite, LibreSprite, Krita, GIMP...).
##
## NUNCA sobrescribe un archivo que ya existe (tus cambios están a salvo).
## Para regenerar todo desde cero:  pnpm game:art:reset   (usa --force)
##
## Especificaciones (tamaños, anclas, nombres): assets/art/README.md
##
## Las texturas de suelo son "sin costuras": el ruido es periódico sobre la
## grilla isométrica (u, v), así un tile encaja con sus vecinos y con las otras
## variantes del mismo tipo (comparten la base; solo cambian los detalles).

const ART := "res://assets/art"
const W := 64
const H := 32
const PROP := Vector2i(64, 64)
## Base del prop (centro del rombo) dentro de su imagen 64x64.
const PROP_BASE := Vector2i(32, 48)
const FRAME := Vector2i(32, 48)
const FEET := Vector2i(16, 44)
const DIRECTIONS: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const WALK_FRAMES := 4

var force := false
var written := 0
var kept := 0


func _initialize() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	_ground_tiles()
	_props()
	_player_sheet()
	print("Arte inicial: %d archivos escritos, %d existentes conservados%s" % [
		written, kept, "" if force else " (usa --force para regenerarlos)"])
	quit()


func _write(relative: String, img: Image) -> void:
	var path := ProjectSettings.globalize_path(ART + "/" + relative)
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	# El peso va en el nombre (grass_1@3.png) y el usuario puede cambiarlo:
	# se compara por el nombre sin el peso.
	var stem := relative.get_file().get_basename().get_slice("@", 0)
	var same: Array[String] = []
	for existing in DirAccess.get_files_at(dir):
		if existing.get_extension() == "png" and existing.get_basename().get_slice("@", 0) == stem:
			same.append(existing)
	if not same.is_empty() and not force:
		kept += 1
		return
	for existing in same:
		DirAccess.remove_absolute(dir.path_join(existing))
	img.save_png(path)
	written += 1


# =============================================================================
# Ruido periódico y utilidades de rombo
# =============================================================================

class PeriodicNoise:
	var grid: int
	var values := PackedFloat32Array()

	func _init(grid_size: int, noise_seed: int) -> void:
		grid = grid_size
		var rng := RandomNumberGenerator.new()
		rng.seed = noise_seed
		values.resize(grid * grid)
		for i in grid * grid:
			values[i] = rng.randf()

	## u, v en unidades de tile: periodo 1 en ambos ejes.
	func at(u: float, v: float) -> float:
		var x := u * grid
		var y := v * grid
		var x0 := floori(x)
		var y0 := floori(y)
		var fx := x - x0
		var fy := y - y0
		fx = fx * fx * (3.0 - 2.0 * fx)
		fy = fy * fy * (3.0 - 2.0 * fy)
		var a := lerpf(_v(x0, y0), _v(x0 + 1, y0), fx)
		var b := lerpf(_v(x0, y0 + 1), _v(x0 + 1, y0 + 1), fx)
		return lerpf(a, b, fy)

	func _v(x: int, y: int) -> float:
		return values[posmod(y, grid) * grid + posmod(x, grid)]


## Medio ancho de la fila y del rombo 2:1 (bordes escalonados que encajan).
func _half_width(y: int) -> int:
	return (y + 1) * 2 if y < H / 2 else (H - y) * 2


func _in_diamond(x: int, y: int, margin := 0) -> bool:
	if y < margin or y >= H - margin:
		return false
	var hw := _half_width(y) - margin * 2
	return x >= W / 2 - hw and x < W / 2 + hw


## Coordenadas isométricas del píxel: el tile vecino está en u+1 o v+1.
func _uv(x: int, y: int) -> Vector2:
	var fx := (x + 0.5) / W
	var fy := (y + 0.5) / H
	return Vector2(fx + fy, fy - fx)


func _shade(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)


# =============================================================================
# Suelo
# =============================================================================

## Nombre de archivo -> pintor. Las variantes comparten la textura base.
## "@n" en el nombre es el peso (frecuencia relativa) de la variante.
func _ground_tiles() -> void:
	var specs := {
		"grass": ["grass_0@6", "grass_1@3", "grass_2@2", "grass_3@1"],
		"grass_dark": ["grass_dark_0@5", "grass_dark_1@3", "grass_dark_2@2"],
		"dirt": ["dirt_0@5", "dirt_1@3", "dirt_2@2"],
		"sand": ["sand_0@4", "sand_1@2"],
		"water": ["water_0@4", "water_1@3", "water_2@3"],
		"stone": ["stone_0@5", "stone_1@2"],
		"asphalt": ["asphalt_0@12", "asphalt_1@1.5", "asphalt_2@0.3"],
		"pavement": ["pavement_0@10", "pavement_1@1.5", "pavement_2@0.5"],
		"building": ["building_0@60", "building_1@1", "building_2@1"],
	}
	for kind: String in specs:
		var names: Array = specs[kind]
		for variant in names.size():
			var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(kind) + variant * 7919
			call("_paint_" + kind, img, variant, rng)
			_write("tiles/ground/%s.png" % names[variant], img)


func _fill(img: Image, painter: Callable) -> void:
	for y in H:
		for x in W:
			if _in_diamond(x, y):
				img.set_pixel(x, y, painter.call(x, y, _uv(x, y)))


func _spot(img: Image, x: int, y: int, c: Color) -> void:
	if _in_diamond(x, y, 1):
		img.set_pixel(x, y, c)


func _random_point(rng: RandomNumberGenerator, margin: int) -> Vector2i:
	for i in 64:
		var p := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(0, H - 1))
		if _in_diamond(p.x, p.y, margin):
			return p
	return Vector2i(W / 2, H / 2)


func _paint_grass(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(4, 11)
	var fine := PeriodicNoise.new(8, 12)
	# Contraste bajo en la base (se repite en cada tile); la variedad la dan
	# los detalles y las variantes.
	var dark := Color("5a9c44")
	var mid := Color("62a548")
	var light := Color("6aad4d")
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var n := base.at(uv.x, uv.y) * 0.65 + fine.at(uv.x, uv.y) * 0.35
		var c := dark if n < 0.4 else (mid if n < 0.62 else light)
		var r := rng.randf()
		if r < 0.05:
			c = c.darkened(0.12)
		elif r > 0.965:
			c = c.lightened(0.12)
		return c)
	# Matas de pasto: una hoja clara con sombra a los lados.
	for i in [7, 12, 7, 5][variant]:
		var p := _random_point(rng, 3)
		_spot(img, p.x, p.y - 1, Color("8cc663"))
		_spot(img, p.x - 1, p.y, Color("447f35"))
		_spot(img, p.x + 1, p.y, Color("447f35"))
		_spot(img, p.x, p.y, Color("74b653"))
	if variant == 2:  # flores
		for i in 6:
			var p := _random_point(rng, 4)
			_spot(img, p.x, p.y, [Color("f5f0e1"), Color("f2d45c"), Color("e98ab0")][i % 3])
			_spot(img, p.x, p.y + 1, Color("3f7a33"))
	if variant == 3:  # trébol más oscuro
		var c := _random_point(rng, 7)
		for dy in range(-2, 3):
			for dx in range(-5, 6):
				if (dx * dx) / 25.0 + (dy * dy) / 4.0 <= 1.0 and rng.randf() < 0.75:
					_spot(img, c.x + dx, c.y + dy, Color("4a8a3a") if rng.randf() < 0.7 else Color("6fb04f"))


func _paint_grass_dark(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(4, 21)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var n := base.at(uv.x, uv.y)
		var c := Color("3a6831") if n < 0.42 else (Color("3f7136") if n < 0.66 else Color("44783a"))
		var r := rng.randf()
		if r < 0.06:
			c = Color("6b5232")  # hojarasca
		elif r < 0.1:
			c = c.darkened(0.15)
		return c)
	for i in [3, 6, 4][variant]:
		var p := _random_point(rng, 3)
		_spot(img, p.x, p.y, Color("8a6a3e"))
		_spot(img, p.x + 1, p.y, Color("5c4428"))
	if variant == 2:  # ramita
		var p := _random_point(rng, 6)
		for k in 6:
			_spot(img, p.x + k, p.y + (k / 3), Color("5a4026"))


func _paint_dirt(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(4, 31)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var n := base.at(uv.x, uv.y)
		var c := Color("936b44") if n < 0.4 else (Color("9b7249") if n < 0.65 else Color("a37a50"))
		if rng.randf() < 0.07:
			c = c.darkened(0.15)
		return c)
	for i in [4, 8, 3][variant]:  # piedritas
		var p := _random_point(rng, 3)
		_spot(img, p.x, p.y, Color("c9b49a"))
		_spot(img, p.x + 1, p.y, Color("a8957d"))
		_spot(img, p.x, p.y + 1, Color("6e5034"))
	if variant == 2:  # charquito seco
		var c := _random_point(rng, 7)
		for dy in range(-2, 3):
			for dx in range(-5, 6):
				if (dx * dx) / 25.0 + (dy * dy) / 4.0 <= 1.0:
					_spot(img, c.x + dx, c.y + dy, Color("7d5a39"))


func _paint_sand(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(4, 41)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var c := Color("dcc488") if base.at(uv.x, uv.y) < 0.5 else Color("e5cf95")
		# Ondas periódicas (frecuencia entera: encajan con los vecinos).
		if sin(TAU * (uv.x * 3.0 + uv.y)) > 0.92:
			c = Color("ecd9a6")
		if rng.randf() < 0.06:
			c = c.darkened(0.08)
		return c)
	if variant == 1:  # conchitas
		for i in 3:
			var p := _random_point(rng, 4)
			_spot(img, p.x, p.y, Color("fbf3e4"))
			_spot(img, p.x + 1, p.y, Color("d8b9a0"))


func _paint_water(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(4, 51)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var n := base.at(uv.x, uv.y)
		return Color("336fc2") if n < 0.42 else (Color("3876cc") if n < 0.68 else Color("3e7dd2")))
	# Reflejos: guiones horizontales claros.
	for i in [5, 7, 6][variant]:
		var p := _random_point(rng, 3)
		var length := rng.randi_range(3, 6)
		for k in length:
			_spot(img, p.x + k, p.y, Color("7fb2ec") if k > 0 and k < length - 1 else Color("5d98e0"))
	if variant == 2:
		var p := _random_point(rng, 4)
		_spot(img, p.x, p.y, Color("c4dcf7"))


func _paint_stone(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	# Adoquines: 4x4 por tile en la grilla (u, v), con junta oscura.
	var shades := PackedFloat32Array()
	var srng := RandomNumberGenerator.new()
	srng.seed = 61
	for i in 16:
		shades.append(srng.randf_range(-0.07, 0.07))
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var a := uv.x * 4.0
		var b := uv.y * 4.0
		var fa := a - floorf(a)
		var fb := b - floorf(b)
		if fa < 0.12 or fb < 0.12:
			return Color("6f6f78")
		var c := _shade(Color("9c9ca6"), shades[posmod(floori(a), 4) * 4 + posmod(floori(b), 4)])
		if fa < 0.3 and fb < 0.3:
			c = c.lightened(0.08)  # borde iluminado
		if rng.randf() < 0.04:
			c = c.darkened(0.1)
		return c)
	if variant == 1:  # desgaste
		for i in 10:
			var p := _random_point(rng, 2)
			_spot(img, p.x, p.y, Color("80808a"))


func _paint_asphalt(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var base := PeriodicNoise.new(8, 71)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var c := Color("44474f") if base.at(uv.x, uv.y) < 0.5 else Color("4a4d55")
		var r := rng.randf()
		if r < 0.05:
			c = Color("5a5d66")
		elif r > 0.96:
			c = Color("383a41")
		return c)
	if variant == 1:  # grieta
		var p := _random_point(rng, 6)
		for k in 14:
			_spot(img, p.x, p.y, Color("2f3137"))
			p += Vector2i(1 if rng.randf() < 0.8 else 0, rng.randi_range(-1, 1) if k % 2 == 0 else 0)
	if variant == 2:  # alcantarilla
		var c := Vector2i(W / 2, H / 2)
		for dy in range(-4, 5):
			for dx in range(-8, 9):
				var d := (dx * dx) / 64.0 + (dy * dy) / 16.0
				if d <= 1.0:
					var col := Color("5f636c") if d > 0.65 else Color("33363c")
					if d <= 0.65 and posmod(dx + dy * 2, 4) == 0:
						col = Color("4a4e56")
					_spot(img, c.x + dx, c.y + dy, col)


func _paint_pavement(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	# Baldosas: 2x2 por tile, con junta.
	var shades := PackedFloat32Array([0.0, -0.04, 0.03, -0.02])
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var a := uv.x * 2.0
		var b := uv.y * 2.0
		var fa := a - floorf(a)
		var fb := b - floorf(b)
		if fa < 0.06 or fb < 0.06:
			return Color("a39b8c")
		var c := _shade(Color("c9c2b4"), shades[posmod(floori(a), 2) * 2 + posmod(floori(b), 2)])
		if rng.randf() < 0.05:
			c = c.darkened(0.06)
		return c)
	if variant == 1:  # baldosa rajada
		var p := _random_point(rng, 6)
		for k in 7:
			_spot(img, p.x + k, p.y + (1 if k > 3 else 0), Color("8e8676"))
	if variant == 2:  # rejilla de desagüe
		for dy in range(-2, 3):
			for dx in range(-5, 6):
				_spot(img, W / 2 + dx, H / 2 + dy, Color("3c3e44") if posmod(dx, 2) == 0 else Color("6a6c72"))


func _paint_building(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	# Tejado de tejas: hileras a lo largo de u con juntas desfasadas.
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var row := uv.y * 8.0
		var fr := row - floorf(row)
		var col := uv.x * 8.0 + 0.5 * posmod(floori(row), 2)
		var fc := col - floorf(col)
		var c := Color("a9513b")
		if fr < 0.16:
			c = Color("7e3a2a")
		elif fc < 0.1:
			c = Color("8e4331")
		elif fr > 0.7:
			c = Color("bb6248")
		if rng.randf() < 0.04:
			c = c.darkened(0.08)
		return c)
	if variant == 1:  # chimenea / ventilación
		var p := _random_point(rng, 7)
		for dy in range(-3, 2):
			for dx in range(-3, 4):
				_spot(img, p.x + dx, p.y + dy, Color("8f9096") if dx < 1 else Color("6c6d73"))
		for dx in range(-3, 4):
			_spot(img, p.x + dx, p.y - 4, Color("b4b5ba"))
	if variant == 2:  # claraboya
		var p := _random_point(rng, 7)
		for dy in range(-2, 3):
			for dx in range(-5, 6):
				var edge := absi(dy) == 2 or absi(dx) == 5
				_spot(img, p.x + dx, p.y + dy, Color("d7d9de") if edge else (Color("8fb4d6") if dx + dy < 0 else Color("6a8fb3")))


# =============================================================================
# Props (64x64, base en PROP_BASE)
# =============================================================================

const OUTLINE := Color("1f2a1c")


func _props() -> void:
	var specs := {
		"tree_0@3": _tree.bind(Color("4f9a3a"), 17, 15, 0),
		"tree_1@2": _tree.bind(Color("5fae45"), 14, 18, 1),
		"pine_0@3": _pine.bind(3, 0),
		"pine_1@2": _pine.bind(4, 1),
		"rock_0@3": _rock.bind(13, 9, 0),
		"rock_1@2": _rock.bind(9, 7, 1),
		"bush_0@3": _bush.bind(false, 0),
		"bush_1@1": _bush.bind(true, 1),
	}
	for name: String in specs:
		var img := Image.create_empty(PROP.x, PROP.y, false, Image.FORMAT_RGBA8)
		var painter: Callable = specs[name]
		painter.call(img)
		_write("props/%s.png" % name, img)


func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _shadow(img: Image, rx: int, ry: int) -> void:
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			if float(x * x) / (rx * rx) + float(y * y) / (ry * ry) <= 1.0:
				_blend(img, PROP_BASE.x + x, PROP_BASE.y + y, Color(0, 0, 0, 0.28))


## Contorno de 1 px alrededor de lo opaco (no cuenta la sombra translúcida).
func _outline(img: Image, color: Color, from := Vector2i.ZERO, to := Vector2i(-1, -1)) -> void:
	if to.x < 0:
		to = Vector2i(img.get_width(), img.get_height())
	var marks: Array[Vector2i] = []
	for y in range(from.y, to.y):
		for x in range(from.x, to.x):
			if img.get_pixel(x, y).a >= 0.6:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= from.x and n.y >= from.y and n.x < to.x and n.y < to.y and img.get_pixel(n.x, n.y).a >= 0.6:
					marks.append(Vector2i(x, y))
					break
	for p in marks:
		img.set_pixel(p.x, p.y, color)


## Volumen redondeado con luz desde arriba a la izquierda, en 4 tonos.
func _ball(img: Image, center: Vector2, radius: Vector2, base: Color, rng: RandomNumberGenerator, mask_center := Vector2.INF, mask_radius := 0.0) -> void:
	var light_center := center if mask_center == Vector2.INF else mask_center
	var lr := maxf(radius.x, radius.y) if mask_radius == 0.0 else mask_radius
	for y in range(int(center.y - radius.y), int(center.y + radius.y) + 1):
		for x in range(int(center.x - radius.x), int(center.x + radius.x) + 1):
			var nx := (x + 0.5 - center.x) / radius.x
			var ny := (y + 0.5 - center.y) / radius.y
			if nx * nx + ny * ny > 1.0:
				continue
			var lx := (x + 0.5 - light_center.x) / lr
			var ly := (y + 0.5 - light_center.y) / lr
			var light := -(lx * 0.6 + ly * 0.8) + rng.randf_range(-0.18, 0.18)
			var c := base
			if light > 0.45:
				c = base.lightened(0.28)
			elif light > 0.05:
				c = base.lightened(0.1)
			elif light < -0.5:
				c = base.darkened(0.32)
			elif light < -0.1:
				c = base.darkened(0.15)
			img.set_pixel(x, y, c)


func _trunk(img: Image, top: int, width: int) -> void:
	for y in range(top, PROP_BASE.y + 1):
		for x in range(PROP_BASE.x - width / 2, PROP_BASE.x - width / 2 + width):
			var rel := x - (PROP_BASE.x - width / 2)
			var c := Color("7a5332") if rel < width / 2 else Color("5c3d24")
			if rel == 0:
				c = Color("8c6440")
			img.set_pixel(x, y, c)


func _tree(img: Image, color: Color, rx: int, ry: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	_shadow(img, 15, 5)
	_trunk(img, 30, 5)
	var center := Vector2(PROP_BASE.x, 22 - (ry - 15))
	# Copa: varias esferas que comparten la misma luz (se ve como un volumen).
	var lobes := [Vector2(0, 0), Vector2(-rx * 0.5, ry * 0.25), Vector2(rx * 0.5, ry * 0.25), Vector2(0, -ry * 0.45)]
	for lobe: Vector2 in lobes:
		_ball(img, center + lobe, Vector2(rx * 0.62, ry * 0.62), color, rng, center, float(rx))
	_outline(img, OUTLINE)


func _pine(img: Image, tiers: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 950 + variant
	_shadow(img, 11, 4)
	_trunk(img, 40, 4)
	var color := Color("2f6b3f")
	var top := 4 if tiers == 4 else 8
	var tier_h := 12 if tiers == 4 else 13
	for t in tiers:
		var y0 := top + t * (tier_h - 4)
		var half := 7 + t * 3
		for dy in tier_h:
			var hw := int(round(half * float(dy + 1) / tier_h))
			for dx in range(-hw, hw + 1):
				var c := color.lightened(0.18) if dx < -hw / 3 else (color.darkened(0.2) if dx > hw / 3 else color)
				if dy == tier_h - 1 or rng.randf() < 0.06:
					c = c.darkened(0.15)
				img.set_pixel(PROP_BASE.x + dx, y0 + dy, c)
	_outline(img, Color("17301d"))


func _rock(img: Image, rx: int, ry: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 970 + variant
	_shadow(img, rx + 1, 5)
	var center := Vector2(PROP_BASE.x + 0.5, PROP_BASE.y - ry + 2)
	_ball(img, center, Vector2(rx, ry), Color("8d8d95"), rng)
	_ball(img, center + Vector2(rx * 0.55, ry * 0.3), Vector2(rx * 0.5, ry * 0.6), Color("7e7e87"), rng, center, float(rx))
	# Grieta
	for k in ry:
		img.set_pixel(int(center.x) - 2 + k / 3, int(center.y) - ry / 2 + k, Color("5e5e66"))
	_outline(img, Color("2b2b30"))


func _bush(img: Image, flowers: bool, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 990 + variant
	_shadow(img, 15, 5)
	var color := Color("4c8f3a")
	var center := Vector2(PROP_BASE.x, 40)
	for lobe: Vector2 in [Vector2(-7, 2), Vector2(7, 2), Vector2(0, -3)]:
		_ball(img, center + lobe, Vector2(9, 7.5), color, rng, center, 14.0)
	if flowers:
		for i in 9:
			var p := Vector2i(int(center.x) + rng.randi_range(-12, 12), int(center.y) + rng.randi_range(-8, 6))
			if img.get_pixel(p.x, p.y).a > 0.5:
				img.set_pixel(p.x, p.y, Color("f7c6d9") if i % 2 == 0 else Color("fff4f0"))
	_outline(img, OUTLINE)


# =============================================================================
# Jugador: hoja de sprites 8 direcciones x (1 quieto + 4 caminando)
# =============================================================================

const SKIN := Color("f1c27d")
const SKIN_SHADE := Color("d9a066")
const HAIR := Color("5a3825")
const HAIR_LIGHT := Color("7a4e33")
const SHIRT := Color("e85d4a")
const SHIRT_SHADE := Color("b8432f")
const PANTS := Color("3b4a6b")
const PANTS_SHADE := Color("2c3752")
const SHOES := Color("2a2a2e")
const CHAR_OUTLINE := Color("241a17")


func _player_sheet() -> void:
	var cols := 1 + WALK_FRAMES
	var img := Image.create_empty(FRAME.x * cols, FRAME.y * DIRECTIONS.size(), false, Image.FORMAT_RGBA8)
	for row in DIRECTIONS.size():
		for col in cols:
			var frame := Image.create_empty(FRAME.x, FRAME.y, false, Image.FORMAT_RGBA8)
			var dir := DIRECTIONS[row]
			# Las direcciones hacia el oeste son el espejo de las del este.
			var mirror := dir in ["w", "sw", "nw"]
			var drawn: String = {"w": "e", "sw": "se", "nw": "ne"}.get(dir, dir)
			_character(frame, drawn, col)
			if mirror:
				frame.flip_x()
			_outline(frame, CHAR_OUTLINE)
			img.blit_rect(frame, Rect2i(Vector2i.ZERO, FRAME), Vector2i(col * FRAME.x, row * FRAME.y))
	# Solo si no hay ningún personaje: nunca toca tus skins (ni con --force)
	# ni agrega uno de relleno al selector.
	var dir := ProjectSettings.globalize_path(ART + "/characters")
	if DirAccess.dir_exists_absolute(dir) and Array(DirAccess.get_files_at(dir)).any(
			func(f: String) -> bool: return f.get_extension() == "png"):
		kept += 1
		return
	_write("characters/player01.png", img)


func _box(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, c)


## Personaje chibi (cabeza grande, estilo RPG de 16 bits) en un frame 32x48.
## `dir`: e, se, s, n o ne (las del oeste se espejan). `frame`: 0 quieto, 1..4 paso.
func _character(img: Image, dir: String, frame: int) -> void:
	var phase := (frame - 1) * PI / 2.0
	var swing := 0 if frame == 0 else int(round(sin(phase) * 2.0))
	var bob := -1 if frame in [1, 3] else 0
	var front := dir in ["s", "se"]
	var back := dir in ["n", "ne"]
	var side := dir == "e"
	var cx := FEET.x  # 16

	# Piernas y zapatos
	if side:
		# De perfil: una pierna adelante y otra atrás.
		for leg in [-1, 1]:
			var shift: int = swing * leg
			var lx := cx - 2 + shift
			_box(img, lx, 36 + bob, 4, 6, PANTS if leg > 0 else PANTS_SHADE)
			_box(img, lx + (1 if leg > 0 else 0), 42, 4, 2, SHOES)
	else:
		var lift_left := maxi(swing, 0)
		var lift_right := maxi(-swing, 0)
		_box(img, cx - 5, 36 + bob, 4, 6 - lift_left, PANTS)
		_box(img, cx + 1, 36 + bob, 4, 6 - lift_right, PANTS_SHADE)
		_box(img, cx - 5, 42 - lift_left, 4, 2, SHOES)
		_box(img, cx + 1, 42 - lift_right, 4, 2, SHOES)

	# Torso
	var top := 25 + bob
	_box(img, cx - 6, top, 12, 11, SHIRT)
	_box(img, cx + 3, top, 3, 11, SHIRT_SHADE)
	_box(img, cx - 6, top + 9, 12, 2, SHIRT_SHADE)  # cintura

	# Brazos (balanceo opuesto a las piernas)
	if side:
		_box(img, cx - 1 - swing, top + 1, 3, 8, SHIRT_SHADE)
		_box(img, cx - 1 - swing, top + 9, 3, 2, SKIN)
	else:
		_box(img, cx - 8, top + 1 + maxi(-swing, 0), 2, 8, SHIRT)
		_box(img, cx + 6, top + 1 + maxi(swing, 0), 2, 8, SHIRT_SHADE)
		_box(img, cx - 8, top + 9 + maxi(-swing, 0), 2, 2, SKIN)
		_box(img, cx + 6, top + 9 + maxi(swing, 0), 2, 2, SKIN_SHADE)

	# Cabeza (grande, esquinas redondeadas)
	var hy := 11 + bob
	_box(img, cx - 6, hy + 1, 12, 12, SKIN)
	_box(img, cx - 5, hy, 10, 14, SKIN)
	_box(img, cx + 3, hy + 2, 2, 10, SKIN_SHADE)

	# Pelo
	_box(img, cx - 6, hy - 1, 12, 5, HAIR)
	_box(img, cx - 5, hy - 2, 10, 2, HAIR)
	_box(img, cx - 4, hy - 2, 4, 1, HAIR_LIGHT)
	if back:
		_box(img, cx - 6, hy + 3, 12, 9, HAIR)
		_box(img, cx - 4, hy, 5, 2, HAIR_LIGHT)
		if dir == "ne":  # se asoma la mejilla del lado hacia donde mira
			_box(img, cx + 3, hy + 5, 3, 6, SKIN_SHADE)
	elif side:
		_box(img, cx - 6, hy + 3, 6, 7, HAIR)  # nuca
		_box(img, cx + 3, hy + 7, 1, 2, CHAR_OUTLINE)  # ojo
		_box(img, cx + 6, hy + 8, 1, 2, SKIN)  # nariz
	elif front:
		_box(img, cx - 6, hy + 3, 2, 4, HAIR)  # patillas
		_box(img, cx + 4, hy + 3, 2, 4, HAIR)
		var shift := 1 if dir == "se" else 0
		_box(img, cx - 4 + shift, hy + 7, 2, 3, CHAR_OUTLINE)
		_box(img, cx + 2 + shift, hy + 7, 2, 3, CHAR_OUTLINE)
		_box(img, cx - 4 + shift, hy + 7, 1, 1, Color.WHITE)
		_box(img, cx + 2 + shift, hy + 7, 1, 1, Color.WHITE)
		_box(img, cx - 6 + shift, hy + 10, 2, 1, Color("f0a6a0"))  # rubor
		_box(img, cx + 4 + shift, hy + 10, 2, 1, Color("f0a6a0"))
