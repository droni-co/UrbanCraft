class_name Minimap
extends Control
## Minimapa del mundo con la misma orientación isométrica que la cámara (como
## el minimapa en rombo de los juegos de estrategia): "arriba" significa lo mismo
## en el juego y en el minimapa. Muestra la zona de juego, los POIs y al jugador.
##
## Posición, tamaño, zoom y modo vienen de GameSettings (preferencias del
## usuario) y se aplican en vivo al cambiar.
##
## Rendimiento: cada chunk se sube como textura L8 creada directamente desde sus
## bytes de suelo (sin recorrer celdas en GDScript) y un shader la colorea con
## una paleta. Las capas estáticas solo se redibujan cuando cambian los chunks.

## Colores por id de WorldTiles.Ground (mismo orden): el tono medio de cada
## tile de assets/art. Si cambias mucho el arte, actualízalos.
const GROUND_COLORS: Array[Color] = [
	Color("62a548"),  # GRASS
	Color("3f7136"),  # GRASS_DARK
	Color("9b7249"),  # DIRT
	Color("dfc78e"),  # SAND
	Color("3876cc"),  # WATER
	Color("9c9ca6"),  # STONE
	Color("474a52"),  # ASPHALT
	Color("c9c2b4"),  # PAVEMENT
	Color("a9513b"),  # BUILDING
]

const PALETTE_SHADER := """
shader_type canvas_item;
uniform sampler2D palette : filter_nearest, repeat_disable;
void fragment() {
	float id = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	vec4 c = texture(palette, vec2((id + 0.5) / 256.0, 0.5));
	COLOR = vec4(c.rgb, c.a * COLOR.a);
}
"""

const BACKGROUND := Color(0.04, 0.06, 0.09, 0.55)
const BORDER := Color(1, 1, 1, 0.25)
const ZONE_COLOR := Color(1, 1, 1, 0.4)
const POI_COLOR := Color(0.55, 0.75, 1.0, 0.7)
const COMPASS_SIZE := Vector2(26, 26)

## Celda global en el centro del minimapa (centro de la zona de juego).
var _center := Vector2i.ZERO
## Radio de la zona de juego en celdas (0 = no dibujar el borde de zona).
var _zone_radius := 0.0
## Radio (en celdas) que debe caber completo en el minimapa con zoom 1.
var _fit_radius := 96.0
var _player_offset := Vector2.ZERO
var _player_facing := Vector2.DOWN
var _chunks := {}  # Vector2i (origen global) -> {texture, pois: Array[Vector2]}

var _map_layer: Control
var _static_layer: Control
var _dynamic_layer: Control
var _compass: Compass


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true

	_map_layer = _make_layer()
	_map_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map_layer.material = _make_palette_material()
	_map_layer.draw.connect(_draw_map)

	_static_layer = _make_layer()
	_static_layer.draw.connect(_draw_static)

	_dynamic_layer = _make_layer()
	_dynamic_layer.draw.connect(_draw_dynamic)

	_compass = Compass.new()
	_compass.size = COMPASS_SIZE
	_compass.north = _iso(Vector2(0, -1)).normalized()  # norte = -y en la grilla
	add_child(_compass)

	resized.connect(_redraw_all)
	GameSettings.minimap_settings_changed.connect(_apply_settings)
	_apply_settings()


# --- API pública ----------------------------------------------------------------

## Centro del minimapa (celda global), radio de la zona de juego y radio a encuadrar.
func set_view(center_cell: Vector2i, zone_radius_cells: float, fit_radius_cells := -1.0) -> void:
	_center = center_cell
	_zone_radius = zone_radius_cells
	_fit_radius = fit_radius_cells if fit_radius_cells > 0.0 else maxf(zone_radius_cells, 32.0)
	_redraw_all()


## Agrega un chunk cuadrado. `ground` son size*size ids de suelo; `pois` son
## diccionarios con "cell" local al chunk (formato del backend).
func add_chunk(origin_cell: Vector2i, chunk_size: int, ground: PackedByteArray, pois: Array = []) -> void:
	if ground.size() != chunk_size * chunk_size:
		return
	var image := Image.create_from_data(chunk_size, chunk_size, false, Image.FORMAT_L8, ground)
	var poi_cells: Array[Vector2] = []
	for poi: Dictionary in pois:
		poi_cells.append(Vector2(float(poi.cell[0]) + 0.5, float(poi.cell[1]) + 0.5))
	_chunks[origin_cell] = {"texture": ImageTexture.create_from_image(image), "pois": poi_cells}
	_map_layer.queue_redraw()
	_static_layer.queue_redraw()


func remove_chunk(origin_cell: Vector2i) -> void:
	if _chunks.erase(origin_cell):
		_map_layer.queue_redraw()
		_static_layer.queue_redraw()


func clear() -> void:
	_chunks.clear()
	_redraw_all()


