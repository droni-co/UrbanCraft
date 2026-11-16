class_name DayNight
extends Node
## Ciclo de día y noche.
##
## La hora es la del servidor (GameClock) y la luz depende de la altura real del
## sol donde está el jugador (Sun): amanece y anochece a la misma hora que en
## su ciudad, en cualquier estación. Cambiar el reloj del dispositivo no cambia
## nada.
##
## - Atmosphere tiñe la imagen (luz del día, atardecer dorado, noche azul).
## - De noche se encienden los postes de luz (iluminan el suelo a su alrededor),
##   las ventanas de los edificios (RoofStyles) y una luz suave alrededor del
##   jugador para que no se pierda en la oscuridad.

## Color de la luz según la altura del sol (grados), de noche cerrada a pleno día.
const SKY := [
	[-12.0, Color(0.30, 0.36, 0.62)],
	[-6.0, Color(0.40, 0.41, 0.68)],
	[-2.0, Color(0.78, 0.60, 0.68)],
	[3.0, Color(1.06, 0.80, 0.62)],
	[10.0, Color(1.05, 0.96, 0.88)],
	[20.0, Color(1.0, 1.0, 1.0)],
]
const LAMP_RADIUS := 72.0
const LAMP_INTENSITY := 1.3
const PLAYER_RADIUS := 44.0
const PLAYER_INTENSITY := 0.45
## Cada cuánto se recalcula el sol (la luz cambia despacio).
const UPDATE_SECONDS := 1.0

var atmosphere: Atmosphere
var player: Node2D
## Altura del sol (grados) y cuánto es de noche (0 = día, 1 = noche cerrada).
var sun_elevation := 45.0
var night := 0.0

## Las luces se recalculan cuando la vista sale de este margen (px de mundo),
## no en cada frame.
const VIEW_MARGIN := 96.0

var _lamps := {}  # chunk -> PackedVector2Array (posiciones en el mundo)
## Postes encendidos cerca de la vista y la zona para la que valen.
var _lamp_lights: Array[Vector4] = []
var _lights_view := Rect2()
var _lights_dirty := true
var _lights_on := false
var _elapsed := UPDATE_SECONDS


func setup(atmosphere_layer: Atmosphere, player_node: Node2D) -> void:
	atmosphere = atmosphere_layer
	player = player_node
	_update_sun()


## Postes de luz de un chunk (para iluminarlos de noche).
func add_chunk(chunk: Vector2i, base: Vector2i, size: int, props: PackedByteArray, layer: TileMapLayer) -> void:
	var lamps := PackedVector2Array()
	var i := props.find(WorldTiles.Prop.STREET_LAMP)
	while i != -1 and i < size * size:
		var cell := base + Vector2i(i % size, i / size)
		# La bombilla está arriba del poste; la luz cae en el suelo junto a él.
		lamps.append(layer.to_global(layer.map_to_local(cell)))
		i = props.find(WorldTiles.Prop.STREET_LAMP, i + 1)
	if lamps.is_empty():
		_lamps.erase(chunk)
	else:
		_lamps[chunk] = lamps
	_lights_dirty = true


func remove_chunk(chunk: Vector2i) -> void:
	_lamps.erase(chunk)
	_lights_dirty = true


func clear() -> void:
	_lamps.clear()
	_lights_dirty = true


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= UPDATE_SECONDS:
		_elapsed = 0.0
		_update_sun()
	if atmosphere == null:
		return
	if night <= 0.0:
		if _lights_on:
			_lights_on = false
			_lights_dirty = true
			atmosphere.set_lights([])
		return
	_lights_on = true
	var view := atmosphere.view_rect()
	if _lights_dirty or not _lights_view.encloses(view):
		_collect_lamps(view)
	var lights: Array[Vector4] = _lamp_lights.duplicate()
	if player:
		var center := player.global_position
		lights.append(Vector4(center.x, center.y - 4.0, PLAYER_RADIUS, PLAYER_INTENSITY))
	atmosphere.set_lights(lights)


## Postes que alumbran la vista (y un margen alrededor, para no repetir esto en
## cada frame): los más cercanos a su centro, si hay más de los que caben.
func _collect_lamps(view: Rect2) -> void:
	_lights_dirty = false
	_lights_view = view.grow(VIEW_MARGIN)
	var reach := _lights_view.grow(LAMP_RADIUS)
	var center := view.get_center()
	_lamp_lights.clear()
	for chunk_lamps: PackedVector2Array in _lamps.values():
		for p in chunk_lamps:
			if reach.has_point(p):
				_lamp_lights.append(Vector4(p.x, p.y, LAMP_RADIUS, LAMP_INTENSITY))
	_lamp_lights.sort_custom(func(a: Vector4, b: Vector4) -> bool:
		return Vector2(a.x, a.y).distance_squared_to(center) < Vector2(b.x, b.y).distance_squared_to(center))
	_lamp_lights.resize(mini(_lamp_lights.size(), Atmosphere.max_lights() - 1))


func _update_sun() -> void:
	sun_elevation = Sun.elevation(GameClock.now_unix(), LocationService.latitude, LocationService.longitude)
	night = 1.0 - smoothstep(-8.0, 1.0, sun_elevation)
	if atmosphere:
		atmosphere.set_daylight(sky_color(sun_elevation), night)
	RoofStyles.set_night(night)


static func sky_color(elevation: float) -> Color:
	if elevation <= SKY[0][0]:
		return SKY[0][1]
	for i in range(1, SKY.size()):
		if elevation <= SKY[i][0]:
			var a: Array = SKY[i - 1]
			var b: Array = SKY[i]
			return (a[1] as Color).lerp(b[1], (elevation - a[0]) / (b[0] - a[0]))
	return SKY[-1][1]
