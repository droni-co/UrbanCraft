extends SceneTree
## Genera pixel art placeholder para el mundo isométrico:
##   assets/tiles/ground.png  — tiles de suelo 64x32 (orden de WorldTiles.Ground)
##   assets/tiles/props.png   — props 64x64 (orden de WorldTiles.Prop)
## Uso:  pnpm game:assets   (reemplaza estos PNG por arte final cuando lo tengas)

const W := 64
const H := 32
const PROP_H := 64
const OUT_DIR := "res://assets/tiles"

const GROUND_COLORS := {
	WorldTiles.Ground.GRASS: Color("6aa84f"),
	WorldTiles.Ground.GRASS_DARK: Color("3f7d3a"),
	WorldTiles.Ground.DIRT: Color("a0764a"),
	WorldTiles.Ground.SAND: Color("e2cc8b"),
	WorldTiles.Ground.WATER: Color("3b7dd8"),
	WorldTiles.Ground.STONE: Color("9a9aa2"),
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_save(_ground_atlas(), OUT_DIR + "/ground.png")
	_save(_props_atlas(), OUT_DIR + "/props.png")
	quit()


func _save(img: Image, path: String) -> void:
	var err := img.save_png(ProjectSettings.globalize_path(path))
	print("%s: %s" % [path, error_string(err)])


# --- Suelo --------------------------------------------------------------------

func _ground_atlas() -> Image:
	var count := WorldTiles.Ground.size()
	var img := Image.create_empty(W * count, H, false, Image.FORMAT_RGBA8)
	for kind in count:
		_ground_tile(img, kind * W, kind)
	return img


## Medio ancho de la fila y del rombo 2:1 (bordes escalonados limpios que encajan).
func _half_width(y: int) -> int:
	return (y + 1) * 2 if y < H / 2 else (H - y) * 2


func _ground_tile(img: Image, ox: int, kind: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + kind
	var base: Color = GROUND_COLORS[kind]
	for y in H:
		var hw := _half_width(y)
		for x in range(W / 2 - hw, W / 2 + hw):
			var c := _ground_pixel(kind, base, x, y, rng.randf())
			var edge := x - (W / 2 - hw) < 2 or (W / 2 + hw - 1) - x < 2
			if edge:
				c = c.lightened(0.08) if y < H / 2 else c.darkened(0.12)
			img.set_pixel(ox + x, y, c)


func _ground_pixel(kind: int, base: Color, x: int, y: int, n: float) -> Color:
	match kind:
		WorldTiles.Ground.GRASS, WorldTiles.Ground.GRASS_DARK:
			if n < 0.10:
				return base.darkened(0.15)
			if n > 0.94:
				return base.lightened(0.15)
		WorldTiles.Ground.DIRT:
			if n < 0.08:
				return base.darkened(0.22)
			if n > 0.95:
				return base.lightened(0.18)
		WorldTiles.Ground.SAND:
			if n < 0.07:
				return base.darkened(0.1)
		WorldTiles.Ground.WATER:
			if posmod(x / 2 + y, 8) == 0 and n < 0.6:
				return base.lightened(0.22)
			if n < 0.05:
				return base.darkened(0.08)
		WorldTiles.Ground.STONE:
			if posmod(x / 2 + y, 8) == 0 or posmod(x / 2 - y, 8) == 0:
				return base.darkened(0.25)
			if n < 0.1:
				return base.darkened(0.06)
	return base


# --- Props --------------------------------------------------------------------

func _props_atlas() -> Image:
	var count := WorldTiles.Prop.size()
	var img := Image.create_empty(W * count, PROP_H, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for kind in count:
		var ox := kind * W
		# La base del prop (centro del rombo) queda en (32, 48) dentro de su celda 64x64.
		match kind:
			WorldTiles.Prop.TREE:
				_shadow(img, ox + 32, 48, 14, 5)
				_rect(img, ox + 30, 30, 5, 18, Color("6b4a2b"))
				_blob(img, ox + 32, 22, 17, 16, Color("4f9a3a"), rng)
			WorldTiles.Prop.PINE:
				_shadow(img, ox + 32, 48, 11, 4)
				_rect(img, ox + 30, 38, 4, 10, Color("5a3d22"))
				for tier in 3:
					_triangle(img, ox + 32, 6 + tier * 10, 14, 7 + tier * 4, Color("2f6b3f"), rng)
			WorldTiles.Prop.ROCK:
				_shadow(img, ox + 32, 48, 14, 5)
				_blob(img, ox + 32, 42, 13, 9, Color("8d8d95"), rng)
			WorldTiles.Prop.BUSH:
				_shadow(img, ox + 32, 48, 15, 5)
				_blob(img, ox + 25, 42, 8, 7, Color("4c8f3a"), rng)
				_blob(img, ox + 39, 42, 8, 7, Color("4c8f3a"), rng)
				_blob(img, ox + 32, 37, 9, 8, Color("5aa244"), rng)
	return img


func _plot(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_plot(img, x, y, c.darkened(0.25) if x >= x0 + w - 2 else c)


func _shadow(img: Image, cx: int, cy: int, rx: int, ry: int) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var nx := (x - cx) / float(rx)
			var ny := (y - cy) / float(ry)
			if nx * nx + ny * ny <= 1.0:
				_plot(img, x, y, Color(0, 0, 0, 0.3))


## Elipse rellena con luz desde arriba-izquierda y contorno oscuro.
func _blob(img: Image, cx: int, cy: int, rx: int, ry: int, base: Color, rng: RandomNumberGenerator) -> void:
	for y in range(cy - ry, cy + ry + 1):
		for x in range(cx - rx, cx + rx + 1):
			var nx := (x - cx) / float(rx)
			var ny := (y - cy) / float(ry)
			var d := nx * nx + ny * ny
			if d > 1.0:
				continue
			var light := -(nx + ny) * 0.5
			var c := base.lightened(light * 0.4) if light > 0.0 else base.darkened(-light * 0.4)
			if d > 0.82:
				c = c.darkened(0.3)
			elif rng.randf() < 0.08:
				c = c.darkened(0.12)
			_plot(img, x, y, c)


## Triángulo (copa de pino) con vértice en (cx, top).
func _triangle(img: Image, cx: int, top: int, height: int, half_base: int, base: Color, rng: RandomNumberGenerator) -> void:
	for dy in height:
		var hw := int(round(half_base * float(dy + 1) / height))
		for dx in range(-hw, hw + 1):
			var c := base.lightened(0.15) if dx < 0 else base.darkened(0.15)
			if absi(dx) >= hw - 1 or dy == height - 1:
				c = c.darkened(0.3)
			elif rng.randf() < 0.08:
				c = c.lightened(0.1)
			_plot(img, cx + dx, top + dy, c)
