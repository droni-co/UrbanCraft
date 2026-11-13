extends SceneTree
## Genera el arte inicial EDITABLE del juego en assets/art/ (un PNG por tile,
## variante y personaje). Es un punto de partida: edítalos o reemplázalos con
## tu propio arte (Krita, GIMP, Photoshop, Aseprite...).
##
## NUNCA sobrescribe un archivo que ya existe (tus cambios están a salvo).
## Para regenerar todo desde cero:  pnpm game:art:reset   (usa --force)
##
## Especificaciones (tamaños, anclas, nombres): assets/art/README.md
##
## Estilo ilustrado / suave, a WorldTiles.ART_SCALE (x4) del tamaño del mundo:
## todo se describe en px LÓGICOS (un tile mide 64x32) y el lienzo (Canvas)
## pinta al doble de la resolución final y luego reduce, así los bordes salen
## con antialias. Luz desde arriba a la izquierda.
##
## Las texturas de suelo son "sin costuras": el ruido es periódico sobre la
## grilla isométrica (u, v), así un tile encaja con sus vecinos y con las otras
## variantes del mismo tipo (comparten la base; solo cambian los detalles).
## Además se pintan un poco más allá del rombo (BLEED) para que, con filtro
## lineal, no se vean rendijas entre tiles.

const ART := "res://assets/art"
const S := WorldTiles.ART_SCALE
const W := 64
const H := 32
const PROP := Vector2i(64, 64)
## Base del prop (centro del rombo) dentro de su imagen, en px lógicos.
const PROP_BASE := Vector2(32, 48)
const FRAME := Vector2i(32, 48)
const FEET := Vector2i(16, 44)
const DIRECTIONS: PackedStringArray = ["e", "se", "s", "sw", "w", "nw", "n", "ne"]
const WALK_FRAMES := 4
## Cuánto se pinta el suelo fuera del rombo (en px lógicos, hacia afuera).
const BLEED := 0.8
const CLEAR := Color(0, 0, 0, 0)
## Dirección de la luz (x a la derecha, y hacia abajo, z hacia la cámara).
const LIGHT := Vector3(-0.5, -0.66, 0.56)

var force := false
var written := 0
var kept := 0


func _initialize() -> void:
	force = "--force" in OS.get_cmdline_user_args()
	var t0 := Time.get_ticks_msec()
	_ground_tiles()
	_props()
	_buildings()
	_poi_icons()
	_player_sheet()
	print("Arte inicial (x%d): %d archivos escritos, %d existentes conservados%s · %.1f s" % [
		S, written, kept, "" if force else " (usa --force para regenerarlos)", (Time.get_ticks_msec() - t0) / 1000.0])
	quit()


## true si hay que generar el archivo (no existe o --force).
func _wanted(relative: String) -> bool:
	if force:
		return true
	var path := ProjectSettings.globalize_path(ART + "/" + relative)
	var dir := path.get_base_dir()
	var stem := relative.get_file().get_basename().get_slice("@", 0)
	if DirAccess.dir_exists_absolute(dir):
		for existing in DirAccess.get_files_at(dir):
			if existing.get_extension() == "png" and existing.get_basename().get_slice("@", 0) == stem:
				kept += 1
				return false
	return true


func _write(relative: String, img: Image) -> void:
	var path := ProjectSettings.globalize_path(ART + "/" + relative)
	var dir := path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	# El peso va en el nombre (grass_1@3.png) y el usuario puede cambiarlo:
	# se compara por el nombre sin el peso.
	var stem := relative.get_file().get_basename().get_slice("@", 0)
	for existing in DirAccess.get_files_at(dir):
		if existing.get_extension() == "png" and existing.get_basename().get_slice("@", 0) == stem:
			DirAccess.remove_absolute(dir.path_join(existing))
	img.save_png(path)
	written += 1


# =============================================================================
# Lienzo, ruido y luz
# =============================================================================

## Lienzo en px lógicos. Pinta a ART_SCALE * SS px reales por px lógico y al
## terminar (finish) reduce a ART_SCALE: los bordes duros quedan suaves.
class Canvas:
	const SS := 2
	var art_scale: int
	var u: float
	var img: Image
	var logical: Vector2i

	func _init(size: Vector2i, scale: int) -> void:
		art_scale = scale
		u = float(scale * SS)
		logical = size
		img = Image.create_empty(int(size.x * u), int(size.y * u), false, Image.FORMAT_RGBA8)

	## Recorre los píxeles cuyo centro cae en `rect` (px lógicos):
	## f(p: Vector2) -> Color, con p en px lógicos. Alfa 0 = no pinta.
	func each(rect: Rect2, f: Callable) -> void:
		var x0 := maxi(0, floori(rect.position.x * u))
		var y0 := maxi(0, floori(rect.position.y * u))
		var x1 := mini(img.get_width(), ceili(rect.end.x * u))
		var y1 := mini(img.get_height(), ceili(rect.end.y * u))
		for y in range(y0, y1):
			var py := (y + 0.5) / u
			for x in range(x0, x1):
				var c: Color = f.call(Vector2((x + 0.5) / u, py))
				if c.a <= 0.0:
					continue
				if c.a >= 1.0:
					img.set_pixel(x, y, c)
				else:
					img.set_pixel(x, y, img.get_pixel(x, y).blend(c))

	func ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		each(Rect2(center - radius, radius * 2.0), func(p: Vector2) -> Color:
			return color if ((p - center) / radius).length_squared() <= 1.0 else Color(0, 0, 0, 0))

	## Anillo elíptico de grosor `width` (px lógicos, aprox.).
	func ring(center: Vector2, radius: Vector2, width: float, color: Color) -> void:
		var pad := Vector2(width, width)
		each(Rect2(center - radius - pad, radius * 2.0 + pad * 2.0), func(p: Vector2) -> Color:
			var d := ((p - center) / radius).length()
			return color if absf(d - 1.0) * minf(radius.x, radius.y) <= width * 0.5 else Color(0, 0, 0, 0))

	func poly(pts: PackedVector2Array, color: Color) -> void:
		var r := Rect2(pts[0], Vector2.ZERO)
		for q in pts:
			r = r.expand(q)
		each(r, func(p: Vector2) -> Color:
			return color if Geometry2D.is_point_in_polygon(p, pts) else Color(0, 0, 0, 0))

	## Trazo redondeado de a a b, de radio r.
	func line(a: Vector2, b: Vector2, r: float, color: Color) -> void:
		var rect := Rect2(a, Vector2.ZERO).expand(b).grow(r)
		each(rect, func(p: Vector2) -> Color:
			return color if p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r else Color(0, 0, 0, 0))

	func polyline(pts: PackedVector2Array, r: float, color: Color) -> void:
		for i in pts.size() - 1:
			line(pts[i], pts[i + 1], r, color)

	func finish() -> Image:
		var out := img.duplicate() as Image
		out.fix_alpha_edges()
		out.resize(logical.x * art_scale, logical.y * art_scale, Image.INTERPOLATE_BILINEAR)
		return out


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


## Ruido fractal periódico (varias octavas), de 0 a 1.
class Fbm:
	var octaves: Array[PeriodicNoise] = []
	var weights := PackedFloat32Array()

	func _init(base_grid: int, count: int, noise_seed: int) -> void:
		var w := 1.0
		var total := 0.0
		for i in count:
			octaves.append(PeriodicNoise.new(base_grid << i, noise_seed + i * 101))
			weights.append(w)
			total += w
			w *= 0.5
		for i in count:
			weights[i] /= total

	func at(uv: Vector2) -> float:
		var n := 0.0
		for i in octaves.size():
			n += octaves[i].at(uv.x, uv.y) * weights[i]
		return n


## Coordenadas isométricas de un punto (px lógicos): el tile vecino está en u+1 o v+1.
func _uv(p: Vector2) -> Vector2:
	var fx := p.x / W
	var fy := p.y / H
	return Vector2(fx + fy, fy - fx)


## Punto (px lógicos) de unas coordenadas isométricas (inversa de _uv).
func _from_uv(u: float, v: float) -> Vector2:
	return Vector2((u - v) * 0.5 * W, (u + v) * 0.5 * H)


## 0 en el centro del rombo, 1 en su borde.
func _diamond(p: Vector2) -> float:
	return absf(p.x - W * 0.5) / (W * 0.5) + absf(p.y - H * 0.5) / (H * 0.5)


## Distancia (aprox., px lógicos) del borde del rombo hacia adentro -> valor de _diamond.
func _diamond_margin(margin: float) -> float:
	return 1.0 - margin / 14.3


func _random_point(rng: RandomNumberGenerator, margin: float) -> Vector2:
	for i in 64:
		var p := Vector2(rng.randf_range(0, W), rng.randf_range(0, H))
		if _diamond(p) <= _diamond_margin(margin):
			return p
	return Vector2(W, H) * 0.5


## Valor fijo (-1..1) por píxel real: grano fino de la superficie.
func _grain(p: Vector2, salt := 0) -> float:
	return WorldTiles.cell_hash(int(p.x * 8.0), int(p.y * 8.0), 977 + salt) / 1073741823.5 - 1.0


