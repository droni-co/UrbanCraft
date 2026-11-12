class_name MapLabels
extends Node2D
## Etiquetas del mapa real, discretas, para orientarse:
##
##   - Nombres de calles y ríos "pintados" sobre el suelo, siguiendo la
##     dirección de la calle en perspectiva isométrica. Se dibujan en este nodo,
##     entre el suelo y las entidades (los personajes pasan por encima).
##   - Nombres de parques, plazas, edificios y POIs, y números de portal, en una
##     capa superior siempre legible (texto recto, tamaño fijo en pantalla).
##
## Todas se desvanecen con la distancia al jugador y solo aparecen las cercanas,
## así el mapa no se llena de texto. Los datos vienen de cada chunk (campo
## "labels" del backend, ver apps/backend/app/map/labels.ts).
##
## Calles: el backend manda su trazado recortado a cada chunk. Aquí se unen los
## trozos de todos los chunks en tramos rectos y el nombre se repite en puntos
## FIJOS a lo largo de cada tramo (no persigue al jugador), como en un mapa.
##
## Coordenadas: "grilla" = celdas locales con decimales (centro de celda = n + 0.5).

const LINE_KINDS := ["street", "path", "waterway"]
const AREA_KINDS := ["park", "water", "square", "place", "building", "district"]

## Distancia máxima (celdas) a la que se ve cada tipo de etiqueta.
const STREET_RADIUS := 22.0
const AREA_RADIUS := {"park": 40.0, "water": 40.0, "square": 30.0, "place": 22.0, "building": 16.0, "district": 80.0}
const POI_RADIUS := 13.0
const NUMBER_RADIUS := 7.0
## Distancia máxima a una calle para considerar que el jugador está en ella.
const ON_STREET_DISTANCE := 4.0
const NEAR_STREET_DISTANCE := 14.0

## Tramos: desvío máximo para seguir considerándolo recto, y separación mínima
## (celdas) entre dos repeticiones del mismo nombre.
const STRAIGHT_TOLERANCE := deg_to_rad(12.0)
const REPEAT_GAP := 12.0
## Un nombre que no cabe en su tramo se achica hasta este factor; si no, se omite.
const MIN_FIT := 0.7

## Tamaño de fuente de dibujo (las calles se escalan desde aquí).
const FONT_SIZE := 16
## Alto de las letras de calle en celdas, según la importancia de la vía.
const STREET_TEXT_CELLS := {9: 0.85, 8: 0.8, 7: 0.75, 6: 0.7, 5: 0.65, 4: 0.55, 3: 0.5, 2: 0.45}

const STREET_COLOR := Color(1, 1, 1, 0.24)
const PATH_COLOR := Color(0.12, 0.12, 0.16, 0.26)
const WATERWAY_COLOR := Color(0.85, 0.94, 1.0, 0.35)

## Estilo de la capa superior: tamaño en píxeles de pantalla (resolución base) y color.
const BILLBOARD_STYLE := {
	"district": {"size": 11, "color": Color(1.0, 0.93, 0.78, 0.72)},
	"park": {"size": 8, "color": Color(0.8, 1.0, 0.78, 0.8)},
	"water": {"size": 8, "color": Color(0.78, 0.9, 1.0, 0.8)},
	"square": {"size": 8, "color": Color(1, 0.97, 0.9, 0.8)},
	"place": {"size": 7, "color": Color(1, 1, 1, 0.78)},
	"building": {"size": 7, "color": Color(1, 0.95, 0.9, 0.7)},
	"poi": {"size": 7, "color": Color(0.8, 0.88, 1.0, 0.8)},
	"number": {"size": 6, "color": Color(1, 1, 1, 0.62)},
}
const OUTLINE_COLOR := Color(0, 0, 0, 0.5)
## Altura (px de mundo) del texto de un POI: justo sobre su marcador.
const POI_TEXT_OFFSET := 32.0
const MAX_BILLBOARDS := 28

## Capa donde se dibuja el suelo: define la proyección grilla -> mundo.
var ground: TileMapLayer

var _chunks := {}  # chunk -> {lines, areas, pois, numbers}
## Puntos fijos donde va el nombre de cada calle (se recalcula al cambiar chunks).
var _street_spots: Array[Dictionary] = []
var _spots_dirty := false
var _focus := Vector2.ZERO
var _font: Font
var _overlay: Node2D
var _view_scale := 1.0


func _ready() -> void:
	_font = _make_font()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay = Node2D.new()
	_overlay.name = "Overlay"
	_overlay.z_index = 10  # sobre las entidades (árboles, personajes)
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	GameSettings.labels_settings_changed.connect(_redraw)


