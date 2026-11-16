class_name MapWindow
extends GameWindow
## Mapa grande: se abre tocando el minimapa. Dibuja el mismo suelo que el
## minimapa (sus texturas y su paleta) más grande, con los lugares del mapa
## (locales, restaurantes, parques…) marcados con el pin de su categoría.
##
## - Arrastrar mueve el mapa; la rueda, el pellizco o los botones +/- hacen zoom.
## - Tocar un lugar muestra su nombre, qué es y a qué distancia queda.
## - "Centrar" vuelve a poner al jugador en el medio.

var _map: BigMap
var _info: Label


func _build() -> void:
	panel_size = Vector2(620, 340)
	title_text = "Mapa"
	_map = BigMap.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.custom_minimum_size = Vector2(200, 120)
	_map.selected.connect(_on_selected)
	body.add_child(_map)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	body.add_child(bar)
	_info = Label.new()
	_info.theme_type_variation = &"HintLabel"
	_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bar.add_child(_info)
	for entry: Array in [["−", func() -> void: _map.zoom_by(1.0 / 1.5)], ["+", func() -> void: _map.zoom_by(1.5)],
			["Centrar", func() -> void: _map.center_on_player()]]:
		var button := GameWindow.small_button(bar, entry[0], entry[1])
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(26 if str(entry[0]).length() == 1 else 0, 22)


## Abre el mapa con los datos que tiene el minimapa.
func open_map(minimap: Minimap) -> void:
	_map.source = minimap
	open()
	_map.reset_view()
	_on_selected({})


func _on_selected(poi: Dictionary) -> void:
	if poi.is_empty():
		_info.text = "Toca un lugar para ver qué es. Arrastra para moverte."
		return
	var meters := float(poi.distance) * _map.source.meters_per_cell
	var distance := "%d m" % roundi(meters) if meters < 1000.0 else "%.1f km" % (meters / 1000.0)
	var what := PoiCatalog.describe(str(poi.kind), str(poi.detail))
	_info.text = "%s · %s · a %s" % [poi.name if str(poi.name) != "" else what, what, distance]


