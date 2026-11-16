class_name WorldObjectsLayer
extends Node
## Objetos que los jugadores dejan en el mapa (materas, puestos, banderas…).
##
## Pide al servidor los de los chunks alrededor del jugador cuando cambia de
## chunk, y los mantiene al día con los avisos del multijugador
## (Game.object_changed). Cada objeto es un Sprite2D en la capa de entidades
## (ordenado por profundidad, como árboles y personajes). No estorban el paso.

## Radio (en chunks) que se mantiene cargado alrededor del jugador.
const RADIUS := 3
## Los sprites están a x4 (192 px → 48 px lógicos) con la base abajo al centro.
const ART_SCALE := 0.25
const SPRITE_OFFSET := Vector2(-96, -176)

## Nodo con y-sort donde van los sprites (Entities).
var container: Node2D
## Celda global (Vector2i) → posición en el mundo del centro de la celda.
var cell_to_world: Callable
var day_night: DayNight

var _objects := {}  # id -> { data, node }
var _by_cell := {}  # Vector2i (celda global) -> id
var _center := Vector2i(-99999, -99999)
var _from := Vector2i.ZERO
var _to := Vector2i(-1, -1)
var _chunk_size := 64
var _request := 0


func _ready() -> void:
	Game.object_changed.connect(_on_changed)


func setup(chunk_size: int) -> void:
	_chunk_size = chunk_size


## Lo llama el mundo con la celda global del jugador.
func update_center(global_cell: Vector2i) -> void:
	var chunk := Vector2i(floori(float(global_cell.x) / _chunk_size), floori(float(global_cell.y) / _chunk_size))
	if chunk == _center:
		return
	_center = chunk
	_load()


## Objeto en una celda global, o {}.
func object_at(global_cell: Vector2i) -> Dictionary:
	var id: Variant = _by_cell.get(global_cell)
	return _objects[id].data if id != null else {}


## El objeto más cercano a una posición dentro de `radius` celdas, o {}. La
## posición va en celdas LOCALES con decimales y `origin` es la celda global del
## origen local (en float de 32 bits las celdas globales no tienen decimales).
func nearest(position: Vector2, origin: Vector2i, radius: float) -> Dictionary:
	var best := {}
	var best_distance := radius
	for id: int in _objects:
		var data: Dictionary = _objects[id].data
		var d := position.distance_to(Vector2(int(data.x) - origin.x + 0.5, int(data.y) - origin.y + 0.5))
		if d <= best_distance:
			best = data
			best_distance = d
	return best


func _load() -> void:
	_request += 1
	var request := _request
	var from := _center - Vector2i(RADIUS, RADIUS)
	var to := _center + Vector2i(RADIUS, RADIUS)
	var list := await Game.objects_in(from, to)
	if request != _request:
		return  # el jugador ya cambió de zona: llegó una respuesta vieja
	_from = from
	_to = to
	var seen := {}
	for data: Dictionary in list:
		seen[int(data.id)] = true
		_put(data)
	for id: int in _objects.keys():
		if not seen.has(id):
			_remove(id)


func _on_changed(op: String, data: Dictionary) -> void:
	if op == "del":
		_remove(int(data.get("id", 0)))
		return
	var chunk := Vector2i(floori(float(data.x) / _chunk_size), floori(float(data.y) / _chunk_size))
	if chunk.x < _from.x or chunk.y < _from.y or chunk.x > _to.x or chunk.y > _to.y:
		return
	_put(data)


func _put(data: Dictionary) -> void:
	var id := int(data.id)
	var cell := Vector2i(int(data.x), int(data.y))
	var entry: Dictionary = _objects.get(id, {})
	if entry.is_empty():
		var node := Node2D.new()
		node.position = container.to_local(cell_to_world.call(cell))
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.centered = false
		sprite.offset = SPRITE_OFFSET
		sprite.scale = Vector2(ART_SCALE, ART_SCALE)
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		node.add_child(sprite)
		container.add_child(node)
		entry = {"data": data, "node": node}
		_objects[id] = entry
		_by_cell[cell] = id
		# Aparece con un saltito.
		node.scale = Vector2(0.6, 0.6)
		node.create_tween().tween_property(node, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	entry.data = data
	_style(entry)


func _style(entry: Dictionary) -> void:
	var data: Dictionary = entry.data
	var node: Node2D = entry.node
	var kind := str(data.kind)
	var sprite: Sprite2D = node.get_node("Sprite")
	var state: Dictionary = data.get("state", {})
	if kind == "farol" and day_night and day_night.night > 0.35:
		sprite.texture = GameArt.object("farol_on")
	else:
		sprite.texture = GameArt.object(kind, state)
	# Las banderas y los estandartes dicen de quién son.
	if kind in ["bandera", "estandarte"] and not node.has_node("Owner"):
		var label := Label.new()
		label.name = "Owner"
		label.text = str(data.get("ownerName", ""))
		label.add_theme_font_override("font", UiArt.FONT_BOLD)
		label.add_theme_font_size_override("font_size", 7)
		label.add_theme_color_override("font_color", Color("ffd38a"))
		label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.9))
		label.add_theme_constant_override("outline_size", 3)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.size = Vector2(80, 10)
		label.position = Vector2(-40, -50)
		label.z_index = 50
		node.add_child(label)


func _remove(id: int) -> void:
	var entry: Dictionary = _objects.get(id, {})
	if entry.is_empty():
		return
	_by_cell.erase(Vector2i(int(entry.data.x), int(entry.data.y)))
	entry.node.queue_free()
	_objects.erase(id)


## De noche se encienden los faroles (se revisa cada tanto, no cada frame).
func refresh_lights() -> void:
	for id: int in _objects:
		if str(_objects[id].data.kind) == "farol":
			_style(_objects[id])