func _sstep(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


func _shade(c: Color, amount: float) -> Color:
	return c.lightened(amount) if amount > 0.0 else c.darkened(-amount)


## Color iluminado: d = -1 (sombra, más frío) .. 0 (base) .. 1 (luz, más cálido).
func _lit(base: Color, d: float) -> Color:
	d = clampf(d, -1.0, 1.0)
	if d >= 0.0:
		return base.lerp(base.lightened(0.3).lerp(Color("fff1d0"), 0.14), d)
	return base.lerp(base.darkened(0.45).lerp(Color("1b2142"), 0.2), -d)


## Luz difusa de una normal (-1..1).
func _diffuse(n: Vector3) -> float:
	return n.normalized().dot(LIGHT.normalized())


## Normal de una esfera: q = punto relativo al centro / radio (|q| <= 1).
func _sphere_normal(q: Vector2) -> Vector3:
	return Vector3(q.x, q.y, sqrt(maxf(0.0, 1.0 - q.length_squared())))


# =============================================================================
# Suelo (64x32 lógicos -> 256x128)
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
			var relative := "tiles/ground/%s.png" % names[variant]
			if not _wanted(relative):
				continue
			var c := Canvas.new(Vector2i(W, H), S)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(kind) + variant * 7919
			call("_paint_" + kind, c, variant, rng)
			_write(relative, c.finish())


## Pinta el rombo (y BLEED más allá) con painter(p, uv) -> Color.
func _fill(c: Canvas, painter: Callable) -> void:
	var limit := 1.0 + BLEED / 14.3
	c.each(Rect2(0, 0, W, H), func(p: Vector2) -> Color:
		if _diamond(p) > limit:
			return CLEAR
		return painter.call(p, _uv(p)))


## Mezcla de tres tonos según t (0..1).
func _tones(a: Color, b: Color, c: Color, t: float) -> Color:
	return a.lerp(b, clampf(t * 2.0, 0.0, 1.0)) if t < 0.5 else b.lerp(c, clampf(t * 2.0 - 1.0, 0.0, 1.0))


## Mata de pasto: hojas finas en abanico.
func _tuft(c: Canvas, at: Vector2, rng: RandomNumberGenerator, dark: Color, light: Color) -> void:
	var blades := rng.randi_range(3, 5)
	for i in blades:
		var k := (i - (blades - 1) * 0.5)
		var base := at + Vector2(k * 0.45, 0)
		var tip := base + Vector2(k * 0.55 + rng.randf_range(-0.3, 0.3), -rng.randf_range(1.4, 2.4))
		var col := dark if i % 2 == 0 else light
		c.poly(PackedVector2Array([base + Vector2(-0.28, 0), base + Vector2(0.28, 0), tip]), col)


func _flower(c: Canvas, at: Vector2, petal: Color) -> void:
	c.line(at + Vector2(0, 0.3), at + Vector2(0, 1.6), 0.18, Color("3f7a33"))
	for a in 5:
		var d := Vector2.from_angle(TAU * a / 5.0 - PI / 2.0) * 0.55
		c.ellipse(at + Vector2(d.x, d.y * 0.7), Vector2(0.45, 0.36), petal)
	c.ellipse(at, Vector2(0.3, 0.25), Color("f2c94c"))


## Piedrita con volumen.
func _pebble(c: Canvas, at: Vector2, r: Vector2, base: Color) -> void:
	c.ellipse(at + Vector2(0.25, r.y * 0.55), r * Vector2(1.0, 0.7), Color(0, 0, 0, 0.22))
	c.each(Rect2(at - r, r * 2.0), func(p: Vector2) -> Color:
		var q := (p - at) / r
		if q.length_squared() > 1.0:
			return CLEAR
		return _lit(base, _diffuse(_sphere_normal(q)) * 1.2 - 0.15))


func _paint_grass(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(4, 3, 11)
	var leafy := PeriodicNoise.new(16, 12)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var n := tone.at(uv)
		var col := _tones(Color("4f9340"), Color("5fa548"), Color("74b857"), _sstep(0.28, 0.72, n))
		col = _shade(col, (leafy.at(uv.x, uv.y) - 0.5) * 0.12 + _grain(p) * 0.035)
		return col)
	for i in [34, 52, 34, 24][variant]:
		_tuft(c, _random_point(rng, 3.0), rng, Color("467f37"), Color("86c45f"))
	if variant == 2:  # flores
		for i in 8:
			_flower(c, _random_point(rng, 4.0), [Color("f7f2e6"), Color("f2d45c"), Color("ec8fb5")][i % 3])
	if variant == 3:  # trébol
		var center := _random_point(rng, 8.0)
		for i in 40:
			var d := Vector2(rng.randf_range(-5, 5), rng.randf_range(-2.2, 2.2))
			if (d / Vector2(5, 2.2)).length() <= 1.0:
				c.ellipse(center + d, Vector2(0.55, 0.4), Color("3f7d34") if rng.randf() < 0.7 else Color("6fb150"))


func _paint_grass_dark(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(4, 3, 21)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := _tones(Color("33602c"), Color("3d6f35"), Color("4b8040"), _sstep(0.25, 0.75, tone.at(uv)))
		return _shade(col, _grain(p) * 0.05))
	for i in 14:
		_tuft(c, _random_point(rng, 3.0), rng, Color("2c5527"), Color("5a9248"))
	for i in [6, 12, 8][variant]:  # hojarasca
		var at := _random_point(rng, 3.0)
		var leaf: Color = [Color("8a6a3e"), Color("a5783f"), Color("6b5232")][i % 3]
		c.ellipse(at, Vector2(0.9, 0.45), leaf)
		c.line(at - Vector2(0.7, 0), at + Vector2(0.7, 0), 0.08, leaf.darkened(0.3))
	if variant == 2:  # ramita
		var at := _random_point(rng, 7.0)
		c.polyline(PackedVector2Array([at, at + Vector2(3, 0.8), at + Vector2(5.5, 1.2)]), 0.3, Color("5a4026"))
		c.line(at + Vector2(3, 0.8), at + Vector2(4, -0.6), 0.2, Color("5a4026"))


func _paint_dirt(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(4, 3, 31)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := _tones(Color("86603d"), Color("9b7249"), Color("ad875c"), _sstep(0.25, 0.75, tone.at(uv)))
		return _shade(col, _grain(p) * 0.06))
	if variant == 2:  # charco seco
		var at := _random_point(rng, 8.0)
		c.each(Rect2(at - Vector2(7, 3.5), Vector2(14, 7)), func(p: Vector2) -> Color:
			var d := ((p - at) / Vector2(6.5, 3.0)).length()
			return Color(0.35, 0.22, 0.12, 0.35 * (1.0 - _sstep(0.6, 1.0, d))) if d < 1.0 else CLEAR)
	for i in [6, 11, 4][variant]:
		var r := rng.randf_range(0.5, 1.0)
		_pebble(c, _random_point(rng, 3.0), Vector2(r * 1.3, r), Color("b9a690"))


func _paint_sand(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(4, 2, 41)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("d9c086").lerp(Color("e8d39e"), _sstep(0.3, 0.7, tone.at(uv)))
		# Ondas periódicas (frecuencia entera: encajan con los vecinos).
		var wave := sin(TAU * (uv.x * 3.0 + uv.y) + tone.at(uv) * 2.0)
		col = _shade(col, _sstep(0.55, 0.95, wave) * 0.1 - _sstep(-0.95, -0.6, -wave) * 0.03)
		return _shade(col, _grain(p) * 0.04))
	if variant == 1:  # conchitas
		for i in 4:
			var at := _random_point(rng, 4.0)
			c.ellipse(at, Vector2(0.8, 0.55), Color("fbf3e4"))
			c.line(at + Vector2(-0.4, 0.1), at + Vector2(0.4, 0.1), 0.08, Color("d8b9a0"))


func _paint_water(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(4, 3, 51)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var n := tone.at(uv)
		var col := _tones(Color("2c64b4"), Color("3674c8"), Color("4385d8"), _sstep(0.25, 0.75, n))
		var wave := sin(TAU * (uv.x * 2.0 + uv.y * 3.0) + n * 6.0)
		col = col.lerp(Color("8cc2f2"), _sstep(0.86, 1.0, wave) * 0.45)
		return col)
	# Reflejos: guiones claros.
	for i in [6, 9, 7][variant]:
		var at := _random_point(rng, 3.0)
		var length := rng.randf_range(2.0, 4.5)
		c.line(at, at + Vector2(length, 0), 0.22, Color(0.82, 0.92, 1.0, 0.7))
	if variant == 2:
		for i in 3:
			var at := _random_point(rng, 4.0)
			c.ellipse(at, Vector2(0.35, 0.35), Color(1, 1, 1, 0.85))


## Adoquines: 4x4 por tile en la grilla (u, v), redondeados, con junta oscura.
func _paint_stone(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var shades := PackedFloat32Array()
	var srng := RandomNumberGenerator.new()
	srng.seed = 61
	for i in 16:
		shades.append(srng.randf_range(-0.08, 0.08))
	var wear := Fbm.new(4, 2, 62)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var a := uv.x * 4.0
		var b := uv.y * 4.0
		var q := Vector2(a - floorf(a) - 0.5, b - floorf(b) - 0.5)
		var corner := (q.abs() - Vector2(0.3, 0.3)).max(Vector2.ZERO).length() - 0.12
		if corner > 0.0:
			return _shade(Color("67646a"), _grain(p) * 0.06)
		var col := _shade(Color("9d9ca5"), shades[posmod(floori(a), 4) * 4 + posmod(floori(b), 4)])
		# Bisel: el borde que mira a la luz (-u) más claro, el opuesto más oscuro.
		var edge := _sstep(-0.1, 0.0, corner)
		var facing := -(q.normalized().x * 0.9 + q.normalized().y * 0.35)
		col = _shade(col, edge * facing * 0.22 + (wear.at(uv) - 0.5) * 0.1 + _grain(p) * 0.03)
		return col)
	if variant == 1:  # desgaste y musgo entre juntas
		for i in 10:
			var at := _random_point(rng, 2.0)
			c.ellipse(at, Vector2(0.6, 0.35), Color(0.36, 0.5, 0.27, 0.6))


func _paint_asphalt(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(8, 2, 71)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("41444c").lerp(Color("4b4e57"), _sstep(0.3, 0.7, tone.at(uv)))
		var g := _grain(p)
		col = _shade(col, g * 0.06)
		if g > 0.94:
			col = col.lightened(0.18)  # piedrita del agregado
		return col)
	if variant == 1:  # grieta
		var at := _random_point(rng, 7.0)
		var pts := PackedVector2Array([at])
		for k in 7:
			at += Vector2(rng.randf_range(1.0, 2.0), rng.randf_range(-0.8, 0.8))
			pts.append(at)
		c.polyline(pts, 0.32, Color("2c2e33"))
		c.line(pts[3], pts[3] + Vector2(1.0, 1.4), 0.2, Color("2c2e33"))
	if variant == 2:  # alcantarilla
		var center := Vector2(W, H) * 0.5
		c.ellipse(center + Vector2(0, 0.4), Vector2(8.6, 4.4), Color(0, 0, 0, 0.3))
		c.ellipse(center, Vector2(8.5, 4.25), Color("666a73"))
		c.each(Rect2(center - Vector2(7, 3.5), Vector2(14, 7)), func(p: Vector2) -> Color:
			var q := (p - center) / Vector2(7, 3.5)
			if q.length() > 1.0:
				return CLEAR
			var bars := posmod(int(floorf((p.x - p.y * 2.0) / 1.6)), 2) == 0
			return Color("2f3237") if bars else Color("4d515a"))


func _paint_pavement(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	# Baldosas: 2x2 por tile, con junta y un leve bisel.
	var shades := PackedFloat32Array([0.0, -0.04, 0.03, -0.02])
	var tone := Fbm.new(4, 2, 72)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var a := uv.x * 2.0
		var b := uv.y * 2.0
		var fa := a - floorf(a)
		var fb := b - floorf(b)
		if fa < 0.03 or fb < 0.03 or fa > 0.985 or fb > 0.985:
			return Color("9d9586")
		var col := _shade(Color("cbc4b6"), shades[posmod(floori(a), 2) * 2 + posmod(floori(b), 2)])
		if fa < 0.07 or fb < 0.07:
			col = col.lightened(0.07)
		elif fa > 0.95 or fb > 0.95:
			col = col.darkened(0.06)
		return _shade(col, (tone.at(uv) - 0.5) * 0.06 + _grain(p) * 0.03))
	if variant == 1:  # baldosa rajada
		var at := _random_point(rng, 7.0)
		c.polyline(PackedVector2Array([at, at + Vector2(2.5, 0.4), at + Vector2(4, 1.4), at + Vector2(6.5, 1.6)]), 0.18, Color("857d6e"))
	if variant == 2:  # rejilla de desagüe
		var center := Vector2(W, H) * 0.5
		c.poly(PackedVector2Array([center + Vector2(-6, 0), center + Vector2(0, -3), center + Vector2(6, 0), center + Vector2(0, 3)]), Color("6a6c72"))
		for k in range(-4, 5):
			var o := Vector2(k * 0.7, k * 0.35)
			c.line(center + o + Vector2(-2.2, 1.1), center + o + Vector2(2.2, -1.1) * 0.9, 0.16, Color("33353a"))


## Tejado de tejas de barro (casas).
func _paint_building(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var hues := PackedFloat32Array()
	var srng := RandomNumberGenerator.new()
	srng.seed = 81
	for i in 64:
		hues.append(srng.randf_range(-0.07, 0.07))
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var row := uv.y * 8.0
		var fr := row - floorf(row)
		var col_f := uv.x * 8.0 + 0.5 * posmod(floori(row), 2)
		var fc := col_f - floorf(col_f)
		var col := _shade(Color("ad553e"), hues[posmod(floori(row), 8) * 8 + posmod(floori(col_f), 8)])
		# Cada teja: sombra de la hilera de arriba, luz en su lomo.
		col = _shade(col, -0.32 * (1.0 - _sstep(0.0, 0.22, fr)) + 0.14 * _sstep(0.55, 0.9, fr))
		col = _shade(col, -0.16 * (1.0 - _sstep(0.0, 0.08, fc)) + 0.08 * sin(fc * PI))
		return _shade(col, _grain(p) * 0.03))
	if variant == 1:  # chimenea
		var at := _random_point(rng, 8.0)
		_iso_box(c, at, 1.8, 1.8, 4.0, Color("b35f45"))
		c.poly(_iso_top(at + Vector2(0, -4.0), 1.2, 1.2), Color("2b2523"))
	if variant == 2:  # claraboya
		_skylight(c, _random_point(rng, 9.0), 0.16, 0.1)


## Ladrillo a la vista (azoteas de Bogotá): hiladas a lo largo de u.
func _paint_roof_brick(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var hues := PackedFloat32Array()
	var srng := RandomNumberGenerator.new()
	srng.seed = 91
	for i in 50:
		hues.append(srng.randf_range(-0.09, 0.09))
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var row := uv.y * 10.0
		var fr := row - floorf(row)
		var col_f := uv.x * 5.0 + 0.5 * posmod(floori(row), 2)
		var fc := col_f - floorf(col_f)
		if fr < 0.14 or fc < 0.04:
			return _shade(Color("c7a389"), _grain(p) * 0.05)  # mortero
		var col := _shade(Color("b2583b"), hues[posmod(floori(row), 10) * 5 + posmod(floori(col_f), 5)])
		col = _shade(col, 0.08 * (1.0 - _sstep(0.14, 0.3, fr)) - 0.08 * _sstep(0.8, 1.0, fr))
		return _shade(col, _grain(p) * 0.05))
	if variant == 1:
		_water_tank(c, rng)
	if variant == 2:
		_vent(c, rng)


## Losa de concreto clara, en paneles.
func _paint_roof_concrete(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var stains := Fbm.new(4, 3, 33)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("bab7af").lerp(Color("a9a69e"), _sstep(0.45, 0.8, stains.at(uv)))
		var fa := uv.x * 2.0 - floorf(uv.x * 2.0)
		var fb := uv.y * 2.0 - floorf(uv.y * 2.0)
		if fa < 0.02 or fb < 0.02:
			col = Color("97948c")
		return _shade(col, _grain(p) * 0.035))
	if variant == 1:
		_water_tank(c, rng)
	if variant == 2:
		_ac_unit(c, rng)


## Grava oscura / tela asfáltica (oficinas, comercio alto).
func _paint_roof_dark(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(8, 2, 34)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("525867").lerp(Color("5f6676"), _sstep(0.3, 0.7, tone.at(uv)))
		return _shade(col, _grain(p) * 0.1))
	if variant == 1:  # claraboya de vidrio
		_skylight(c, _random_point(rng, 10.0), 0.22, 0.14)


## Edificios públicos (iglesias, colegios, hospitales): teja crema.
func _paint_roof_civic(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var row := uv.y * 6.0
		var fr := row - floorf(row)
		var col := Color("dbc199")
		col = _shade(col, -0.25 * (1.0 - _sstep(0.0, 0.2, fr)) + 0.1 * _sstep(0.6, 0.95, fr))
		col = _shade(col, sin(TAU * uv.x * 24.0) * 0.06)  # tejas de canal
		return _shade(col, _grain(p) * 0.03))
	if variant == 1:  # remate / campanario visto desde arriba
		var center := Vector2(W, H) * 0.5
		c.poly(PackedVector2Array([center + Vector2(-8, 0), center + Vector2(0, -4), center + Vector2(0, 4)]), Color("b0593f"))
		c.poly(PackedVector2Array([center + Vector2(8, 0), center + Vector2(0, -4), center + Vector2(0, 4)]), Color("8a432f"))
		c.ellipse(center, Vector2(0.6, 0.6), Color("e3c35a"))


## Lámina metálica ondulada (bodegas, industria).
func _paint_roof_industrial(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var rust := Fbm.new(4, 3, 35)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("8996a3")
		col = _shade(col, sin(TAU * uv.x * 16.0) * 0.12)
		var fb := uv.y * 2.0 - floorf(uv.y * 2.0)
		if fb < 0.025:
			col = col.darkened(0.25)  # traslape de láminas
		if variant == 1:
			col = col.lerp(Color("98653f"), _sstep(0.58, 0.7, rust.at(uv)) * 0.85)
		return _shade(col, _grain(p) * 0.03))


## Paso de cebra: asfalto con franjas blancas gastadas.
func _paint_crosswalk(c: Canvas, _variant: int, rng: RandomNumberGenerator) -> void:
	var wear := Fbm.new(8, 2, 36)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := _shade(Color("464951"), _grain(p) * 0.06)
		if posmod(floori(uv.x * 6.0), 2) == 0:
			var worn := _sstep(0.66, 0.8, wear.at(uv)) * 0.45
			col = _shade(Color("e8e6de"), _grain(p) * 0.03).lerp(col, worn)
		return col)