## El lienzo del mapa: suelo, zona de juego, lugares, otros jugadores y tú.
class BigMap:
	extends Control

	signal selected(poi: Dictionary)

	const BACKGROUND := Color(0.04, 0.06, 0.09, 1.0)
	const ZONE_COLOR := Color(1, 1, 1, 0.45)
	const MAX_SCALE := 10.0
	## Píxeles por celda a partir de los que se escriben los nombres de los lugares.
	const LABEL_SCALE := 2.2
	const PIN_RADIUS := 5.0
	## Por debajo de esta escala los lugares son puntos (sin icono) para no tapar el mapa.
	const DOT_SCALE := 0.9
	const START_CELLS := 160.0
	const TAP_DISTANCE := 8.0

	var source: Minimap
	var _scale := 1.0
	var _min_scale := 0.2
	## Celda (relativa al centro del minimapa) que queda en el medio del lienzo.
	var _view := Vector2.ZERO
	var _selected := {}
	var _ground: Control
	var _overlay: Control
	var _touches := {}  # índice -> posición
	var _pinch_distance := 0.0
	var _press_at := Vector2.ZERO
	var _dragging := false
	var _moved := 0.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		_ground = Control.new()
		_ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ground.set_anchors_preset(Control.PRESET_FULL_RECT)
		_ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_ground.draw.connect(_draw_ground)
		add_child(_ground)
		_overlay = Control.new()
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay)
		resized.connect(_refresh)

	## Encuadra la zona de juego y centra al jugador.
	func reset_view() -> void:
		if source == null:
			return
		_ground.material = source.palette_material()
		_selected = {}
		await get_tree().process_frame  # el panel ya tiene su tamaño
		var reach := maxf(source.zone_radius(), 48.0)
		_min_scale = _fit_scale(reach * 1.15)
		# Empieza mostrando el vecindario (unos 300 m alrededor); con zoom out, toda la zona.
		_scale = clampf(_fit_scale(START_CELLS), _min_scale, MAX_SCALE)
		center_on_player()

	func center_on_player() -> void:
		if source:
			_view = source.player_offset()
		_refresh()

	func zoom_by(factor: float, at := Vector2(-1, -1)) -> void:
		var pivot := size / 2.0 if at.x < 0.0 else at
		var cell := _to_cell(pivot)
		_scale = clampf(_scale * factor, _min_scale, MAX_SCALE)
		_view += cell - _to_cell(pivot)  # el punto bajo el cursor no se mueve
		_refresh()

	# --- Proyección (la del minimapa: rombo 2:1) ---

	func _fit_scale(radius_cells: float) -> float:
		var r := radius_cells * sqrt(2.0)
		return maxf(0.05, minf(0.5 * size.x / r, 0.5 * size.y / (r * 0.5)))

	func _iso(v: Vector2) -> Vector2:
		return Vector2(v.x - v.y, (v.x + v.y) * 0.5)

	func _to_screen(cell: Vector2) -> Vector2:
		return size / 2.0 + _iso(cell - _view) * _scale

	func _to_cell(screen: Vector2) -> Vector2:
		var s := (screen - size / 2.0) / _scale
		return _view + Vector2((s.x + 2.0 * s.y) / 2.0, (2.0 * s.y - s.x) / 2.0)

	func _refresh() -> void:
		queue_redraw()
		_ground.queue_redraw()
		_overlay.queue_redraw()

	# --- Dibujo ---

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)

	func _draw_ground() -> void:
		if source == null:
			return
		var x_axis := Vector2(1.0, 0.5) * _scale
		var y_axis := Vector2(-1.0, 0.5) * _scale
		var center := source.center_cell()
		var view := Rect2(Vector2.ZERO, size)
		for origin: Vector2i in source.chunk_data():
			var chunk: Dictionary = source.chunk_data()[origin]
			var base := Vector2(origin - center)
			var side := float(chunk.size)
			# Fuera de la vista no se dibuja (el rombo del chunk cabe en este rectángulo).
			var top := _to_screen(base)
			var bounds := Rect2(top + Vector2(-side, 0) * _scale, Vector2(side * 2.0, side) * _scale)
			if not view.intersects(bounds):
				continue
			_ground.draw_set_transform_matrix(Transform2D(x_axis, y_axis, top))
			_ground.draw_texture(chunk.texture, Vector2.ZERO)
		_ground.draw_set_transform_matrix(Transform2D.IDENTITY)

	func _draw_overlay() -> void:
		if source == null:
			return
		var zone := source.zone_radius()
		if zone > 0.0:
			var points := PackedVector2Array()
			for i in 129:
				var angle := TAU * i / 128.0
				points.append(_to_screen(Vector2(cos(angle), sin(angle)) * zone))
			_overlay.draw_polyline(points, ZONE_COLOR, 1.0, true)

		var font := UiArt.FONT_BOLD
		var taken: Array[Rect2] = []
		var show_names := _scale >= LABEL_SCALE
		var view := Rect2(Vector2.ZERO, size).grow(PIN_RADIUS)
		var pins := _visible_pois(view)
		var chosen := str(_selected.get("id", ""))
		for poi: Dictionary in pins:
			_draw_pin(poi.screen, str(poi.cat), poi.id == chosen)
		# Nombres: primero el seleccionado; los que se pisarían con otro, no.
		pins = pins.filter(func(poi: Dictionary) -> bool: return poi.id != chosen)
		if not _selected.is_empty():
			pins.push_front(_selected.merged({"screen": _to_screen(_selected.cell)}, true))
		for poi: Dictionary in pins:
			var is_selected: bool = poi.id == chosen
			if not (show_names or is_selected) or str(poi.name).is_empty():
				continue
			var text := str(poi.name)
			var font_size := 8 if is_selected else 7
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var rect := Rect2(poi.screen + Vector2(-width / 2.0, -PIN_RADIUS - 11.0), Vector2(width, 9))
			if not is_selected and taken.any(func(other: Rect2) -> bool: return other.intersects(rect)):
				continue
			taken.append(rect)
			var color := MenuTheme.GOLD.lightened(0.3) if is_selected else Color(1, 1, 1, 0.92)
			_overlay.draw_string_outline(font, rect.position + Vector2(0, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 3, Color(0.03, 0.04, 0.08, 0.9))
			_overlay.draw_string(font, rect.position + Vector2(0, 8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

		for other in source.others_near():
			var p := _to_screen(other)
			_overlay.draw_circle(p, 3.5, Color(0, 0, 0, 0.75))
			_overlay.draw_circle(p, 2.5, Color("ffd75e"))
		_draw_player()

	## Lugares dentro de `view`, con su posición en pantalla y distancia al jugador.
	func _visible_pois(view: Rect2) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		var center := source.center_cell()
		var player := source.player_offset()
		for origin: Vector2i in source.chunk_data():
			var base := Vector2(origin - center)
			for poi: Dictionary in source.chunk_data()[origin].pois:
				var cell: Vector2 = base + poi.cell
				var screen := _to_screen(cell)
				if view.has_point(screen):
					result.append(poi.merged({
						"id": "%d:%d" % [origin.x + int(poi.cell.x), origin.y + int(poi.cell.y)],
						"screen": screen, "cell": cell, "distance": cell.distance_to(player)}, true))
		return result

	func _draw_pin(at: Vector2, category: String, highlight: bool) -> void:
		var color := PoiCatalog.color(category)
		if _scale < DOT_SCALE and not highlight:
			_overlay.draw_circle(at, 2.2, Color(0, 0, 0, 0.5))
			_overlay.draw_circle(at, 1.6, color)
			return
		var radius := PIN_RADIUS + (1.5 if highlight else 0.0)
		_overlay.draw_circle(at + Vector2(0, 1), radius + 1.0, Color(0, 0, 0, 0.45))
		_overlay.draw_circle(at, radius + 1.0, MenuTheme.GOLD.lightened(0.3) if highlight else Color(1, 1, 1, 0.95))
		_overlay.draw_circle(at, radius, color)
		var icon := PoiCatalog.icon(category)
		if icon:
			var s := radius * 1.3
			_overlay.draw_texture_rect(icon, Rect2(at - Vector2(s, s) / 2.0, Vector2(s, s)), false)

	func _draw_player() -> void:
		var p := _to_screen(source.player_offset())
		var facing := source.player_facing()
		var f := facing.normalized() if facing != Vector2.ZERO else Vector2.DOWN
		var side := f.orthogonal() * 4.5
		var arrow := PackedVector2Array([p + f * 7.5, p - f * 4.5 + side, p - f * 2.0, p - f * 4.5 - side])
		_overlay.draw_circle(p, 9.0, Color(1, 1, 1, 0.18))
		_overlay.draw_colored_polygon(arrow, Color.WHITE)
		arrow.append(arrow[0])
		_overlay.draw_polyline(arrow, Color(0, 0, 0, 0.85), 1.0, true)

	# --- Entrada: arrastrar, zoom y tocar lugares ---

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventScreenTouch:
			_on_touch(event)
		elif event is InputEventScreenDrag:
			_on_touch_drag(event)
		elif event is InputEventMagnifyGesture:
			zoom_by(event.factor, event.position)
		elif event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION:
			_on_mouse_button(event)
		elif event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION and _dragging:
			_pan(event.relative)
		else:
			return
		accept_event()

	func _on_mouse_button(event: InputEventMouseButton) -> void:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_by(1.15, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_by(1.0 / 1.15, event.position)
			MOUSE_BUTTON_LEFT:
				if Input.emulate_touch_from_mouse:
					return  # llega como toque
				if event.pressed:
					_dragging = true
					_moved = 0.0
					_press_at = event.position
				else:
					_dragging = false
					if _moved <= TAP_DISTANCE:
						_tap(event.position)

	func _on_touch(event: InputEventScreenTouch) -> void:
		if event.pressed:
			_touches[event.index] = event.position
			if _touches.size() == 1:
				_moved = 0.0
				_press_at = event.position
			elif _touches.size() == 2:
				_pinch_distance = _touch_distance()
				_moved = INF  # dos dedos: no es un toque
			return
		var was_single := _touches.size() == 1
		_touches.erase(event.index)
		if was_single and _moved <= TAP_DISTANCE:
			_tap(event.position)
		if _touches.size() == 2:
			_pinch_distance = _touch_distance()

	func _on_touch_drag(event: InputEventScreenDrag) -> void:
		if not _touches.has(event.index):
			return
		var before: Vector2 = _touches[event.index]
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_pan(event.position - before)
		elif _touches.size() == 2:
			var distance := _touch_distance()
			var mid: Vector2 = (_touches.values()[0] + _touches.values()[1]) / 2.0
			if _pinch_distance > 0.0:
				zoom_by(distance / _pinch_distance, mid)
			_pinch_distance = distance
			_pan((event.position - before) / 2.0)

	func _touch_distance() -> float:
		var points := _touches.values()
		return (points[0] as Vector2).distance_to(points[1])

	func _pan(screen_delta: Vector2) -> void:
		_moved += screen_delta.length()
		# El desplazamiento en pantalla vuelto a celdas (inversa del rombo).
		var s := screen_delta / _scale
		_view -= Vector2((s.x + 2.0 * s.y) / 2.0, (2.0 * s.y - s.x) / 2.0)
		_refresh()

	func _tap(at: Vector2) -> void:
		var best := {}
		var best_distance := TAP_DISTANCE + PIN_RADIUS
		for poi: Dictionary in _visible_pois(Rect2(Vector2.ZERO, size).grow(PIN_RADIUS)):
			var d: float = (poi.screen as Vector2).distance_to(at)
			if d <= best_distance:
				best = poi
				best_distance = d
		_selected = best
		selected.emit(best)
		_overlay.queue_redraw()