## Posición del jugador en celdas (con decimales) relativa al centro, y su
## dirección en pantalla (la misma que en el juego).
func set_player(offset_cells: Vector2, facing: Vector2) -> void:
	if offset_cells.is_equal_approx(_player_offset) and facing.is_equal_approx(_player_facing):
		return
	_player_offset = offset_cells
	_player_facing = facing
	if GameSettings.minimap_follow_player:
		_redraw_all()
	else:
		_dynamic_layer.queue_redraw()


# --- Disposición ----------------------------------------------------------------

func _apply_settings() -> void:
	visible = GameSettings.minimap_visible
	var s := GameSettings.minimap_size
	var m := GameSettings.minimap_margin
	var right := GameSettings.minimap_corner in [GameSettings.ScreenCorner.TOP_RIGHT, GameSettings.ScreenCorner.BOTTOM_RIGHT]
	var bottom := GameSettings.minimap_corner in [GameSettings.ScreenCorner.BOTTOM_LEFT, GameSettings.ScreenCorner.BOTTOM_RIGHT]

	anchor_left = 1.0 if right else 0.0
	anchor_right = anchor_left
	anchor_top = 1.0 if bottom else 0.0
	anchor_bottom = anchor_top
	offset_left = -m.x - s.x if right else m.x
	offset_right = offset_left + s.x
	# Abajo se usa el margen lateral (la barra superior solo importa arriba).
	offset_top = -m.x - s.y if bottom else m.y
	offset_bottom = offset_top + s.y

	# Brújula en la esquina interior, del lado del centro de la pantalla.
	_compass.visible = GameSettings.compass_visible
	_compass.position = Vector2(2.0 if right else s.x - COMPASS_SIZE.x - 2.0, 2.0)
	_redraw_all()


func _make_layer() -> Control:
	var layer := Control.new()
	layer.mouse_filter = MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	return layer


func _make_palette_material() -> ShaderMaterial:
	var palette := Image.create_empty(256, 1, false, Image.FORMAT_RGBA8)
	palette.fill(Color(0, 0, 0, 0))
	for i in GROUND_COLORS.size():
		palette.set_pixel(i, 0, GROUND_COLORS[i])
	var shader := Shader.new()
	shader.code = PALETTE_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("palette", ImageTexture.create_from_image(palette))
	return material


func _redraw_all() -> void:
	queue_redraw()
	if _map_layer:
		_map_layer.queue_redraw()
		_static_layer.queue_redraw()
		_dynamic_layer.queue_redraw()


# --- Proyección -----------------------------------------------------------------

## Grilla -> pantalla con la misma forma que los tiles 64x32 (diamond-down).
func _iso(v: Vector2) -> Vector2:
	return Vector2(v.x - v.y, (v.x + v.y) * 0.5)


## Píxeles por celda: encuadra _fit_radius en el ancho y alto disponibles.
func _scale() -> float:
	var r := _fit_radius * sqrt(2.0)
	var fit := minf(0.46 * size.x / r, 0.46 * size.y / (r * 0.5))
	return fit * GameSettings.minimap_zoom


func _view_offset() -> Vector2:
	return _player_offset if GameSettings.minimap_follow_player else Vector2.ZERO


## Celdas relativas al centro -> píxeles del minimapa.
func _to_screen(offset_cells: Vector2) -> Vector2:
	return size / 2.0 + _iso(offset_cells - _view_offset()) * _scale()


# --- Dibujo ---------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)


func _draw_map() -> void:
	var s := _scale()
	var x_axis := Vector2(1.0, 0.5) * s
	var y_axis := Vector2(-1.0, 0.5) * s
	for origin: Vector2i in _chunks:
		var screen := _to_screen(Vector2(origin - _center))
		_map_layer.draw_set_transform_matrix(Transform2D(x_axis, y_axis, screen))
		_map_layer.draw_texture(_chunks[origin].texture, Vector2.ZERO)
	_map_layer.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_static() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	for origin: Vector2i in _chunks:
		var base := Vector2(origin - _center)
		for cell: Vector2 in _chunks[origin].pois:
			var p := _to_screen(base + cell)
			if bounds.has_point(p):
				_static_layer.draw_rect(Rect2(p.floor(), Vector2.ONE), POI_COLOR)

	if _zone_radius > 0.0:
		var points := PackedVector2Array()
		for i in 129:
			var angle := TAU * i / 128.0
			points.append(_to_screen(Vector2(cos(angle), sin(angle)) * _zone_radius))
		_static_layer.draw_polyline(points, ZONE_COLOR, 1.0, true)


func _draw_dynamic() -> void:
	var p := _to_screen(_player_offset)
	var f := _player_facing.normalized() if _player_facing != Vector2.ZERO else Vector2.DOWN
	var side := f.orthogonal() * 3.0
	var arrow := PackedVector2Array([p + f * 5.0, p - f * 3.0 + side, p - f * 1.5, p - f * 3.0 - side])
	_dynamic_layer.draw_colored_polygon(arrow, Color.WHITE)
	arrow.append(arrow[0])
	_dynamic_layer.draw_polyline(arrow, Color(0, 0, 0, 0.8), 1.0, true)
	_dynamic_layer.draw_rect(Rect2(Vector2.ZERO, size), BORDER, false, 1.0)