## Vía férrea: balasto con traviesas y rieles.
func _paint_rail(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var gravel := PeriodicNoise.new(32, 37)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := _tones(Color("6f695f"), Color("8a8478"), Color("a29c90"), gravel.at(uv.x, uv.y))
		col = _shade(col, _grain(p) * 0.08)
		var fu := uv.x * 4.0 - floorf(uv.x * 4.0)
		if fu > 0.05 and fu < 0.25:
			col = _shade(Color("6b4f36"), (fu - 0.15) * -0.8 + _grain(p, 1) * 0.04)  # traviesa
		var fv := uv.y - floorf(uv.y)
		for rail: float in [0.3, 0.7]:
			var d := fv - rail
			if absf(d) < 0.05:
				col = Color("c4c9d1").lerp(Color("7f848c"), _sstep(-0.05, 0.05, d))  # riel
			elif d > 0.05 and d < 0.08:
				col = col.darkened(0.25)  # sombra del riel
		return col)
	if variant == 1:  # maleza entre el balasto
		for i in 7:
			_tuft(c, _random_point(rng, 3.0), rng, Color("4f7f33"), Color("7aa84f"))


## Ciclorruta: pavimento rojo.
func _paint_cycleway(c: Canvas, variant: int, rng: RandomNumberGenerator) -> void:
	var tone := Fbm.new(8, 2, 38)
	_fill(c, func(p: Vector2, uv: Vector2) -> Color:
		var col := Color("9a443a").lerp(Color("ab5244"), _sstep(0.3, 0.7, tone.at(uv)))
		return _shade(col, _grain(p) * 0.06))
	if variant == 1:  # bicicleta pintada
		var center := Vector2(W, H) * 0.5
		var white := Color(0.95, 0.95, 0.92, 0.95)
		c.ring(center + Vector2(-5, 0.5), Vector2(3, 1.8), 0.45, white)
		c.ring(center + Vector2(5, 0.5), Vector2(3, 1.8), 0.45, white)
		c.polyline(PackedVector2Array([center + Vector2(-5, 0.5), center + Vector2(-1, -1.5), center + Vector2(3, -1.5), center + Vector2(5, 0.5)]), 0.25, white)
		c.polyline(PackedVector2Array([center + Vector2(-1, -1.5), center + Vector2(0.5, 0.5), center + Vector2(3, -1.5)]), 0.25, white)


