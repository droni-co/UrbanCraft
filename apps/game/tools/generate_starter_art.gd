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
	_buildings()
	_poi_icons()
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
		"roof_brick": ["roof_brick_0@20", "roof_brick_1@2", "roof_brick_2@1"],
		"roof_concrete": ["roof_concrete_0@20", "roof_concrete_1@2", "roof_concrete_2@1.5"],
		"roof_dark": ["roof_dark_0@20", "roof_dark_1@1.5"],
		"roof_civic": ["roof_civic_0@20", "roof_civic_1@1"],
		"roof_industrial": ["roof_industrial_0@20", "roof_industrial_1@2"],
		"crosswalk": ["crosswalk_0@1"],
		"rail": ["rail_0@4", "rail_1@1"],
		"cycleway": ["cycleway_0@8", "cycleway_1@1"],
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


## Ladrillo a la vista (azoteas de Bogotá): hiladas a lo largo de u.
func _paint_roof_brick(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var row := uv.y * 10.0
		var fr := row - floorf(row)
		var col := uv.x * 5.0 + 0.5 * posmod(floori(row), 2)
		var fc := col - floorf(col)
		var c := Color("b65a3c") if posmod(floori(col) + floori(row), 3) != 0 else Color("a8513a")
		if fr < 0.18 or fc < 0.05:
			c = Color("c9a58c")  # junta de mortero
		if rng.randf() < 0.05:
			c = c.darkened(0.08)
		return c)
	if variant == 1:
		_water_tank(img, rng)
	if variant == 2:
		_vent(img, rng)


## Losa de concreto clara, en paneles.
func _paint_roof_concrete(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	var noise := PeriodicNoise.new(6, 33)
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var c := Color("b9b6ae") if noise.at(uv.x, uv.y) < 0.55 else Color("b1aea6")
		var fa := uv.x * 2.0 - floorf(uv.x * 2.0)
		var fb := uv.y * 2.0 - floorf(uv.y * 2.0)
		if fa < 0.03 or fb < 0.03:
			c = Color("9d9a92")
		if rng.randf() < 0.05:
			c = c.darkened(0.05)
		return c)
	if variant == 1:
		_water_tank(img, rng)
	if variant == 2:
		_ac_unit(img, rng)


## Grava oscura / tela asfáltica (oficinas, comercio alto).
func _paint_roof_dark(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var r := rng.randf()
		var c := Color("5b6170")
		if r < 0.25:
			c = Color("535867")
		elif r > 0.9:
			c = Color("6a7080")
		return c)
	if variant == 1:  # claraboya de vidrio
		var p := _random_point(rng, 8)
		for dy in range(-3, 4):
			for dx in range(-7, 8):
				var edge := absi(dy) == 3 or absi(dx) == 7
				_spot(img, p.x + dx, p.y + dy, Color("c9ccd2") if edge else (Color("9cc3e6") if dx + dy * 2 < 0 else Color("6f97bd")))


## Edificios públicos (iglesias, colegios, hospitales): teja crema.
func _paint_roof_civic(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var row := uv.y * 6.0
		var fr := row - floorf(row)
		var c := Color("dcc29a")
		if fr < 0.15:
			c = Color("b89c74")
		elif fr > 0.75:
			c = Color("e8d2ad")
		if rng.randf() < 0.04:
			c = c.darkened(0.06)
		return c)
	if variant == 1:  # remate / campanario visto desde arriba
		for dy in range(-4, 5):
			for dx in range(-8, 9):
				if absi(dx) / 2 + absi(dy) <= 4:
					_spot(img, W / 2 + dx, H / 2 + dy, Color("a8553d") if dx < 0 else Color("8e4532"))


## Lámina metálica ondulada (bodegas, industria).
func _paint_roof_industrial(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var c := Color("8f9ba7") if posmod(floori(uv.x * 16.0), 2) == 0 else Color("7d8994")
		if rng.randf() < 0.03:
			c = c.lightened(0.1)
		return c)
	if variant == 1:  # óxido
		for i in 3:
			var p := _random_point(rng, 6)
			for k in 10:
				_spot(img, p.x + rng.randi_range(-4, 4), p.y + rng.randi_range(-2, 2), Color("9a6a48") if k % 2 == 0 else Color("85593c"))