func _process(_delta: float) -> void:
	# El texto superior mantiene su tamaño en pantalla aunque la cámara haga zoom.
	var scale_now := get_viewport().get_canvas_transform().get_scale().x
	if not is_equal_approx(scale_now, _view_scale):
		_view_scale = scale_now
		_overlay.queue_redraw()


# --- API --------------------------------------------------------------------------

## Agrega las etiquetas de un chunk. `base` es su esquina en celdas locales.
func add_chunk(chunk: Vector2i, base: Vector2i, labels: Array, pois: Array) -> void:
	var entry := {"lines": [], "areas": [], "pois": [], "numbers": []}
	var offset := Vector2(base)
	for label: Dictionary in labels:
		var kind := str(label.get("kind", ""))
		var item := {
			"kind": kind,
			"name": str(label.get("name", "")),
			"rank": int(label.get("rank", 1)),
			"at": offset + Vector2(float(label.at[0]), float(label.at[1])),
		}
		if kind in LINE_KINDS:
			var paths: Array[PackedVector2Array] = []
			for flat: Array in label.get("paths", []):
				var points := PackedVector2Array()
				for i in range(0, flat.size() - 1, 2):
					points.append(offset + Vector2(float(flat[i]), float(flat[i + 1])))
				if points.size() >= 2:
					paths.append(points)
			item.paths = paths
			entry.lines.append(item)
		elif kind == "number":
			entry.numbers.append(item)
		elif kind in AREA_KINDS:
			entry.areas.append(item)
	for poi: Dictionary in pois:
		var cell := offset + Vector2(float(poi.cell[0]) + 0.5, float(poi.cell[1]) + 0.5)
		entry.pois.append({"kind": "poi", "name": str(poi.get("name", "")), "rank": 3, "at": cell})
	_chunks[chunk] = entry
	_spots_dirty = true
	_redraw()


func remove_chunk(chunk: Vector2i) -> void:
	if _chunks.erase(chunk):
		_spots_dirty = true
		_redraw()


func clear() -> void:
	_chunks.clear()
	_spots_dirty = true
	_redraw()


## Posición del jugador en la grilla. Redibuja solo si se movió lo suficiente.
func set_focus(grid_position: Vector2) -> void:
	if grid_position.distance_squared_to(_focus) < 0.04:
		return
	_focus = grid_position
	_redraw()


## Dónde está el jugador: la calle que pisa, el lugar con nombre junto a él
## (monumento, parque, plaza...) o, si no, "Cerca de <calle más próxima>".
func location_name(grid_position: Vector2) -> String:
	var street := _nearest_street(grid_position)
	if street.distance <= ON_STREET_DISTANCE:
		return street.name

	var best := ""
	var best_distance := INF
	for entry: Dictionary in _chunks.values():
		for item: Dictionary in entry.areas + entry.pois:
			if item.kind == "district":
				continue  # el barrio va aparte (lo manda el backend por chunk)
			var reach: float = 24.0 if item.kind in ["park", "square", "water"] else 8.0
			var d := grid_position.distance_to(item.at)
			if d < reach and d < best_distance:
				best_distance = d
				best = item.name
	if not best.is_empty():
		return best
	if street.distance <= NEAR_STREET_DISTANCE:
		return "Cerca de %s" % street.name
	return ""


func _nearest_street(grid_position: Vector2) -> Dictionary:
	var best := {"name": "", "distance": INF}
	for entry: Dictionary in _chunks.values():
		for item: Dictionary in entry.lines:
			if item.kind == "waterway":
				continue
			for path: PackedVector2Array in item.paths:
				for i in path.size() - 1:
					var closest := Geometry2D.get_closest_point_to_segment(grid_position, path[i], path[i + 1])
					var d := grid_position.distance_to(closest)
					if d < best.distance:
						best = {"name": item.name, "distance": d}
	return best


# --- Tramos y puntos de las calles -------------------------------------------------