## Tanque de agua (los negros de las azoteas), visto desde arriba.
func _water_tank(c: Canvas, rng: RandomNumberGenerator) -> void:
	var at := _random_point(rng, 10.0)
	_cylinder(c, at, Vector2(4.5, 2.6), 3.0, Color("33373f"))
	c.ellipse(at + Vector2(0, -3.0), Vector2(2.0, 1.1), Color("454a54"))
	c.ring(at + Vector2(0, -3.0), Vector2(2.0, 1.1), 0.3, Color("23262c"))


func _vent(c: Canvas, rng: RandomNumberGenerator) -> void:
	var at := _random_point(rng, 8.0)
	_iso_box(c, at, 2.0, 1.5, 2.5, Color("9a9ba1"))
	for k in 3:
		c.line(at + Vector2(-1.6 + k * 0.6, -1.6 + k * 0.3), at + Vector2(-0.4 + k * 0.6, -2.2 + k * 0.3), 0.12, Color("5d5e64"))


func _ac_unit(c: Canvas, rng: RandomNumberGenerator) -> void:
	var at := _random_point(rng, 9.0)
	_iso_box(c, at, 3.0, 2.0, 2.4, Color("d6d8dc"))
	var top := at + Vector2(0, -2.4)
	c.ellipse(top, Vector2(1.6, 0.8), Color("5d6168"))
	c.ring(top, Vector2(1.6, 0.8), 0.2, Color("3e4147"))


## Claraboya de vidrio en el plano del techo (u, v); size en fracciones de tile.
func _skylight(c: Canvas, at: Vector2, su: float, sv: float) -> void:
	var uv := _uv(at)
	var quad := func(du0: float, dv0: float, du1: float, dv1: float) -> PackedVector2Array:
		return PackedVector2Array([_from_uv(uv.x + du0, uv.y + dv0), _from_uv(uv.x + du1, uv.y + dv0),
			_from_uv(uv.x + du1, uv.y + dv1), _from_uv(uv.x + du0, uv.y + dv1)])
	c.poly(quad.call(-su * 0.5 - 0.02, -sv * 0.5 - 0.02, su * 0.5 + 0.02, sv * 0.5 + 0.02), Color("d5d8de"))
	var glass: PackedVector2Array = quad.call(-su * 0.5, -sv * 0.5, su * 0.5, sv * 0.5)
	var r := Rect2(glass[0], Vector2.ZERO)
	for q in glass:
		r = r.expand(q)
	c.each(r, func(p: Vector2) -> Color:
		if not Geometry2D.is_point_in_polygon(p, glass):
			return CLEAR
		var t := (p.y - r.position.y) / maxf(r.size.y, 0.001)
		var col := Color("a6cbe9").lerp(Color("5f86ad"), t)
		if posmod(p.x - p.y * 1.5, 6.0) < 0.9:
			col = col.lightened(0.3)
		return col)


# =============================================================================
# Formas con volumen (props, techos)
# =============================================================================

## Esquinas de la cara de arriba de una caja isométrica (base en su centro).
func _iso_top(o: Vector2, a: float, b: float) -> PackedVector2Array:
	var du := Vector2(1, 0.5)
	var dv := Vector2(-1, 0.5)
	return PackedVector2Array([o - du * a - dv * b, o + du * a - dv * b, o + du * a + dv * b, o - du * a + dv * b])


## Caja isométrica: base (centro de su planta), semilados a (eje u) y b (eje v)
## en px de pantalla, alto h, elevada z. Luz desde arriba a la izquierda.
func _iso_box(c: Canvas, base: Vector2, a: float, b: float, h: float, top: Color, z := 0.0) -> void:
	var o := base + Vector2(0, -z)
	var t := _iso_top(o, a, b)
	var up := Vector2(0, -h)
	# Cara izquierda (mira al sur-oeste) y derecha (sur-este), con un leve degradé.
	_gradient_poly(c, PackedVector2Array([t[3], t[2], t[2] + up, t[3] + up]), _lit(top, -0.35), _lit(top, -0.2))
	_gradient_poly(c, PackedVector2Array([t[2], t[1], t[1] + up, t[2] + up]), _lit(top, -0.7), _lit(top, -0.55))
	c.poly(PackedVector2Array([t[0] + up, t[1] + up, t[2] + up, t[3] + up]), _lit(top, 0.15))
	# Arista frontal iluminada.
	c.line(t[3] + up, t[2] + up, 0.12, _lit(top, 0.45))


## Polígono con degradé vertical (abajo -> arriba).
func _gradient_poly(c: Canvas, pts: PackedVector2Array, bottom: Color, top: Color) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	c.each(r, func(p: Vector2) -> Color:
		if not Geometry2D.is_point_in_polygon(p, pts):
			return CLEAR
		return top.lerp(bottom, (p.y - r.position.y) / maxf(r.size.y, 0.001)))


## Cilindro vertical de planta elíptica (radio r), alto h, sobre `base`.
func _cylinder(c: Canvas, base: Vector2, r: Vector2, h: float, color: Color) -> void:
	c.each(Rect2(base - Vector2(r.x, r.y + h), Vector2(r.x * 2.0, r.y * 2.0 + h)), func(p: Vector2) -> Color:
		var nx := (p.x - base.x) / r.x
		if absf(nx) > 1.0:
			return CLEAR
		var ry := r.y * sqrt(1.0 - nx * nx)
		if p.y > base.y + ry or p.y < base.y - h - ry:
			return CLEAR
		if p.y < base.y - h + ry and ((p - (base + Vector2(0, -h))) / r).length_squared() <= 1.0:
			return _lit(color, 0.25)  # tapa
		return _lit(color, _diffuse(Vector3(nx, 0, sqrt(1.0 - nx * nx))) * 1.1 - 0.2))


## Poste cilíndrico vertical en x, de top a bottom, de radio r.
func _pole(c: Canvas, x: float, top: float, bottom: float, r: float, color: Color) -> void:
	c.each(Rect2(x - r, top, r * 2.0, bottom - top), func(p: Vector2) -> Color:
		var nx := (p.x - x) / r
		if absf(nx) > 1.0:
			return CLEAR
		return _lit(color, _diffuse(Vector3(nx, 0, sqrt(1.0 - nx * nx))) * 1.2 - 0.15))


