extends Node
## Reloj del juego sincronizado con el servidor.
##
## La hora del día (ciclo de día y noche) sale de la hora del SERVIDOR, no del
## dispositivo: al iniciar se pide GET /api/v1/time y desde ahí se cuenta con el
## reloj monótono del motor (Time.get_ticks_msec), que no cambia aunque el
## jugador adelante o atrase el reloj del sistema. Se vuelve a sincronizar cada
## RESYNC_SECONDS. La hora local sale de la posición del jugador (ver Sun), no de
## su zona horaria.
##
## Sin servidor (modo demo o sin conexión) se usa el reloj del sistema.

signal synced

const RESYNC_SECONDS := 900.0

## Hora UTC del servidor (s desde epoch) en el momento `_sync_ticks`.
var _server_unix := 0.0
var _sync_ticks := 0
var _synced := false
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = RESYNC_SECONDS
	_timer.timeout.connect(sync)
	add_child(_timer)
	_timer.start()
	sync.call_deferred()


func is_synced() -> bool:
	return _synced


## Hora UTC actual en segundos desde epoch.
func now_unix() -> float:
	if not _synced:
		return Time.get_unix_time_from_system()
	return _server_unix + (Time.get_ticks_msec() - _sync_ticks) / 1000.0


func sync() -> void:
	var sent := Time.get_ticks_msec()
	var res: Dictionary = await Api.request_json(HTTPClient.METHOD_GET, "/api/v1/time")
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY or not res.data.has("now"):
		return
	var received := Time.get_ticks_msec()
	# La respuesta salió del servidor más o menos a mitad del viaje.
	_sync_ticks = (sent + received) / 2
	_server_unix = float(res.data.now) / 1000.0
	_synced = true
	synced.emit()