## Une los trozos de cada calle (de todos los chunks) en tramos rectos y reparte
## puntos fijos para su nombre.
func _rebuild_street_spots() -> void:
	_spots_dirty = false
	_street_spots.clear()
	var by_name := {}  # "kind|nombre" -> {kind, name, rank, runs: Array}
	for entry: Dictionary in _chunks.values():
		for item: Dictionary in entry.lines:
			var key: String = "%s|%s" % [item.kind, item.name]
			if not by_name.has(key):
				by_name[key] = {"kind": item.kind, "name": item.name, "rank": item.rank, "runs": []}
			var group: Dictionary = by_name[key]
			group.rank = maxi(group.rank, item.rank)
			for path: PackedVector2Array in item.paths:
				group.runs.append_array(_straight_runs(path))

	for group: Dictionary in by_name.values():
		var text_px := _font.get_string_size(group.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var height: float = STREET_TEXT_CELLS.get(clampi(group.rank, 2, 9), 1.0)
		var text_cells := text_px * height / FONT_SIZE
		for run: Dictionary in _join_runs(group.runs):
			var length: float = run.a.distance_to(run.b)
			var fit := minf(1.0, (length + 1.0) / text_cells)
			if fit < MIN_FIT:
				continue  # rotondas y curvas cerradas: sin texto (el HUD muestra el nombre)
			var count := maxi(1, floori((length + REPEAT_GAP) / (text_cells * fit + REPEAT_GAP)))
			for i in count:
				_street_spots.append({
					"kind": group.kind,
					"name": group.name,
					"rank": group.rank,
					"at": run.a.lerp(run.b, (i + 0.5) / count),
					"dir": (run.b - run.a).normalized(),
					"scale": height / FONT_SIZE * fit,
					"text_px": text_px,
					"radius": text_cells * fit / 2.0,
				})
	_street_spots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank > b.rank if a.rank != b.rank else a.radius > b.radius)


## Tramos casi rectos de una polilínea: [{a, b}].
func _straight_runs(path: PackedVector2Array) -> Array[Dictionary]:
	var runs: Array[Dictionary] = []
	var start := 0
	while start < path.size() - 1:
		var base_dir := (path[start + 1] - path[start]).angle()
		var end := start + 1
		while end < path.size() - 1 and absf(angle_difference(base_dir, (path[end + 1] - path[end]).angle())) <= STRAIGHT_TOLERANCE:
			end += 1
		if path[start].distance_to(path[end]) > 0.5:
			runs.append({"a": path[start], "b": path[end]})
		start = end
	return runs


## Une tramos que se continúan (p. ej. una calle cortada en el borde de dos chunks).
func _join_runs(runs: Array) -> Array:
	var pending := runs.duplicate()
	var joined := []
	while not pending.is_empty():
		var run: Dictionary = pending.pop_back()
		var merged := true
		while merged:
			merged = false
			for i in pending.size():
				var other: Dictionary = pending[i]
				var candidate := _try_join(run, other)
				if candidate.is_empty():
					candidate = _try_join(run, {"a": other.b, "b": other.a})
				if not candidate.is_empty():
					run = candidate
					pending.remove_at(i)
					merged = true
					break
		joined.append(run)
	return joined


func _try_join(r1: Dictionary, r2: Dictionary) -> Dictionary:
	var d1: Vector2 = r1.b - r1.a
	var d2: Vector2 = r2.b - r2.a
	if absf(angle_difference(d1.angle(), d2.angle())) > STRAIGHT_TOLERANCE:
		return {}
	if r1.b.distance_to(r2.a) < 0.2:
		return {"a": r1.a, "b": r2.b}
	if r2.b.distance_to(r1.a) < 0.2:
		return {"a": r2.a, "b": r1.b}
	return {}


# --- Dibujo -----------------------------------------------------------------------

func _redraw() -> void:
	queue_redraw()
	if _overlay:
		_overlay.queue_redraw()


## Grilla -> posición local de este nodo (misma proyección que el TileMapLayer).
func _grid_to_world(g: Vector2) -> Vector2:
	return ground.map_to_local(Vector2i.ZERO) + _grid_vector(g - Vector2(0.5, 0.5))


## Vector de la grilla -> vector en pantalla (sin desplazamiento).
func _grid_vector(d: Vector2) -> Vector2:
	var half := Vector2(ground.tile_set.tile_size) / 2.0
	return Vector2((d.x - d.y) * half.x, (d.x + d.y) * half.y)


func _fade(distance: float, radius: float) -> float:
	return 1.0 - smoothstep(radius * 0.55, radius, distance)