## Volumen redondeado (elipse con luz de esfera). La luz se calcula sobre la
## esfera (light_center, light_radius) si se da: varios bultos se ven como uno.
func _blob(c: Canvas, center: Vector2, radius: Vector2, base: Color, light_center := Vector2.INF, light_radius := 0.0, bump := 0.6) -> void:
	var lc := center if light_center == Vector2.INF else light_center
	var lr := maxf(radius.x, radius.y) if light_radius == 0.0 else light_radius
	c.each(Rect2(center - radius, radius * 2.0), func(p: Vector2) -> Color:
		var q := (p - center) / radius
		if q.length_squared() > 1.0:
			return CLEAR
		var g := (p - lc) / lr
		if g.length_squared() > 1.0:
			g = g.normalized() * 0.999
		var n := _sphere_normal(g) + _sphere_normal(q) * bump
		var d := _diffuse(n) * 1.25 - 0.25
		d -= _sstep(0.7, 1.0, q.length()) * 0.25  # borde del bulto, un poco más oscuro
		return _lit(base, d + _grain(p, 3) * 0.04))


## Sombra suave en el suelo, centrada en `at`.
func _shadow(c: Canvas, at: Vector2, r: Vector2, alpha := 0.32) -> void:
	c.each(Rect2(at - r, r * 2.0), func(p: Vector2) -> Color:
		var d := ((p - at) / r).length()
		return Color(0, 0, 0, alpha * (1.0 - _sstep(0.45, 1.0, d))) if d < 1.0 else CLEAR)


## Contorno suave alrededor de lo opaco (a resolución final): `width` px reales.
func _soft_outline(img: Image, color: Color, width := 2) -> Image:
	var w := img.get_width()
	var h := img.get_height()
	var alpha := PackedFloat32Array()
	alpha.resize(w * h)
	for y in h:
		for x in w:
			alpha[y * w + x] = img.get_pixel(x, y).a
	# Dilatación separable (máximo en una ventana de 2*width+1).
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	for y in h:
		for x in w:
			var m := 0.0
			for k in range(maxi(0, x - width), mini(w, x + width + 1)):
				m = maxf(m, alpha[y * w + k])
			tmp[y * w + x] = m
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var m := 0.0
			for k in range(maxi(0, y - width), mini(h, y + width + 1)):
				m = maxf(m, tmp[k * w + x])
			var under := Color(color, minf(1.0, m * 1.15) * color.a)
			out.set_pixel(x, y, under.blend(img.get_pixel(x, y)))
	return out


# =============================================================================
# Props (64x64 lógicos -> 256x256, base en PROP_BASE)
# =============================================================================

const OUTLINE := Color(0.1, 0.14, 0.09, 0.85)