## Paso de cebra: asfalto con franjas blancas.
func _paint_crosswalk(img: Image, _variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var c := Color("e6e4dc") if posmod(floori(uv.x * 6.0), 2) == 0 else Color("464951")
		if rng.randf() < 0.06:
			c = c.darkened(0.08)
		return c)


## Vía férrea: balasto con traviesas y rieles.
func _paint_rail(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var r := rng.randf()
		var c := Color("8a8478") if r < 0.5 else (Color("7c766b") if r < 0.85 else Color("9d978b"))
		var fu := uv.x * 4.0 - floorf(uv.x * 4.0)
		if fu < 0.22:
			c = Color("6b4f36") if r < 0.8 else Color("5c432e")  # traviesa
		var fv := uv.y - floorf(uv.y)
		if absf(fv - 0.3) < 0.035 or absf(fv - 0.7) < 0.035:
			c = Color("b9bec6") if fv < 0.5 else Color("a3a8b0")  # rieles
		return c)
	if variant == 1:  # maleza entre el balasto
		for i in 6:
			var p := _random_point(rng, 3)
			_spot(img, p.x, p.y, Color("5f8f3e"))


## Ciclorruta: pavimento rojo.
func _paint_cycleway(img: Image, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(img, func(x: int, y: int, uv: Vector2) -> Color:
		var r := rng.randf()
		return Color("a24a3e") if r < 0.6 else (Color("963f35") if r < 0.9 else Color("b25a4c")))
	if variant == 1:  # bicicleta pintada
		for a in 16:
			var t := TAU * a / 16.0
			_spot(img, W / 2 - 5 + roundi(cos(t) * 3), H / 2 + roundi(sin(t) * 2), Color.WHITE)
			_spot(img, W / 2 + 5 + roundi(cos(t) * 3), H / 2 + roundi(sin(t) * 2), Color.WHITE)
		for dx in range(-5, 6):
			_spot(img, W / 2 + dx, H / 2 - 2 + absi(dx) / 3, Color.WHITE)


## Tanque de agua (los negros de las azoteas), visto desde arriba.
func _water_tank(img: Image, rng: RandomNumberGenerator) -> void:
	var p := _random_point(rng, 9)
	for dy in range(-4, 5):
		for dx in range(-7, 8):
			var d := (dx * dx) / 49.0 + (dy * dy) / 16.0
			if d <= 1.0:
				_spot(img, p.x + dx, p.y + dy, Color("2c2f36") if d > 0.55 else (Color("3d424b") if dx + dy < 0 else Color("33373f")))


func _vent(img: Image, rng: RandomNumberGenerator) -> void:
	var p := _random_point(rng, 7)
	for dy in range(-2, 3):
		for dx in range(-3, 4):
			_spot(img, p.x + dx, p.y + dy, Color("8f9096") if dx < 1 else Color("6c6d73"))


func _ac_unit(img: Image, rng: RandomNumberGenerator) -> void:
	var p := _random_point(rng, 8)
	for dy in range(-3, 4):
		for dx in range(-5, 6):
			var c := Color("d4d6da") if dy < 0 else Color("aeb1b7")
			if (dx * dx) / 9.0 + (dy * dy) / 4.0 <= 1.0:
				c = Color("5d6168")  # ventilador
			_spot(img, p.x + dx, p.y + dy, c)


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
		"bench_0@1": _bench,
		"street_lamp_0@1": _street_lamp,
		"traffic_light_0@1": _traffic_light,
		"bus_stop_0@1": _bus_stop,
		"fountain_0@1": _fountain,
		"statue_0@1": _statue,
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


## Polígono relleno (centros de píxel dentro del polígono).
func _poly(img: Image, pts: PackedVector2Array, c: Color) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	for y in range(floori(r.position.y), ceili(r.end.y) + 1):
		for x in range(floori(r.position.x), ceili(r.end.x) + 1):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height() \
					and Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				img.set_pixel(x, y, c)


## Caja isométrica: base (centro de su planta), semilados a (eje u) y b (eje v)
## en píxeles de pantalla, alto h, elevada z. Luz desde arriba a la izquierda.
func _iso_box(img: Image, base: Vector2, a: float, b: float, h: float, top: Color, z := 0.0) -> void:
	var du := Vector2(1, 0.5)
	var dv := Vector2(-1, 0.5)
	var o := base + Vector2(0, -z)
	var c0 := o - du * a - dv * b
	var c1 := o + du * a - dv * b
	var c2 := o + du * a + dv * b
	var c3 := o - du * a + dv * b
	var up := Vector2(0, -h)
	_poly(img, PackedVector2Array([c3, c2, c2 + up, c3 + up]), top.darkened(0.22))
	_poly(img, PackedVector2Array([c2, c1, c1 + up, c2 + up]), top.darkened(0.4))
	_poly(img, PackedVector2Array([c0 + up, c1 + up, c2 + up, c3 + up]), top)


func _pole(img: Image, x: int, top: int, bottom: int, c: Color) -> void:
	for y in range(top, bottom + 1):
		img.set_pixel(x, y, c.lightened(0.15))
		img.set_pixel(x + 1, y, c.darkened(0.15))


func _bench(img: Image) -> void:
	var base := Vector2(PROP_BASE)
	_shadow(img, 14, 5)
	var wood := Color("a3713f")
	var iron := Color("3a3d44")
	for side: float in [-1.0, 1.0]:
		_iso_box(img, base + Vector2(1, 0.5) * 8.0 * side, 1.0, 2.5, 6.0, iron)
	_iso_box(img, base, 10.0, 3.0, 2.0, wood, 6.0)
	_iso_box(img, base + Vector2(-1, 0.5) * -3.0, 10.0, 0.8, 6.0, wood.darkened(0.08), 8.0)
	_outline(img, Color("2a1f17"))


func _street_lamp(img: Image) -> void:
	_shadow(img, 5, 2)
	var grey := Color("68707d")
	_box(img, 29, 45, 6, 4, grey.darkened(0.2))
	_pole(img, 31, 8, 46, grey)
	for x in range(32, 39):
		img.set_pixel(x, 8, grey)
	_box(img, 36, 9, 6, 3, Color("2f3540"))
	_box(img, 37, 12, 4, 1, Color("ffe7a3"))
	for y in range(13, 17):  # halo de luz
		for x in range(34, 45):
			_blend(img, x, y, Color(1.0, 0.92, 0.6, 0.12))
	_outline(img, Color("23272e"), Vector2i.ZERO, Vector2i(64, 13))


func _traffic_light(img: Image) -> void:
	_shadow(img, 5, 2)
	_pole(img, 31, 16, 47, Color("5d6470"))
	_box(img, 28, 3, 8, 19, Color("2b2f36"))
	var colors := [Color("e5483d"), Color("f2c14e").darkened(0.35), Color("4fc46b")]
	for i in 3:
		var cy := 6 + i * 6
		_box(img, 29, cy - 3, 6, 1, Color("1d2025"))  # visera
		for dy in range(-2, 2):
			for dx in range(-2, 2):
				if dx * dx + dy * dy <= 4:
					img.set_pixel(32 + dx, cy + dy, colors[i])
	_outline(img, Color("15171b"))


func _bus_stop(img: Image) -> void:
	var base := Vector2(PROP_BASE) + Vector2(-2, 0)
	_shadow(img, 18, 6)
	var frame := Color("4a5260")
	for px: int in [-11, 11]:  # postes
		_pole(img, int(base.x) + px, int(base.y) - 29, int(base.y) - 1, frame)
	# Panel trasero de vidrio
	_poly(img, PackedVector2Array([base + Vector2(-11, -6), base + Vector2(11, -6), base + Vector2(11, -26), base + Vector2(-11, -26)]), Color(0.62, 0.78, 0.9, 0.55))
	_iso_box(img, base + Vector2(0, -2), 9.0, 1.5, 1.5, Color("9aa3ad"), 5.0)  # banca
	_iso_box(img, base + Vector2(0, -1), 13.0, 5.0, 2.0, Color("3f6fb5"), 27.0)  # techo
	_pole(img, int(base.x) + 16, int(base.y) - 30, int(base.y) + 2, Color("8a929c"))  # señal
	_box(img, int(base.x) + 13, int(base.y) - 36, 9, 7, Color("2f6fd6"))
	_box(img, int(base.x) + 15, int(base.y) - 34, 5, 3, Color.WHITE)
	_outline(img, Color("1f2530"))


func _fountain(img: Image) -> void:
	var c := Vector2i(PROP_BASE) + Vector2i(0, -3)
	_shadow(img, 19, 7)
	var stone := Color("b7b1a5")
	for k in range(5, -1, -1):  # borde con volumen
		for y in range(-10, 11):
			for x in range(-19, 20):
				if (x * x) / 361.0 + (y * y) / 90.0 <= 1.0:
					img.set_pixel(c.x + x, c.y + y - k, stone.darkened(0.25) if k < 5 else stone)
	for y in range(-8, 9):
		for x in range(-16, 17):
			if (x * x) / 256.0 + (y * y) / 64.0 <= 1.0:
				img.set_pixel(c.x + x, c.y + y - 5, Color("4f8fd6") if posmod(x + y, 5) != 0 else Color("78aee6"))
	_box(img, c.x - 2, c.y - 18, 4, 13, stone.darkened(0.1))
	for i in 9:  # chorros
		_blend(img, c.x - 4 + i, c.y - 20 + absi(i - 4), Color(0.85, 0.93, 1.0, 0.85))
	_outline(img, Color("3c3a36"))


func _statue(img: Image) -> void:
	var base := Vector2(PROP_BASE)
	_shadow(img, 12, 4)
	_iso_box(img, base, 6.0, 6.0, 12.0, Color("aaa498"))
	var bronze := Color("6f6043")
	var x0 := int(base.x)
	var top := int(base.y) - 18
	_box(img, x0 - 3, top - 14, 6, 14, bronze)
	_box(img, x0 - 3, top - 14, 2, 14, bronze.lightened(0.15))
	_box(img, x0 + 3, top - 12, 2, 7, bronze.darkened(0.2))  # brazo
	for dy in range(-3, 3):
		for dx in range(-3, 3):
			if dx * dx + dy * dy <= 7:
				img.set_pixel(x0 + dx, top - 18 + dy, bronze.lightened(0.1) if dx < 0 else bronze)
	_outline(img, Color("2b2720"))


# =============================================================================
# Edificios: fachadas de un piso (las apila tools/build_art.gd)
# =============================================================================

const FLOOR_PX := WorldTiles.BUILDING_FLOOR_PX
const FACE_W := 32

## Estilo -> archivos de planta baja ("ground") y de pisos altos ("upper").
## El estilo es el nombre del suelo de su techo (WorldTiles.BUILDING_STYLES).
const FACADES := {
	"building": {"ground": ["0@3", "1@3", "2@1"], "upper": ["0@5", "1@2", "2@1"]},
	"roof_brick": {"ground": ["0@3", "1@3", "2@2"], "upper": ["0@5", "1@2", "2@1"]},
	"roof_concrete": {"ground": ["0@3", "1@2", "2@1"], "upper": ["0@5", "1@1", "2@1"]},
	"roof_dark": {"ground": ["0@3", "1@1"], "upper": ["0@4", "1@1"]},
	"roof_civic": {"ground": ["0@3", "1@1"], "upper": ["0@1"]},
	"roof_industrial": {"ground": ["0@2", "1@1"], "upper": ["0@3", "1@1"]},
}


func _buildings() -> void:
	for style: String in FACADES:
		for part: String in ["ground", "upper"]:
			var names: Array = FACADES[style][part]
			for variant in names.size():
				var img := Image.create_empty(WorldTiles.BUILDING_FACADE_SIZE.x, WorldTiles.BUILDING_FACADE_SIZE.y, false, Image.FORMAT_RGBA8)
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(style + part) + variant * 7919
				var painter: Callable = Callable(self, "_facade_" + style).bind(part == "ground", variant, rng)
				_facade(img, painter, part == "ground")
				_write("buildings/%s_%s_%s.png" % [style, part, names[variant]], img)


## Recorre los píxeles de las dos paredes visibles de un piso. painter(face, s, t):
## face 0 = pared izquierda (iluminada), 1 = derecha (en sombra); s = 0..31 a lo
## largo de la pared; t = 0..FLOOR_PX-1 desde arriba. Así las ventanas quedan
## inclinadas con la pared. La planta baja oscurece un poco su zócalo.
func _facade(img: Image, painter: Callable, ground_floor: bool) -> void:
	for x in WorldTiles.BUILDING_FACADE_SIZE.x:
		var face := 0 if x < FACE_W else 1
		var s := x if face == 0 else x - FACE_W
		var top := x / 2 if face == 0 else (WorldTiles.BUILDING_FACADE_SIZE.x - 1 - x) / 2
		for t in FLOOR_PX:
			var c: Color = painter.call(face, s, t)
			if c.a <= 0.0:
				continue
			if ground_floor and t >= FLOOR_PX - 2:
				c = c.darkened(0.35)  # zócalo
			if face == 1:
				c = c.darkened(0.24)
			img.set_pixel(x, top + t, c)


## Ventana: marco, vidrio con reflejo (o luz cálida) y alféizar. "" si (s, t) no cae en ella.
func _window(s: int, t: int, s0: int, t0: int, w: int, h: int, frame: Color, lit := false) -> Variant:
	if s < s0 or s >= s0 + w or t < t0 or t > t0 + h:
		return null
	if t == t0 + h:
		return frame.darkened(0.12)  # alféizar
	if s == s0 or s == s0 + w - 1 or t == t0 or t == t0 + h - 1 or t == t0 + h / 2:
		return frame
	if lit:
		return Color("f3d68e") if (s + t) % 7 != 0 else Color("e8c374")
	# Reflejo: franja clara en diagonal.
	return Color("a9c8e4") if posmod(s - t, 9) < 2 else (Color("7fa3c7") if t < t0 + h / 2 else Color("6a8db3"))


func _door(s: int, t: int, s0: int, w: int, wood: Color) -> Variant:
	if s < s0 or s >= s0 + w or t < 6:
		return null
	if s == s0 or s == s0 + w - 1 or t == 6:
		return wood.darkened(0.3)
	if s == s0 + w - 3 and t == 15:
		return Color("e0c060")  # manija
	return wood if (s - s0) % 3 != 0 else wood.darkened(0.1)


## Casas (techo de teja): pañete claro, ventanas con postigos, puerta de madera.
func _facade_building(face: int, s: int, t: int, ground_floor: bool, variant: int, rng: RandomNumberGenerator) -> Color:
	var wall := Color("eadbbd") if rng.randf() > 0.06 else Color("dfcfae")
	if t <= 1:
		wall = Color("cdb994")  # cornisa / entrepiso
	if ground_floor and variant == 1 and face == 0:
		var d: Variant = _door(s, t, 11, 10, Color("7a5234"))
		if d != null:
			return d
	var shutter := Color("4f7a5a") if variant != 2 else Color("8a5a3a")
	if (s == 8 or s == 9 or s == 22 or s == 23) and t >= 7 and t <= 19:
		return shutter if t % 2 == 0 else shutter.darkened(0.12)
	var win: Variant = _window(s, t, 10, 7, 12, 13, Color("f4efe4"), not ground_floor and variant == 2)
	if win != null:
		return win
	if not ground_floor and variant == 1 and t >= 20 and t <= 22 and s >= 9 and s <= 22:
		return Color("4e8f3c") if (s + t) % 3 else Color("e86a8a")  # matera con flores
	return wall


## Ladrillo a la vista (lo más común en Bogotá).
func _facade_roof_brick(face: int, s: int, t: int, ground_floor: bool, variant: int, rng: RandomNumberGenerator) -> Color:
	var row := t / 3
	var brick := (s + (row % 2) * 3) / 6
	var wall := Color("b65a3c") if (brick + row) % 3 != 0 else Color("a8513a")
	if t % 3 == 2 or (s + (row % 2) * 3) % 6 == 0:
		wall = Color("c9a58c")  # mortero
	if rng.randf() < 0.04:
		wall = wall.darkened(0.08)
	if t <= 1:
		wall = Color("d6c3ae")  # remate de concreto
	if ground_floor:
		if variant == 1 and face == 0:
			var d: Variant = _door(s, t, 10, 11, Color("5d4030"))
			if d != null:
				return d
		if variant == 2 and s >= 3 and s <= 28 and t >= 5:
			# Local con persiana metálica.
			if s == 3 or s == 28 or t == 5:
				return Color("6f747a")
			return Color("a7adb3") if t % 2 == 0 else Color("8f959b")
	var win: Variant = _window(s, t, 9, 6, 14, 14, Color("ece7dc"), not ground_floor and variant == 2)
	if win != null:
		return win
	if not ground_floor and variant == 1 and t >= 18 and t <= 23 and s >= 6 and s <= 25:
		# Balcón con baranda.
		if t == 18 or s == 6 or s == 25 or s % 3 == 0:
			return Color("3a3a3e")
		return Color(0, 0, 0, 0)
	return wall


## Concreto claro, ventanas corridas (oficinas y apartamentos).
func _facade_roof_concrete(face: int, s: int, t: int, ground_floor: bool, variant: int, rng: RandomNumberGenerator) -> Color:
	var wall := Color("cfccc4") if rng.randf() > 0.05 else Color("c4c1b9")
	if t <= 2:
		wall = Color("aeaaa1")  # placa
	if ground_floor:
		var awning: Color = [Color("d9534f"), Color("2f7fc1"), Color("3c9a5f")][variant % 3]
		if variant >= 1 and t >= 4 and t <= 6 and s >= 2 and s <= 29:
			return awning if s % 4 < 2 else awning.lightened(0.35)  # toldo
		if s >= 3 and s <= 28 and t >= 7:
			# Vitrina de local (o portería).
			if s == 3 or s == 28 or t == 7 or s == 15:
				return Color("55595f")
			return Color("9cc0dc") if posmod(s - t, 11) < 2 else Color("6f93b5")
		return wall
	var win: Variant = _window(s, t, 3, 7, 26, 12, Color("8a8d92"), variant == 2)
	if win != null:
		return win
	if variant == 1 and t >= 7 and t <= 19 and (s == 12 or s == 20):
		return Color("8a8d92")
	return wall


## Muro cortina de vidrio (edificios altos).
func _facade_roof_dark(face: int, s: int, t: int, ground_floor: bool, variant: int, rng: RandomNumberGenerator) -> Color:
	if t <= 3:
		return Color("3a404c")  # franja de losa
	if s % 8 == 0:
		return Color("2f3540")  # parteluz
	if ground_floor and variant == 1 and face == 0 and s >= 9 and s <= 22 and t >= 8:
		return Color("2f3540") if s == 9 or s == 22 or s == 16 else Color("d9e6f2")  # entrada iluminada
	var lit := not ground_floor and variant == 1 and (s / 8) % 2 == 1
	if lit:
		return Color("f0d58c")
	var reflect := posmod(s - t * 2, 23) < 4
	var base := Color("5f7f9f") if t < FLOOR_PX / 2 else Color("4d6b8a")
	if ground_floor:
		base = base.darkened(0.15)
	return base.lightened(0.25) if reflect else (base if rng.randf() > 0.04 else base.lightened(0.06))


## Edificios públicos: piedra clara, pilastras y ventanas en arco.
func _facade_roof_civic(face: int, s: int, t: int, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var wall := Color("e6d9bb")
	if t % 6 == 5 or (t / 6 + s / 8) % 2 == 0 and s % 8 == 0:
		wall = Color("cdbf9f")  # juntas de los bloques
	if s <= 1 or s >= 30:
		wall = Color("f2e8cf")  # pilastras
	if t <= 1:
		wall = Color("cdbf9f")
	# Arco: rectángulo con remate semicircular.
	var s0 := 11
	var w := 10
	var top := 5 if ground_floor and variant == 0 else 7
	var cx := s0 + (w - 1) / 2.0
	var in_rect := s >= s0 and s < s0 + w and t >= top + 4 and t < FLOOR_PX - (1 if ground_floor else 4)
	var in_arch := t >= top and t < top + 5 and Vector2(s - cx, (t - (top + 4)) * 1.1).length() <= w / 2.0
	if in_rect or in_arch:
		var edge := s == s0 or s == s0 + w - 1 or (in_arch and Vector2(s - cx, (t - (top + 4)) * 1.1).length() > w / 2.0 - 1.2)
		if edge:
			return Color("b8a882")
		if ground_floor and variant == 0:
			return Color("6b4a32") if (s - s0) % 3 != 0 else Color("5a3d29")  # portón de madera
		return Color("7fa3c7") if t < top + 6 else Color("6a8db3")
	return wall


## Bodegas: lámina ondulada (como su techo), portón enrollable en la planta baja.
func _facade_roof_industrial(face: int, s: int, t: int, ground_floor: bool, variant: int, rng: RandomNumberGenerator) -> Color:
	var wall := Color("8f9ba7") if s % 4 < 2 else Color("7d8994")
	if rng.randf() < 0.03:
		wall = wall.lightened(0.08)
	if ground_floor and variant == 0 and face == 0 and s >= 4 and s <= 27 and t >= 5:
		if s == 4 or s == 27 or t == 5:
			return Color("5e6872")
		return Color("c2c6ca") if t % 3 != 0 else Color("a5aaaf")
	if not ground_floor and variant == 1 and t >= 4 and t <= 8 and s >= 4 and s <= 27:
		return Color("5e6872") if t == 4 or t == 8 or s % 6 == 4 else Color("9cc0dc")
	return wall

# =============================================================================
# Iconos de categoría de los puntos de interés (assets/art/ui/poi/<cat>.png)
# =============================================================================

const POI_ICONS := {
	"food": ["X.X.X..", "X.X.X.X", "X.X.X.X", ".XXX.XX", "..X...X", "..X...X", "..X...X"],
	"shop": ["..XXX..", ".X...X.", "XXXXXXX", "XXXXXXX", "XXXXXXX", "XXXXXXX", ".XXXXX."],
	"health": ["..XXX..", "..XXX..", "XXXXXXX", "XXXXXXX", "XXXXXXX", "..XXX..", "..XXX.."],
	"education": ["...X...", ".XXXXX.", "XXXXXXX", ".XXXXX.", ".X...X.", ".XXXXX.", "...X..."],
	"worship": ["...X...", "..XXX..", "...X...", "..XXX..", ".XXXXX.", ".XX.XX.", ".XX.XX."],
	"money": ["...X...", ".XXXXX.", "X..X...", ".XXXXX.", "...X..X", ".XXXXX.", "...X..."],
	"transport": [".XXXXX.", "XXXXXXX", "X.X.X.X", "XXXXXXX", "XXXXXXX", ".X...X.", "......."],
	"culture": ["...X...", "..XXX..", "XXXXXXX", ".X.X.X.", ".X.X.X.", ".X.X.X.", "XXXXXXX"],
	"lodging": ["X......", "X.XX...", "XXXXXXX", "XXXXXXX", "X.....X", "X.....X", "......."],
	"sport": ["..XXX..", ".X.X.X.", "XXX.XXX", "X.XXX.X", "XXX.XXX", ".X.X.X.", "..XXX.."],
	"service": ["...X...", ".......", "..XX...", "...X...", "...X...", "...X...", "..XXX.."],
	"other": [".......", "..XXX..", ".XXXXX.", ".XXXXX.", ".XXXXX.", "..XXX..", "......."],
}


func _poi_icons() -> void:
	for cat: String in POI_ICONS:
		var rows: Array = POI_ICONS[cat]
		var img := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "X":
					img.set_pixel(x, y, Color.WHITE)
		_write("ui/poi/%s.png" % cat, img)


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