## Calles pintadas sobre el suelo.
func _draw() -> void:
	if ground == null or not GameSettings.street_names_visible:
		return
	if _spots_dirty:
		_rebuild_street_spots()
	var opacity := GameSettings.labels_opacity
	var placed: Array[Dictionary] = []

	for spot: Dictionary in _street_spots:
		var distance: float = _focus.distance_to(spot.at)
		if distance >= STREET_RADIUS:
			continue
		# Cruces: si dos nombres se pisarían, gana la calle más importante. El mismo
		# nombre tampoco se repite cerca (avenidas con dos calzadas en OSM).
		var overlaps := placed.any(func(p: Dictionary) -> bool:
			var gap: float = p.at.distance_to(spot.at)
			if p.name == spot.name:
				return gap < (p.radius + spot.radius + REPEAT_GAP) * 0.9
			return gap < (p.radius + spot.radius) * 0.8)
		if overlaps:
			continue
		placed.append(spot)

		var dir: Vector2 = spot.dir
		var along := _grid_vector(dir)
		# Que se lea de izquierda a derecha (o de abajo hacia arriba si es vertical).
		if along.x < -0.01 or (absf(along.x) <= 0.01 and along.y > 0.0):
			dir = -dir
		var perp := Vector2(-dir.y, dir.x)
		var text_scale: float = spot.scale
		var x_axis := _grid_vector(dir) * text_scale
		var y_axis := _grid_vector(perp) * text_scale
		draw_set_transform_matrix(Transform2D(x_axis, y_axis, _grid_to_world(spot.at)))

		var color: Color = WATERWAY_COLOR if spot.kind == "waterway" else (PATH_COLOR if spot.kind == "path" else STREET_COLOR)
		color.a *= opacity * _fade(distance, STREET_RADIUS)
		var baseline := Vector2(-spot.text_px / 2.0, FONT_SIZE * 0.35)
		draw_string(_font, baseline, spot.name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
	draw_set_transform_matrix(Transform2D.IDENTITY)


## Nombres de lugares y números de portal: texto recto, tamaño fijo en pantalla.
func _draw_overlay() -> void:
	if ground == null:
		return
	var candidates: Array[Dictionary] = []
	for entry: Dictionary in _chunks.values():
		if GameSettings.place_names_visible:
			for item: Dictionary in entry.areas:
				_add_candidate(candidates, item, AREA_RADIUS.get(item.kind, 20.0) + (14.0 if item.rank >= 6 else 0.0))
			for item: Dictionary in entry.pois:
				_add_candidate(candidates, item, POI_RADIUS)
		if GameSettings.house_numbers_visible:
			for item: Dictionary in entry.numbers:
				_add_candidate(candidates, item, NUMBER_RADIUS)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.rank > b.rank if a.rank != b.rank else a.distance < b.distance)

	var inv := 1.0 / maxf(_view_scale, 0.01)
	# Zona del jugador: nunca se tapa con texto.
	var player_world := _grid_to_world(_focus)
	var blocked: Array[Rect2] = [Rect2(player_world + Vector2(-10, -34) * inv, Vector2(20, 38) * inv)]
	var shown_names := {}  # nombre -> posición en grilla (evita repetir el mismo lugar)
	var drawn := 0

	for item: Dictionary in candidates:
		if drawn >= MAX_BILLBOARDS:
			break
		if item.kind != "number" and shown_names.has(item.name) and shown_names[item.name].distance_to(item.at) < 30.0:
			continue
		var style: Dictionary = BILLBOARD_STYLE.get(item.kind, BILLBOARD_STYLE.place)
		var font_size: int = style.size
		var text_size := _font.get_string_size(item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		var anchor := _grid_to_world(item.at)
		if item.kind == "poi":
			anchor.y -= POI_TEXT_OFFSET
		var rect := Rect2(anchor - text_size / 2.0 * inv, text_size * inv)
		var grown := rect.grow(2.0 * inv)
		if blocked.any(func(r: Rect2) -> bool: return r.intersects(grown)):
			continue
		blocked.append(grown)
		if item.kind != "number":
			shown_names[item.name] = item.at
		drawn += 1

		var color: Color = style.color
		color.a *= GameSettings.labels_opacity * item.fade
		var outline := OUTLINE_COLOR
		outline.a *= GameSettings.labels_opacity * item.fade
		var baseline := Vector2(-text_size.x / 2.0, _font.get_ascent(font_size) - text_size.y / 2.0)
		_overlay.draw_set_transform(anchor, 0.0, Vector2(inv, inv))
		_overlay.draw_string_outline(_font, baseline, item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, outline)
		_overlay.draw_string(_font, baseline, item.name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	_overlay.draw_set_transform(Vector2.ZERO)


func _add_candidate(out: Array[Dictionary], item: Dictionary, radius: float) -> void:
	var d: float = _focus.distance_to(item.at)
	if d >= radius or item.name.is_empty():
		return
	var candidate := item.duplicate()
	candidate.distance = d
	candidate.fade = _fade(d, radius)
	out.append(candidate)


## Fuente con campo de distancia (MSDF): nítida aunque se escale o se deforme
## en perspectiva, como el texto de las calles.
func _make_font() -> Font:
	var base := ThemeDB.fallback_font
	if base is FontFile:
		var font: FontFile = base.duplicate()
		font.multichannel_signed_distance_field = true
		font.msdf_pixel_range = 8
		font.msdf_size = 48
		return font
	return base