func _props() -> void:
	var specs := {
		"tree_0@3": _tree.bind(Color("4f9a3a"), 17.0, 15.0, 0),
		"tree_1@2": _tree.bind(Color("63ad47"), 14.0, 18.0, 1),
		"pine_0@3": _pine.bind(3, 0),
		"pine_1@2": _pine.bind(4, 1),
		"rock_0@3": _rock.bind(13.0, 9.0, 0),
		"rock_1@2": _rock.bind(9.0, 7.0, 1),
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
		var relative := "props/%s.png" % name
		if not _wanted(relative):
			continue
		var c := Canvas.new(PROP, S)
		var painter: Callable = specs[name]
		var outline: Color = painter.call(c)
		_write(relative, _soft_outline(c.finish(), outline))


func _trunk(c: Canvas, top: float, width: float, bottom := PROP_BASE.y + 0.5) -> void:
	var x := PROP_BASE.x
	c.each(Rect2(x - width, top, width * 2.0, bottom - top), func(p: Vector2) -> Color:
		var t := (p.y - top) / (bottom - top)
		var hw := width * 0.5 * (0.8 + t * 0.35)  # se ensancha hacia la raíz
		var nx := (p.x - x) / hw
		if absf(nx) > 1.0:
			return CLEAR
		var bark := sin(p.x * 5.0 + sin(p.y * 1.3) * 2.0) * 0.06
		return _lit(Color("7a5332"), _diffuse(Vector3(nx, 0, sqrt(1.0 - nx * nx))) * 1.1 - 0.2 + bark))


## Árbol de copa redonda: muchos racimos de hojas que comparten la luz de la copa.
func _tree(c: Canvas, color: Color, rx: float, ry: float, variant: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	_shadow(c, PROP_BASE + Vector2(2, 0), Vector2(16, 5.5))
	_trunk(c, 26.0, 5.0)
	var center := Vector2(PROP_BASE.x, 22.0 - (ry - 15.0))
	var radius := Vector2(rx, ry)
	_blob(c, center + Vector2(0, 1), radius * 0.9, color.darkened(0.3), center, rx, 0.0)
	var clusters: Array[Vector2] = []
	for i in 30:
		var a := rng.randf() * TAU
		var d := sqrt(rng.randf()) * 0.78
		clusters.append(center + Vector2(cos(a), sin(a)) * radius * d)
	clusters.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for p in clusters:
		var r := rng.randf_range(3.6, 5.4)
		_blob(c, p, Vector2(r, r * 0.88), color, center, rx * 1.05, 0.55)
	# Brillos sueltos en la parte iluminada.
	for i in 14:
		var p := center + Vector2(rng.randf_range(-0.7, 0.1) * rx, rng.randf_range(-0.85, -0.1) * ry)
		if ((p - center) / radius).length() < 0.75:
			c.ellipse(p, Vector2(0.7, 0.5), Color(color.lightened(0.45), 0.75))
	return OUTLINE


func _pine(c: Canvas, tiers: int, variant: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = 950 + variant
	_shadow(c, PROP_BASE + Vector2(2, 0), Vector2(12, 4.5))
	_trunk(c, 40.0, 4.0)
	var color := Color("2f6b3f")
	var top := 3.0 if tiers == 4 else 7.0
	var tier_h := 12.5 if tiers == 4 else 13.5
	for t in tiers:
		var y0 := top + t * (tier_h - 4.0)
		var half := 7.5 + t * 3.0
		var apex := Vector2(PROP_BASE.x, y0)
		var teeth := 5 + t
		c.each(Rect2(apex.x - half - 1, y0, half * 2 + 2, tier_h + 1.5), func(p: Vector2) -> Color:
			var dy := p.y - y0
			var k := dy / tier_h
			var hw := half * k
			# Borde de abajo dentado (puntas de ramas).
			var along := (p.x - (apex.x - half)) / (half * 2.0) * teeth
			var tooth := absf(along - floorf(along) - 0.5) * 2.0
			if absf(p.x - apex.x) > hw or dy > tier_h - 1.4 + tooth * 1.4 or dy < 0.0:
				return CLEAR
			var nx := (p.x - apex.x) / maxf(hw, 0.01)
			var d := _diffuse(Vector3(nx * 0.9, -0.35, 0.6)) * 1.3 - 0.2
			d -= _sstep(0.6, 1.0, k) * 0.35  # la falda de cada piso, en sombra
			return _lit(color, d + _grain(p, 5) * 0.06 + sin(p.x * 3.0 + p.y * 2.0) * 0.04))
	return Color(0.06, 0.15, 0.09, 0.85)


func _rock(c: Canvas, rx: float, ry: float, variant: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = 970 + variant
	_shadow(c, PROP_BASE + Vector2(1.5, 0), Vector2(rx + 2, 5.0))
	var center := Vector2(PROP_BASE.x + 0.5, PROP_BASE.y - ry + 2)
	_blob(c, center, Vector2(rx, ry), Color("8f8f98"), Vector2.INF, 0.0, 0.0)
	_blob(c, center + Vector2(rx * 0.55, ry * 0.3), Vector2(rx * 0.5, ry * 0.6), Color("7f7f88"), center, rx, 0.4)
	# Grieta con borde claro.
	var crack := PackedVector2Array([center + Vector2(-2, -ry * 0.55), center + Vector2(-0.8, -ry * 0.1), center + Vector2(-1.6, ry * 0.25), center + Vector2(-0.4, ry * 0.6)])
	c.polyline(crack, 0.3, Color("55555d"))
	if variant == 0:  # musgo arriba
		for i in 9:
			c.ellipse(center + Vector2(rng.randf_range(-rx * 0.6, rx * 0.3), -ry * 0.75 + rng.randf_range(0, 2.5)), Vector2(1.6, 0.8), Color(0.42, 0.6, 0.3, 0.8))
	return Color(0.12, 0.12, 0.14, 0.85)


func _bush(c: Canvas, flowers: bool, variant: int) -> Color:
	var rng := RandomNumberGenerator.new()
	rng.seed = 990 + variant
	_shadow(c, PROP_BASE + Vector2(1, 0), Vector2(16, 5.5))
	var color := Color("4c8f3a")
	var center := Vector2(PROP_BASE.x, 40.0)
	_blob(c, center + Vector2(0, 1), Vector2(14, 8), color.darkened(0.3), center, 14.0, 0.0)
	var clusters: Array[Vector2] = []
	for i in 16:
		clusters.append(center + Vector2(rng.randf_range(-11, 11), rng.randf_range(-6, 4)))
	clusters.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.y < b.y)
	for p in clusters:
		var r := rng.randf_range(3.2, 4.6)
		_blob(c, p, Vector2(r, r * 0.85), color, center, 14.0, 0.55)
	if flowers:
		for i in 12:
			var p := center + Vector2(rng.randf_range(-11, 11), rng.randf_range(-7, 4))
			var petal := Color("f7c6d9") if i % 2 == 0 else Color("fff4f0")
			for a in 5:
				c.ellipse(p + Vector2.from_angle(TAU * a / 5.0) * 0.55, Vector2(0.5, 0.4), petal)
			c.ellipse(p, Vector2(0.3, 0.3), Color("f2c94c"))
	return OUTLINE


func _bench(c: Canvas) -> Color:
	var base := PROP_BASE
	_shadow(c, base + Vector2(1, 0.5), Vector2(15, 5.5))
	var wood := Color("a8743f")
	var iron := Color("3a3d44")
	for side: float in [-1.0, 1.0]:
		_iso_box(c, base + Vector2(1, 0.5) * 8.0 * side, 0.8, 2.6, 6.0, iron)
	for k in 3:  # tablas del asiento
		_iso_box(c, base + Vector2(-1, 0.5) * (k - 1) * 1.8, 10.5, 0.75, 1.2, wood.lightened(0.04 * k), 6.0)
	for k in 2:  # espaldar
		_iso_box(c, base + Vector2(-1, 0.5) * -3.2, 10.5, 0.5, 1.6, wood.darkened(0.06), 9.0 + k * 2.6)
	_iso_box(c, base + Vector2(-1, 0.5) * -3.2 + Vector2(1, 0.5) * 8.0, 0.5, 0.5, 6.0, iron, 6.0)
	_iso_box(c, base + Vector2(-1, 0.5) * -3.2 - Vector2(1, 0.5) * 8.0, 0.5, 0.5, 6.0, iron, 6.0)
	return Color(0.16, 0.12, 0.09, 0.85)


## Halo de luz cálida.
func _glow(c: Canvas, at: Vector2, r: Vector2, color: Color) -> void:
	c.each(Rect2(at - r, r * 2.0), func(p: Vector2) -> Color:
		var d := ((p - at) / r).length()
		return Color(color, color.a * pow(1.0 - d, 2.0)) if d < 1.0 else CLEAR)


func _street_lamp(c: Canvas) -> Color:
	_shadow(c, PROP_BASE + Vector2(1, 0), Vector2(5, 2))
	var grey := Color("68707d")
	_iso_box(c, PROP_BASE, 2.2, 2.2, 3.0, grey.darkened(0.15))
	_pole(c, PROP_BASE.x, 8.0, PROP_BASE.y - 2.0, 0.9, grey)
	c.polyline(PackedVector2Array([Vector2(PROP_BASE.x, 9.5), Vector2(PROP_BASE.x + 1.5, 7.6), Vector2(PROP_BASE.x + 5, 7.4), Vector2(PROP_BASE.x + 7, 8.6)]), 0.55, grey)
	# Farol: pantalla oscura y vidrio encendido.
	var head := Vector2(PROP_BASE.x + 7, 9.0)
	c.poly(PackedVector2Array([head + Vector2(-3, 0), head + Vector2(3, 0), head + Vector2(2, 2.2), head + Vector2(-2, 2.2)]), Color("2f3540"))
	c.ellipse(head + Vector2(0, 2.4), Vector2(1.9, 0.7), Color("fff0b8"))
	_glow(c, head + Vector2(0, 4), Vector2(7, 5), Color(1.0, 0.92, 0.6, 0.35))
	return Color(0.12, 0.13, 0.16, 0.85)


func _traffic_light(c: Canvas) -> Color:
	_shadow(c, PROP_BASE + Vector2(1, 0), Vector2(5, 2))
	_iso_box(c, PROP_BASE, 1.8, 1.8, 2.0, Color("4a505b"))
	_pole(c, PROP_BASE.x, 18.0, PROP_BASE.y - 1.0, 0.85, Color("5d6470"))
	# Caja con esquinas redondeadas (columna de luces).
	var box := Rect2(PROP_BASE.x - 4, 2.5, 8, 19)
	c.each(box, func(p: Vector2) -> Color:
		var q := (p - box.get_center()).abs() - box.size * 0.5 + Vector2(1.2, 1.2)
		if q.max(Vector2.ZERO).length() > 1.2:
			return CLEAR
		var nx := (p.x - box.get_center().x) / (box.size.x * 0.5)
		return _lit(Color("2b2f36"), -nx * 0.35))
	var colors := [Color("e5483d").darkened(0.45), Color("f2c14e").darkened(0.45), Color("54d77a")]
	for i in 3:
		var at := Vector2(PROP_BASE.x, 6.5 + i * 6.0)
		c.ellipse(at + Vector2(0, -0.3), Vector2(2.4, 2.4), Color("15171b"))  # visera
		c.ellipse(at, Vector2(2.0, 2.0), colors[i])
		c.ellipse(at + Vector2(-0.6, -0.6), Vector2(0.6, 0.5), Color(1, 1, 1, 0.5))
	_glow(c, Vector2(PROP_BASE.x, 18.5), Vector2(6, 6), Color(0.4, 1.0, 0.55, 0.35))
	return Color(0.06, 0.07, 0.08, 0.85)


func _bus_stop(c: Canvas) -> Color:
	var base := PROP_BASE + Vector2(-2, 0)
	_shadow(c, base + Vector2(1, 0.5), Vector2(19, 6.5))
	var frame := Color("4a5260")
	for px: float in [-11.0, 11.0]:  # postes
		_pole(c, base.x + px, base.y - 29.0, base.y - 0.5, 0.7, frame)
	# Panel trasero de vidrio con reflejo.
	var glass := Rect2(base + Vector2(-11, -26), Vector2(22, 20))
	c.each(glass, func(p: Vector2) -> Color:
		var col := Color(0.62, 0.78, 0.9, 0.5)
		if posmod(p.x - p.y * 0.8, 9.0) < 1.6:
			col = Color(0.9, 0.96, 1.0, 0.6)
		return col)
	c.line(glass.position + Vector2(0, glass.size.y), glass.end, 0.3, frame)
	_iso_box(c, base + Vector2(0, -2), 9.0, 1.6, 1.4, Color("9aa3ad"), 5.0)  # banca
	_iso_box(c, base + Vector2(0, -1), 13.5, 5.0, 2.0, Color("3f6fb5"), 27.0)  # techo
	_pole(c, base.x + 17.5, base.y - 30.0, base.y + 2.0, 0.5, Color("8a929c"))  # señal
	var sign_rect := Rect2(base + Vector2(13, -37), Vector2(9, 7))
	c.each(sign_rect, func(p: Vector2) -> Color:
		return _lit(Color("2f6fd6"), 0.2 - (p.y - sign_rect.position.y) / sign_rect.size.y * 0.4))
	# Bus (icono blanco)
	var bus := Rect2(sign_rect.position + Vector2(2, 1.6), Vector2(5, 3))
	c.poly(PackedVector2Array([bus.position, bus.position + Vector2(bus.size.x, 0), bus.end, bus.position + Vector2(0, bus.size.y)]), Color.WHITE)
	c.line(bus.position + Vector2(0.6, 1.0), bus.position + Vector2(4.4, 1.0), 0.35, Color("2f6fd6"))
	c.ellipse(bus.position + Vector2(1.2, 3.1), Vector2(0.5, 0.5), Color.WHITE)
	c.ellipse(bus.position + Vector2(3.8, 3.1), Vector2(0.5, 0.5), Color.WHITE)
	return Color(0.1, 0.12, 0.16, 0.85)


func _fountain(c: Canvas) -> Color:
	var center := PROP_BASE + Vector2(0, -3)
	_shadow(c, center + Vector2(1, 4), Vector2(21, 8))
	var stone := Color("b7b1a5")
	var r := Vector2(19, 9.5)
	# Pared del estanque (cilindro bajo) y borde de arriba.
	_cylinder(c, center + Vector2(0, 1), r, 5.0, stone)
	c.ring(center + Vector2(0, -4), r - Vector2(1, 0.5), 1.6, stone.lightened(0.15))
	# Agua con ondas concéntricas.
	var water_r := r - Vector2(2.6, 1.4)
	c.each(Rect2(center + Vector2(0, -4) - water_r, water_r * 2.0), func(p: Vector2) -> Color:
		var q := (p - (center + Vector2(0, -4))) / water_r
		var d := q.length()
		if d > 1.0:
			return CLEAR
		var col := Color("3f7fcc").lerp(Color("5f9be0"), 0.5 - q.y * 0.5)
		col = col.lerp(Color("bfe0fa"), _sstep(0.82, 1.0, sin(d * 22.0)) * 0.5)
		return col.darkened(_sstep(0.85, 1.0, d) * 0.25))
	# Columna central y taza.
	_pole(c, center.x, center.y - 18.0, center.y - 4.0, 1.6, stone.darkened(0.05))
	_cylinder(c, center + Vector2(0, -14), Vector2(4.5, 2.0), 1.2, stone)
	# Chorros: arcos de agua y gotas.
	for side: float in [-1.0, 1.0]:
		var pts := PackedVector2Array()
		for i in 9:
			var t := i / 8.0
			pts.append(center + Vector2(side * t * 9.0, -19.0 + t * t * 14.0 - sin(t * PI) * 3.0))
		c.polyline(pts, 0.4, Color(0.86, 0.94, 1.0, 0.8))
	c.ellipse(center + Vector2(0, -19.5), Vector2(1.0, 1.4), Color(0.9, 0.96, 1.0, 0.9))
	return Color(0.2, 0.19, 0.17, 0.85)


func _statue(c: Canvas) -> Color:
	var base := PROP_BASE
	_shadow(c, base + Vector2(1.5, 0.5), Vector2(13, 4.5))
	_iso_box(c, base, 6.5, 6.5, 10.0, Color("aaa498"))
	_iso_box(c, base + Vector2(0, -10), 5.5, 5.5, 2.0, Color("bdb7aa"))  # cornisa
	var bronze := Color("7a6847")
	var feet := base + Vector2(0, -13)
	# Figura de pie, mano levantada (luz de esfera común para que se vea redonda).
	var lc := feet + Vector2(0, -9)
	_blob(c, feet + Vector2(-1.4, -3), Vector2(1.3, 3.4), bronze, lc, 9.0, 0.5)  # piernas
	_blob(c, feet + Vector2(1.4, -3), Vector2(1.3, 3.4), bronze, lc, 9.0, 0.5)
	_blob(c, feet + Vector2(0, -9), Vector2(3.2, 4.2), bronze, lc, 9.0, 0.5)  # torso
	c.line(feet + Vector2(-2.6, -11), feet + Vector2(-3.4, -6), 0.9, bronze.darkened(0.2))  # brazo
	c.line(feet + Vector2(2.6, -11.5), feet + Vector2(4.5, -16.5), 0.9, bronze.darkened(0.05))  # brazo en alto
	_blob(c, feet + Vector2(0, -15.2), Vector2(2.2, 2.3), bronze, feet + Vector2(0, -15.2), 2.3, 0.0)  # cabeza
	return Color(0.12, 0.11, 0.08, 0.85)


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
				var relative := "buildings/%s_%s_%s.png" % [style, part, names[variant]]
				if not _wanted(relative):
					continue
				var c := Canvas.new(WorldTiles.BUILDING_FACADE_SIZE, S)
				var rng := RandomNumberGenerator.new()
				rng.seed = hash(style + part) + variant * 7919
				var painter: Callable = Callable(self, "_facade_" + style).bind(part == "ground", variant, rng)
				_facade(c, painter, part == "ground")
				_write(relative, c.finish())


## Pinta las dos paredes visibles de un piso. painter(face, s, t) -> Color:
## face 0 = pared izquierda (iluminada), 1 = derecha (en sombra); s = 0..32 a lo
## largo de la pared; t = 0..FLOOR_PX desde arriba (px lógicos, con decimales).
## Así las ventanas quedan inclinadas con la pared. La planta baja oscurece su
## zócalo; abajo de cada piso hay un poco de oclusión.
func _facade(c: Canvas, painter: Callable, ground_floor: bool) -> void:
	var size := WorldTiles.BUILDING_FACADE_SIZE
	c.each(Rect2(Vector2.ZERO, size), func(p: Vector2) -> Color:
		var face := 0 if p.x < FACE_W else 1
		var s := p.x if face == 0 else p.x - FACE_W
		var top := p.x * 0.5 if face == 0 else (size.x - p.x) * 0.5
		var t := p.y - top
		if t < 0.0 or t >= FLOOR_PX:
			return CLEAR
		var col: Color = painter.call(face, s, t)
		if col.a <= 0.0:
			return CLEAR
		if ground_floor and t >= FLOOR_PX - 1.6:
			col = col.darkened(0.35)  # zócalo
		col = col.darkened(_sstep(FLOOR_PX - 5.0, FLOOR_PX, t) * 0.06)
		if face == 1:
			col = col.darkened(0.26).lerp(Color("2a3150"), 0.06)
		elif s > FACE_W - 0.5:
			col = col.lightened(0.12)  # arista de la esquina
		return col)


## Ventana: marco, vidrio con degradé y reflejo (o luz cálida) y alféizar.
## null si (s, t) no cae en ella.
func _window(s: float, t: float, s0: float, t0: float, w: float, h: float, frame: Color, lit := false, mullion := true) -> Variant:
	if s < s0 or s >= s0 + w or t < t0 or t >= t0 + h + 0.8:
		return null
	if t >= t0 + h:
		return frame.darkened(0.08 + (t - t0 - h) * 0.2)  # alféizar
	var fw := 0.6
	if s < s0 + fw or s >= s0 + w - fw or t < t0 + fw or t >= t0 + h - fw or absf(t - (t0 + h * 0.42)) < fw * 0.5 \
			or (mullion and absf(s - (s0 + w * 0.5)) < fw * 0.4):
		return frame if s >= s0 + fw * 0.5 else frame.darkened(0.15)
	var g := (t - t0) / h
	if lit:
		return Color("f6dc96").lerp(Color("e3b866"), g)
	var glass := Color("98bde0").lerp(Color("4a6e96"), g)
	if posmod(s - t * 0.9, 10.0) < 1.8:
		glass = glass.lightened(0.28)  # reflejo
	if t < t0 + fw + 1.0:
		glass = glass.darkened(0.2)  # sombra del dintel
	return glass


func _door(s: float, t: float, s0: float, w: float, wood: Color) -> Variant:
	if s < s0 or s >= s0 + w or t < 6.0:
		return null
	if s < s0 + 0.7 or s >= s0 + w - 0.7 or t < 6.7:
		return wood.darkened(0.35)
	if absf(s - (s0 + w - 2.4)) < 0.5 and absf(t - 15.5) < 0.5:
		return Color("e8c860")  # manija
	var panel := posmod(s - s0, w * 0.5) < 0.5 or absf(t - 15.0) < 0.3
	return _shade(wood, -0.12 if panel else sin(s * 4.0) * 0.03)


## Casas (techo de teja): pañete claro, ventanas con postigos, puerta de madera.
func _facade_building(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var wall := _shade(Color("ecdcbc"), _grain(Vector2(s, t), face) * 0.035)
	if t <= 1.5:
		wall = Color("cdb994").darkened(0.15 * (1.0 - t / 1.5))  # cornisa
	if ground_floor and variant == 1 and face == 0:
		var d: Variant = _door(s, t, 11.0, 10.0, Color("7a5234"))
		if d != null:
			return d
	var shutter := Color("4f7a5a") if variant != 2 else Color("8a5a3a")
	for x0: float in [7.6, 21.8]:
		if s >= x0 and s < x0 + 2.4 and t >= 7.0 and t < 20.0:
			return _shade(shutter, -0.12 if posmod(t, 1.2) < 0.4 else 0.04)
	var win: Variant = _window(s, t, 10.0, 7.0, 12.0, 13.0, Color("f4efe4"), not ground_floor and variant == 2)
	if win != null:
		return win
	if not ground_floor and variant == 1 and t >= 20.5 and t < 23.0 and s >= 9.0 and s < 23.0:
		# Matera con flores.
		if t < 21.6:
			return Color("e86a8a") if posmod(s * 1.7, 2.0) < 0.9 else Color("4e8f3c")
		return Color("b45f3c").darkened((t - 21.6) * 0.2)
	if t > 1.5 and t < 2.4:
		return wall.darkened(0.12)  # sombra de la cornisa
	return wall


## Ladrillo a la vista (lo más común en Bogotá).
func _facade_roof_brick(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var row := floori(t / 2.2)
	var off := 2.8 * (row % 2)
	var brick := floori((s + off) / 5.6)
	var wall := Color("b65a3c").lerp(Color("9e4a33"), float(WorldTiles.cell_hash(brick, row, 5 + face) % 100) / 160.0)
	var ft := posmod(t, 2.2)
	var fs := posmod(s + off, 5.6)
	if ft > 1.85 or fs < 0.35:
		wall = Color("c9a58c")  # mortero
	else:
		wall = _shade(wall, 0.06 * (1.0 - ft / 1.85) + _grain(Vector2(s, t), face) * 0.04)
	if t <= 1.6:
		wall = Color("d6c3ae").darkened(0.12 * (1.0 - t / 1.6))  # remate de concreto
	if ground_floor:
		if variant == 1 and face == 0:
			var d: Variant = _door(s, t, 10.0, 11.0, Color("5d4030"))
			if d != null:
				return d
		if variant == 2 and s >= 3.0 and s < 29.0 and t >= 5.0:
			# Local con persiana metálica.
			if s < 3.8 or s >= 28.2 or t < 5.8:
				return Color("6f747a")
			return _shade(Color("a7adb3"), -0.1 if posmod(t, 1.3) < 0.35 else 0.03)
	var win: Variant = _window(s, t, 9.0, 6.0, 14.0, 14.0, Color("ece7dc"), not ground_floor and variant == 2)
	if win != null:
		return win
	if not ground_floor and variant == 1 and t >= 18.0 and t < 23.5 and s >= 6.0 and s < 26.0:
		# Balcón con baranda.
		if t < 18.6 or s < 6.6 or s >= 25.4 or posmod(s, 2.2) < 0.45:
			return Color("3a3a3e")
		return CLEAR
	return wall


## Concreto claro, ventanas corridas (oficinas y apartamentos).
func _facade_roof_concrete(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var wall := _shade(Color("cfccc4"), _grain(Vector2(s, t), face) * 0.03)
	if t <= 2.5:
		wall = Color("aeaaa1").lightened(0.1 * (1.0 - t / 2.5))  # placa
	if ground_floor:
		var awning: Color = [Color("d9534f"), Color("2f7fc1"), Color("3c9a5f")][variant % 3]
		if variant >= 1 and t >= 3.5 and t < 6.5 and s >= 2.0 and s < 30.0:
			return _shade(awning if posmod(s, 4.0) < 2.0 else awning.lightened(0.35), -(t - 3.5) * 0.06)  # toldo
		if s >= 3.0 and s < 29.0 and t >= 7.0:
			# Vitrina de local (o portería).
			if s < 3.8 or s >= 28.2 or t < 7.8 or absf(s - 16.0) < 0.4:
				return Color("55595f")
			var g := Color("a2c4de").lerp(Color("5f84a8"), (t - 7.0) / 19.0)
			return g.lightened(0.25) if posmod(s - t, 11.0) < 2.0 else g
		return wall
	var win: Variant = _window(s, t, 3.0, 7.0, 26.0, 12.0, Color("8a8d92"), variant == 2, false)
	if win != null:
		return win
	if variant == 1 and t >= 7.0 and t < 19.0 and (absf(s - 12.0) < 0.5 or absf(s - 20.0) < 0.5):
		return Color("8a8d92")
	return wall


## Muro cortina de vidrio (edificios altos).
func _facade_roof_dark(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	if t <= 3.0:
		return Color("3a404c").lightened(0.1 * (1.0 - t / 3.0))  # franja de losa
	if posmod(s, 8.0) < 0.7:
		return Color("2f3540")  # parteluz
	if ground_floor and variant == 1 and face == 0 and s >= 9.0 and s < 23.0 and t >= 8.0:
		if s < 9.7 or s >= 22.3 or absf(s - 16.0) < 0.35:
			return Color("2f3540")
		return Color("e1ecf6").lerp(Color("c4d6e6"), (t - 8.0) / 18.0)  # entrada iluminada
	var lit := not ground_floor and variant == 1 and int(s / 8.0) % 2 == 1
	if lit:
		return Color("f3da94").lerp(Color("e2b968"), (t - 3.0) / 23.0)
	var g := (t - 3.0) / 23.0
	var base := Color("6a8aab").lerp(Color("435f80"), g)
	if ground_floor:
		base = base.darkened(0.15)
	# Reflejo del cielo en diagonal.
	var reflect := _sstep(0.0, 1.5, posmod(s - t * 2.0, 23.0)) * (1.0 - _sstep(3.0, 5.0, posmod(s - t * 2.0, 23.0)))
	return base.lerp(Color("c9def0"), reflect * 0.45)


## Edificios públicos: piedra clara, pilastras y ventanas en arco.
func _facade_roof_civic(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var wall := _shade(Color("e6d9bb"), _grain(Vector2(s, t), face) * 0.025)
	var block_row := floori(t / 6.0)
	if posmod(t, 6.0) > 5.5 or (posmod(s + 4.0 * (block_row % 2), 8.0) < 0.45):
		wall = Color("cdbf9f")  # juntas de los bloques
	if s <= 2.0 or s >= 30.0:
		wall = Color("f2e8cf").darkened(0.06 if s >= 30.0 else 0.0)  # pilastras
	if t <= 1.6:
		wall = Color("cdbf9f").lightened(0.1 * (1.0 - t / 1.6))
	# Arco: rectángulo con remate semicircular.
	var s0 := 11.0
	var w := 10.0
	var top := 5.0 if ground_floor and variant == 0 else 7.0
	var cx := s0 + w * 0.5
	var bottom := FLOOR_PX - (1.0 if ground_floor else 4.0)
	var arch_d := Vector2(s - cx, (t - (top + 5.0)) * 1.1).length()
	var in_rect := s >= s0 and s < s0 + w and t >= top + 5.0 and t < bottom
	var in_arch := t >= top and t < top + 5.0 and arch_d <= w * 0.5
	if in_rect or in_arch:
		var edge := s < s0 + 0.8 or s >= s0 + w - 0.8 or (in_arch and arch_d > w * 0.5 - 0.8)
		if edge:
			return Color("b8a882")
		if ground_floor and variant == 0:
			return _shade(Color("6b4a32"), -0.1 if posmod(s - s0, 3.3) < 0.4 else sin(t * 3.0) * 0.03)  # portón
		var g := Color("9cbedd").lerp(Color("55789f"), (t - top) / (bottom - top))
		return g.lightened(0.25) if posmod(s - t, 9.0) < 1.4 else g
	if not in_rect and absf(t - (bottom + 0.4)) < 0.4 and s >= s0 - 0.6 and s < s0 + w + 0.6:
		return Color("cdbf9f")  # repisa
	return wall


## Bodegas: lámina ondulada (como su techo), portón enrollable en la planta baja.
func _facade_roof_industrial(face: int, s: float, t: float, ground_floor: bool, variant: int, _rng: RandomNumberGenerator) -> Color:
	var wall := _shade(Color("8996a3"), sin(s * TAU / 4.0) * 0.1 + _grain(Vector2(s, t), face) * 0.02)
	if ground_floor and variant == 0 and face == 0 and s >= 4.0 and s < 28.0 and t >= 5.0:
		if s < 4.8 or s >= 27.2 or t < 5.8:
			return Color("5e6872")
		return _shade(Color("c2c6ca"), -0.12 if posmod(t, 1.4) < 0.3 else 0.02)
	if not ground_floor and variant == 1 and t >= 4.0 and t < 9.0 and s >= 4.0 and s < 28.0:
		if t < 4.6 or t >= 8.4 or posmod(s - 4.0, 6.0) < 0.5:
			return Color("5e6872")
		return Color("a8c8e2").lerp(Color("6f93b5"), (t - 4.0) / 5.0)
	return wall


# =============================================================================
# Iconos de categoría de los puntos de interés (assets/art/ui/poi/<cat>.png)
# 7x7 lógicos -> 28x28, blancos (el juego los tiñe). Se amplían con Scale2x
# dos veces: las diagonales quedan redondeadas, no en escalera.
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
		var relative := "ui/poi/%s.png" % cat
		if not _wanted(relative):
			continue
		var rows: Array = POI_ICONS[cat]
		var img := Image.create_empty(7, 7, false, Image.FORMAT_RGBA8)
		for y in rows.size():
			var row: String = rows[y]
			for x in row.length():
				if row[x] == "X":
					img.set_pixel(x, y, Color.WHITE)
		_write(relative, scale4x(img))


## Amplía pixel art x4 (Scale2x dos veces): mantiene los bordes nítidos y
## suaviza las diagonales. Sirve también para los iconos de la interfaz.
static func scale4x(img: Image) -> Image:
	return _scale2x(_scale2x(img))


static func _scale2x(src: Image) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create_empty(w * 2, h * 2, false, Image.FORMAT_RGBA8)
	var at := func(x: int, y: int) -> Color:
		return src.get_pixel(clampi(x, 0, w - 1), clampi(y, 0, h - 1))
	for y in h:
		for x in w:
			var p: Color = at.call(x, y)
			var a: Color = at.call(x, y - 1)
			var b: Color = at.call(x + 1, y)
			var c: Color = at.call(x - 1, y)
			var d: Color = at.call(x, y + 1)
			out.set_pixel(x * 2, y * 2, a if c == a and c != d and a != b else p)
			out.set_pixel(x * 2 + 1, y * 2, b if a == b and a != c and b != d else p)
			out.set_pixel(x * 2, y * 2 + 1, c if d == c and d != b and c != a else p)
			out.set_pixel(x * 2 + 1, y * 2 + 1, d if b == d and b != a and d != c else p)
	return out


## Contorno de 1 px alrededor de lo opaco (pixel art de los personajes).
func _pixel_outline(img: Image, color: Color) -> void:
	var marks: Array[Vector2i] = []
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a >= 0.6:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, y) + d
				if n.x >= 0 and n.y >= 0 and n.x < img.get_width() and n.y < img.get_height() and img.get_pixel(n.x, n.y).a >= 0.6:
					marks.append(Vector2i(x, y))
					break
	for p in marks:
		img.set_pixel(p.x, p.y, color)


# =============================================================================
# Jugador: hoja de sprites 8 direcciones x (1 quieto + 4 caminando), pixel art a x1
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
			_pixel_outline(frame, CHAR_OUTLINE)
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
